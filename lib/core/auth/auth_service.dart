import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import 'app_role.dart';
import 'password_hasher.dart';
import 'session_secret_store.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });
  final String id;
  final String username;
  final String displayName;
  final AppRole role;
}

/// Local first-run setup, login, persisted lockout and one-device session.
class AuthService {
  AuthService(this.database, this.secretStore, {
    PasswordHasher? passwordHasher,
    DateTime Function()? clock,
    Random? random,
  }) : passwordHasher = passwordHasher ?? PasswordHasher(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);
  static const Duration sessionDuration = Duration(days: 30);

  final Database database;
  final SessionSecretStore secretStore;
  final PasswordHasher passwordHasher;
  final DateTime Function() _clock;
  final Random _random;

  Future<bool> hasAnyUser() async {
    final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM app_users');
    return (rows.single['count'] as int) > 0;
  }

  Future<String> createInitialManager({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final normalized = _normalizeUsername(username);
    final name = displayName.trim();
    _validatePassword(password);
    if (normalized.length < 3 || name.isEmpty) {
      throw const AuthException('أدخل اسم مستخدم من 3 أحرف على الأقل والاسم الظاهر');
    }
    final passwordHash = await passwordHasher.hash(password);
    final id = _randomHex(16);
    final now = _clock().toUtc().toIso8601String();
    try {
      await database.transaction((txn) async {
        final count = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM app_users'),
        )!;
        if (count != 0) {
          throw const AuthException('تم إنشاء المدير الأول مسبقاً');
        }
        await txn.insert('app_users', {
          'id': id,
          'username': normalized,
          'display_name': name,
          'password_hash': passwordHash,
          'role': AppRole.manager.storageValue,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthException('اسم المستخدم مستخدم بالفعل');
      }
      rethrow;
    }
    return id;
  }

  Future<AuthenticatedUser> login({
    required String username,
    required String password,
  }) async {
    final normalized = _normalizeUsername(username);
    final now = _clock().toUtc();
    final attemptRows = await database.query(
      'auth_login_attempts', where: 'username = ?', whereArgs: [normalized], limit: 1,
    );
    if (attemptRows.isNotEmpty) {
      final until = DateTime.tryParse(attemptRows.single['locked_until'] as String? ?? '');
      if (until != null && until.isAfter(now)) {
        throw const AuthException('تم إيقاف محاولات الدخول مؤقتاً. حاول لاحقاً');
      }
    }
    final users = await database.query(
      'app_users', where: 'username = ?', whereArgs: [normalized], limit: 1,
    );
    if (users.isEmpty) {
      await _recordFailure(normalized, now);
      throw const AuthException('اسم المستخدم أو كلمة المرور غير صحيحة');
    }
    final user = users.single;
    final valid = await passwordHasher.verify(password, user['password_hash']! as String);
    if (!valid || user['is_active'] != 1) {
      await _recordFailure(normalized, now);
      throw const AuthException('اسم المستخدم أو كلمة المرور غير صحيحة');
    }
    await database.delete(
      'auth_login_attempts', where: 'username = ?', whereArgs: [normalized],
    );

    final token = _randomHex(32);
    final tokenHash = await _hashToken(token);
    final sessionId = _randomHex(16);
    await database.insert('auth_sessions', {
      'id': sessionId,
      'user_id': user['id'],
      'token_hash': tokenHash,
      'created_at': now.toIso8601String(),
      'expires_at': now.add(sessionDuration).toIso8601String(),
      'revoked_at': null,
    });
    try {
      await secretStore.write(token);
    } catch (_) {
      await database.update(
        'auth_sessions',
        {'revoked_at': _clock().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [sessionId],
      );
      rethrow;
    }
    return AuthenticatedUser(
      id: user['id']! as String,
      username: user['username']! as String,
      displayName: user['display_name']! as String,
      role: AppRole.fromStorage(user['role']! as String)!,
    );
  }

  Future<AuthenticatedUser?> currentUser() async {
    final token = await secretStore.read();
    if (token == null || token.isEmpty) return null;
    final hash = await _hashToken(token);
    final now = _clock().toUtc().toIso8601String();
    final rows = await database.rawQuery('''
      SELECT u.id, u.username, u.display_name, u.role, u.is_active
      FROM auth_sessions s JOIN app_users u ON u.id = s.user_id
      WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ?
      LIMIT 1
    ''', [hash, now]);
    if (rows.isEmpty || rows.single['is_active'] != 1) {
      await secretStore.delete();
      return null;
    }
    final row = rows.single;
    final role = AppRole.fromStorage(row['role']! as String);
    if (role == null) {
      await secretStore.delete();
      return null;
    }
    return AuthenticatedUser(
      id: row['id']! as String,
      username: row['username']! as String,
      displayName: row['display_name']! as String,
      role: role,
    );
  }

  Future<void> logout() async {
    final token = await secretStore.read();
    if (token != null && token.isNotEmpty) {
      final hash = await _hashToken(token);
      await database.update(
        'auth_sessions',
        {'revoked_at': _clock().toUtc().toIso8601String()},
        where: 'token_hash = ? AND revoked_at IS NULL',
        whereArgs: [hash],
      );
    }
    await secretStore.delete();
  }

  Future<void> _recordFailure(String username, DateTime now) async {
    await database.transaction((txn) async {
      final rows = await txn.query(
        'auth_login_attempts', where: 'username = ?', whereArgs: [username], limit: 1,
      );
      final count = (rows.isEmpty ? 0 : rows.single['failed_attempts'] as int) + 1;
      final lockedUntil = count >= maxFailedAttempts
          ? now.add(lockoutDuration).toIso8601String() : null;
      await txn.insert('auth_login_attempts', {
        'username': username,
        'failed_attempts': count,
        'locked_until': lockedUntil,
        'updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String> _hashToken(String token) async {
    final digest = await Sha256().hash(utf8.encode(token));
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _randomHex(int length) => List<int>.generate(
    length, (_) => _random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String _normalizeUsername(String value) => value.trim().toLowerCase();

  void _validatePassword(String password) {
    if (password.length < 10) {
      throw const AuthException('كلمة المرور يجب ألا تقل عن 10 أحرف');
    }
  }
}
