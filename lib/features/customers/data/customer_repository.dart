import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/auth/app_permission.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';
import 'customer_model.dart';

/// Permission-enforced SQLite access to the customer directory.
class CustomerRepository {
  CustomerRepository(
    this.database,
    this.authorization, {
    AuthorizationPolicy policy = const AuthorizationPolicy(),
    DateTime Function()? clock,
    Random? random,
  }) : policy = policy,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Database database;
  final AuthorizationService authorization;
  final AuthorizationPolicy policy;
  final DateTime Function() _clock;
  final Random _random;

  Future<List<CustomerRecord>> search(
    String query, {
    bool includeArchived = false,
  }) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.customerRead);

    final term = query.trim();
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeArchived) clauses.add('is_archived = 0');
    if (term.isNotEmpty) {
      clauses.add('(name LIKE ? OR phone LIKE ?)');
      args
        ..add('%$term%')
        ..add('%$term%');
    }
    if (context.role != AppRole.manager &&
        context.role != AppRole.employee) {
      if (context.scopedCustomerIds.isEmpty) return const [];
      final ids = context.scopedCustomerIds.toList(growable: false);
      clauses.add('id IN (${List.filled(ids.length, '?').join(',')})');
      args.addAll(ids);
    }

    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final rows = await database.query(
      'customers',
      where: where,
      whereArgs: where == null ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(CustomerRecord.fromMap).toList(growable: false);
  }

  Future<CustomerRecord?> getById(String customerId) async {
    final context = await authorization.loadContext();
    policy.requireCustomerAccess(context, customerId);
    final rows = await database.query(
      'customers',
      where: 'id = ? AND is_archived = 0',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isEmpty ? null : CustomerRecord.fromMap(rows.single);
  }

  Future<CustomerRecord> create(CustomerDraft draft) async {
    final context = await authorization.loadContext();
    policy.requirePermission(context, AppPermission.customerCreate);
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw const CustomerValidationException('اسم العميل مطلوب');
    }
    final now = _clock().toUtc().toIso8601String();
    final id = _newId();
    await database.insert('customers', {
      'id': id,
      'name': name,
      'phone': _clean(draft.phone),
      'address': _clean(draft.address),
      'category': _clean(draft.category),
      'notes': _clean(draft.notes),
      'current_balance': '0',
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
    });
    final rows = await database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return CustomerRecord.fromMap(rows.single);
  }

  Future<CustomerRecord> update(
    String customerId,
    CustomerDraft draft,
  ) async {
    final context = await authorization.loadContext();
    policy.requireCustomerAccess(context, customerId);
    policy.requirePermission(context, AppPermission.customerUpdate);
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw const CustomerValidationException('اسم العميل مطلوب');
    }
    final updated = await database.update(
      'customers',
      {
        'name': name,
        'phone': _clean(draft.phone),
        'address': _clean(draft.address),
        'category': _clean(draft.category),
        'notes': _clean(draft.notes),
        'updated_at': _clock().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_archived = 0',
      whereArgs: [customerId],
    );
    if (updated == 0) {
      throw const CustomerNotFoundException();
    }
    final rows = await database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return CustomerRecord.fromMap(rows.single);
  }

  Future<void> archive(String customerId) async {
    final context = await authorization.loadContext();
    policy.requireCustomerAccess(context, customerId);
    policy.requirePermission(context, AppPermission.customerArchive);
    final changed = await database.update(
      'customers',
      {
        'is_archived': 1,
        'updated_at': _clock().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_archived = 0',
      whereArgs: [customerId],
    );
    if (changed == 0) throw const CustomerNotFoundException();
  }

  String _newId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}

class CustomerValidationException implements Exception {
  const CustomerValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CustomerNotFoundException implements Exception {
  const CustomerNotFoundException();
  @override
  String toString() => 'Customer not found';
}
