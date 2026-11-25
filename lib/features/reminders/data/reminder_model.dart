// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';
import 'reminder_model.dart';

/// Local-first follow-up tasks with authorization and an audit trail.
class ReminderRepository {
  ReminderRepository(this.database, this.authorization, {this.policy = const AuthorizationPolicy(), DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now, _random = random ?? Random.secure();

  final Database database;
  final AuthorizationService authorization;
  final AuthorizationPolicy policy;
  final DateTime Function() _clock;
  final Random _random;

  Future<List<ReminderRecord>> list({String? status, int limit = 300}) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.followupRead);
    if (limit < 1 || limit > 500) throw ArgumentError.value(limit, 'limit');
    final clauses = <String>[];
    final args = <Object?>[];
    if (status == 'active') {
      clauses.add("f.status IN ('new', 'scheduled')");
    } else if (status != null) {
      if (!ReminderStatus.values.contains(status)) throw ArgumentError.value(status, 'status');
      clauses.add('f.status = ?');
      args.add(status);
    }
    if (context.role != AppRole.manager && context.role != AppRole.employee) {
      final ids = context.scopedCustomerIds.toList(growable: false);
      if (ids.isEmpty) {
        clauses.add('f.customer_id IS NULL');
      } else {
        clauses.add('(f.customer_id IS NULL OR f.customer_id IN (${List.filled(ids.length, '?').join(',')}))');
        args.addAll(ids);
      }
    }
    final rows = await database.rawQuery('''
      SELECT f.*, c.name AS customer_name
      FROM followups f LEFT JOIN customers c ON c.id = f.customer_id
      ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'}
      ORDER BY CASE f.status WHEN 'completed' THEN 2 WHEN 'cancelled' THEN 3 ELSE 0 END, f.due_at ASC
      LIMIT ?
    ''', [...args, limit]);
    return rows.map(ReminderRecord.fromMap).toList(growable: false);
  }

  Future<List<ReminderCustomer>> customerChoices() async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.customerRead);
    final clauses = <String>['is_archived = 0'];
    final args = <Object?>[];
    if (context.role != AppRole.manager && context.role != AppRole.employee) {
      final ids = context.scopedCustomerIds.toList(growable: false);
      if (ids.isEmpty) return const [];
      clauses.add('id IN (${List.filled(ids.length, '?').join(',')})');
      args.addAll(ids);
    }
    final rows = await database.query('customers', columns: ['id', 'name'], where: clauses.join(' AND '), whereArgs: args, orderBy: 'name COLLATE NOCASE', limit: 500);
    return rows.map((row) => ReminderCustomer(id: row['id']! as String, name: row['name']! as String)).toList(growable: false);
  }

  Future<ReminderRecord> create({required String title, required DateTime dueAt, String? note, String? customerId, String priority = 'normal'}) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.followupCreate);
    final cleanTitle = title.trim();
    final cleanNote = note?.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 180) throw const ReminderValidationException('عنوان المتابعة مطلوب وبحد أقصى 180 حرفاً');
    if (cleanNote != null && cleanNote.length > 2000) throw const ReminderValidationException('الملاحظة طويلة جداً');
    if (!ReminderPriority.values.contains(priority)) throw const ReminderValidationException('أولوية المتابعة غير صحيحة');
    if (customerId != null) {
      policy.requireCustomerAccess(context, customerId);
      final customer = await database.query('customers', columns: ['id'], where: 'id = ? AND is_archived = 0', whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw const ReminderValidationException('العميل غير موجود أو مؤرشف');
    }
    final now = _clock().toUtc();
    final id = _newId();
    await database.transaction((txn) async {
      await txn.insert('followups', {
        'id': id, 'customer_id': customerId, 'title': cleanTitle,
        'note': cleanNote == null || cleanNote.isEmpty ? null : cleanNote,
        'due_at': dueAt.toUtc().toIso8601String(), 'priority': priority,
        'status': 'new', 'assigned_to': context.userId, 'created_by': context.userId,
        'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
      });
      await txn.insert('audit_events', {
        'id': _newId(), 'actor_user_id': context.userId, 'entity_type': 'followup',
        'entity_id': id, 'action': 'followup.create',
        'after_json': jsonEncode({'title': cleanTitle, 'customer_id': customerId, 'due_at': dueAt.toUtc().toIso8601String(), 'priority': priority, 'status': 'new'}),
        'occurred_at': now.toIso8601String(),
      });
    });
    return (await list()).firstWhere((record) => record.id == id);
  }

  Future<void> updateStatus({required String id, required String status, String? outcome}) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.followupUpdate);
    if (!ReminderStatus.values.contains(status)) throw const ReminderValidationException('حالة المتابعة غير صحيحة');
    final cleanOutcome = outcome?.trim();
    if (cleanOutcome != null && cleanOutcome.length > 2000) throw const ReminderValidationException('نتيجة المتابعة طويلة جداً');
    final now = _clock().toUtc();
    await database.transaction((txn) async {
      final rows = await txn.query('followups', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw const ReminderNotFoundException();
      final current = rows.single;
      final customerId = current['customer_id'] as String?;
      if (customerId != null) policy.requireCustomerAccess(context, customerId);
      await txn.update('followups', {
        'status': status, 'updated_at': now.toIso8601String(),
        'completed_at': status == 'completed' ? now.toIso8601String() : null,
        if (cleanOutcome != null && cleanOutcome.isNotEmpty) 'note': cleanOutcome,
      }, where: 'id = ?', whereArgs: [id]);
      await txn.insert('audit_events', {
        'id': _newId(), 'actor_user_id': context.userId, 'entity_type': 'followup',
        'entity_id': id, 'action': 'followup.status.update',
        'before_json': jsonEncode(current),
        'after_json': jsonEncode({'status': status, 'completed_at': status == 'completed' ? now.toIso8601String() : null, if (cleanOutcome != null && cleanOutcome.isNotEmpty) 'note': cleanOutcome}),
        'occurred_at': now.toIso8601String(),
      });
      if (status == 'completed' && customerId != null) {
        await txn.insert('contact_events', {
          'id': _newId(), 'customer_id': customerId, 'contact_type': 'followup',
          'summary': current['title'], 'outcome': cleanOutcome,
          'occurred_at': now.toIso8601String(), 'created_by': context.userId,
        });
      }
    });
  }

  String _newId() => List<int>.generate(16, (_) => _random.nextInt(256)).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

abstract final class ReminderStatus {
  static const values = <String>{'new', 'scheduled', 'completed', 'postponed', 'cancelled'};
}
abstract final class ReminderPriority {
  static const values = <String>{'low', 'normal', 'high', 'urgent'};
}
class ReminderValidationException implements Exception {
  const ReminderValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
class ReminderNotFoundException implements Exception {
  const ReminderNotFoundException();
  @override
  String toString() => 'Reminder not found';
}
