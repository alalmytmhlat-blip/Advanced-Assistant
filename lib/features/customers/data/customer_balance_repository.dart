import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';
import 'balance_change_model.dart';

/// Changes signed customer balances atomically and preserves a complete audit trail.
class CustomerBalanceRepository {
  CustomerBalanceRepository(
    this.database,
    this.authorization, {
    this.policy = const AuthorizationPolicy(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Database database;
  final AuthorizationService authorization;
  final AuthorizationPolicy policy;
  final DateTime Function() _clock;
  final Random _random;

  Future<String> readBalance(String customerId) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.balanceRead);
    policy.requireCustomerAccess(context, customerId);
    final rows = await database.query(
      'customers',
      columns: ['current_balance'],
      where: 'id = ? AND is_archived = 0',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) throw const BalanceCustomerNotFoundException();
    return _ExactDecimal.parse(rows.single['current_balance']! as String);
  }

  Future<List<BalanceChangeRecord>> history(
    String customerId, {
    int limit = 100,
  }) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.balanceRead);
    policy.requireCustomerAccess(context, customerId);
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 500');
    }
    final rows = await database.query(
      'customer_balance_changes',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'changed_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(BalanceChangeRecord.fromMap).toList(growable: false);
  }

  Future<BalanceChangeRecord> updateBalance({
    required String customerId,
    required String newBalance,
    required String reason,
  }) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.balanceUpdate);
    policy.requireCustomerAccess(context, customerId);

    final normalizedNew = _ExactDecimal.parse(newBalance);
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const BalanceValidationException('سبب تعديل الرصيد مطلوب');
    }
    if (cleanReason.length > 500) {
      throw const BalanceValidationException('سبب التعديل طويل جداً');
    }

    final changeId = _newId();
    final now = _clock().toUtc().toIso8601String();
    late final BalanceChangeRecord result;

    await database.transaction((txn) async {
      final rows = await txn.query(
        'customers',
        columns: ['current_balance'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [customerId],
        limit: 1,
      );
      if (rows.isEmpty) throw const BalanceCustomerNotFoundException();

      final previous = _ExactDecimal.parse(
        rows.single['current_balance']! as String,
      );
      if (previous == normalizedNew) {
        throw const BalanceValidationException('الرصيد الجديد مطابق للرصيد الحالي');
      }

      await txn.update(
        'customers',
        {'current_balance': normalizedNew, 'updated_at': now},
        where: 'id = ? AND is_archived = 0',
        whereArgs: [customerId],
      );
      await txn.insert('customer_balance_changes', {
        'id': changeId,
        'customer_id': customerId,
        'previous_balance': previous,
        'new_balance': normalizedNew,
        'reason': cleanReason,
        'changed_by': context.userId,
        'changed_at': now,
      });
      await txn.insert('audit_events', {
        'id': _newId(),
        'actor_user_id': context.userId,
        'entity_type': 'customer_balance',
        'entity_id': customerId,
        'action': 'balance.update',
        'before_json': jsonEncode({'current_balance': previous}),
        'after_json': jsonEncode({'current_balance': normalizedNew}),
        'reason': cleanReason,
        'operation_id': changeId,
        'occurred_at': now,
      });
      result = BalanceChangeRecord(
        id: changeId,
        customerId: customerId,
        previousBalance: previous,
        newBalance: normalizedNew,
        reason: cleanReason,
        changedBy: context.userId,
        changedAt: now,
      );
    });
    return result;
  }

  String _newId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

class BalanceCustomerNotFoundException implements Exception {
  const BalanceCustomerNotFoundException();
  @override
  String toString() => 'Customer not found';
}

/// Decimal parser/normalizer based only on BigInt; no binary floating point.
class _ExactDecimal {
  static final _pattern = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$');

  static String parse(String input) {
    final value = input.trim();
    if (value.length > 120 || !_pattern.hasMatch(value)) {
      throw const BalanceValidationException('أدخل رصيداً رقمياً صحيحاً');
    }

    var unsigned = value;
    var negative = false;
    if (unsigned.startsWith('-')) {
      negative = true;
      unsigned = unsigned.substring(1);
    } else if (unsigned.startsWith('+')) {
      unsigned = unsigned.substring(1);
    }

    final parts = unsigned.split('.');
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final fraction = parts.length == 2 ? parts[1] : '';
    var coefficient = BigInt.parse(whole + fraction);
    var scale = fraction.length;

    while (scale > 0 && coefficient % BigInt.from(10) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    if (coefficient == BigInt.zero) return '0';

    if (scale == 0) {
      return '${negative ? '-' : ''}${coefficient.toString()}';
    }
    final digits = coefficient.toString().padLeft(scale + 1, '0');
    final splitAt = digits.length - scale;
    final integerPart = digits.substring(0, splitAt);
    final fractionalPart = digits.substring(splitAt);
    return '${negative ? '-' : ''}$integerPart.$fractionalPart';
  }
}
