// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';

class InventoryItemRecord {
  const InventoryItemRecord({required this.id, required this.name, required this.quantity, required this.minimumQuantity, required this.unit, this.code, this.size, this.category, this.notes});
  final String id;
  final String name;
  final String quantity;
  final String minimumQuantity;
  final String unit;
  final String? code;
  final String? size;
  final String? category;
  final String? notes;
  bool get isLowStock => _decimalCompare(quantity, minimumQuantity) <= 0;

  factory InventoryItemRecord.fromMap(Map<String, Object?> row) => InventoryItemRecord(
    id: row['id']! as String,
    name: row['original_name']! as String,
    quantity: row['quantity']! as String,
    minimumQuantity: row['minimum_quantity']! as String,
    unit: row['unit']! as String,
    code: row['original_code'] as String?,
    size: row['original_size'] as String?,
    category: row['category_name'] as String?,
    notes: row['notes'] as String?,
  );
}

/// Inventory data access. Every write is permission-checked and audited.
class InventoryRepository {
  InventoryRepository(this.database, this.authorization, {DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now, _random = random ?? Random.secure();
  final Database database;
  final AuthorizationService authorization;
  final DateTime Function() _clock;
  final Random _random;

  Future<List<InventoryItemRecord>> list({String query = '', bool includeArchived = false, int limit = 500}) async {
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();
    policy.requirePermission(context, AppPermission.inventoryRead);
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit');
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeArchived) clauses.add('i.is_archived = 0');
    final clean = query.trim();
    if (clean.isNotEmpty) {
      clauses.add('(i.original_name LIKE ? OR i.original_code LIKE ? OR i.original_size LIKE ?)');
      args.addAll(['%$clean%', '%$clean%', '%$clean%']);
    }
    final rows = await database.rawQuery('''
      SELECT i.*, c.name AS category_name FROM inventory_items i
      LEFT JOIN inventory_categories c ON c.id = i.category_id
      ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'}
      ORDER BY i.original_name COLLATE NOCASE LIMIT ?
    ''', [...args, limit]);
    return rows.map(InventoryItemRecord.fromMap).toList(growable: false);
  }

  Future<void> create({required String name, String? code, String? size, String unit = '', String? category, required String quantity, String minimumQuantity = '0', String? notes}) async {
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();
    policy.requirePermission(context, AppPermission.inventoryManage);
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 240) throw const InventoryValidationException('اسم الصنف مطلوب وبحد أقصى 240 حرفاً');
    final qty = _normalizeDecimal(quantity);
    final min = _normalizeDecimal(minimumQuantity);
    if (_decimalCompare(qty, '0') < 0 || _decimalCompare(min, '0') < 0) throw const InventoryValidationException('الكمية وحد التنبيه لا يمكن أن يكونا سالبين');
    final now = _clock().toUtc().toIso8601String();
    final id = _newId();
    await database.transaction((txn) async {
      String? categoryId;
      final categoryName = category?.trim();
      if (categoryName != null && categoryName.isNotEmpty) {
        final found = await txn.query('inventory_categories', columns: ['id'], where: 'name = ?', whereArgs: [categoryName], limit: 1);
        if (found.isEmpty) {
          categoryId = _newId();
          await txn.insert('inventory_categories', {'id': categoryId, 'name': categoryName, 'created_at': now});
        } else {
          categoryId = found.single['id']! as String;
        }
      }
      await txn.insert('inventory_items', {
        'id': id, 'original_name': cleanName, 'original_code': _clean(code),
        'original_size': _clean(size), 'unit': unit.trim(), 'category_id': categoryId,
        'quantity': qty, 'minimum_quantity': min, 'notes': _clean(notes),
        'is_archived': 0, 'created_at': now, 'updated_at': now,
      });
      await txn.insert('audit_events', {
        'id': _newId(), 'actor_user_id': context.userId, 'entity_type': 'inventory_item',
        'entity_id': id, 'action': 'inventory.create',
        'after_json': jsonEncode({'name': cleanName, 'code': code, 'size': size, 'quantity': qty, 'minimum_quantity': min}),
        'occurred_at': now,
      });
    });
  }

  Future<void> updateQuantity({required String itemId, required String quantity, required String reason}) async {
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();
    policy.requirePermission(context, AppPermission.inventoryManage);
    final next = _normalizeDecimal(quantity);
    if (_decimalCompare(next, '0') < 0) throw const InventoryValidationException('لا يمكن حفظ كمية سالبة');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) throw const InventoryValidationException('سبب تعديل الكمية مطلوب وبحد أقصى 500 حرف');
    final now = _clock().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows = await txn.query('inventory_items', where: 'id = ? AND is_archived = 0', whereArgs: [itemId], limit: 1);
      if (rows.isEmpty) throw const InventoryNotFoundException();
      final old = rows.single['quantity']! as String;
      if (old == next) throw const InventoryValidationException('الكمية الجديدة مطابقة للكمية الحالية');
      await txn.update('inventory_items', {'quantity': next, 'updated_at': now}, where: 'id = ?', whereArgs: [itemId]);
      await txn.insert('audit_events', {
        'id': _newId(), 'actor_user_id': context.userId, 'entity_type': 'inventory_item',
        'entity_id': itemId, 'action': 'inventory.quantity.update',
        'before_json': jsonEncode({'quantity': old}),
        'after_json': jsonEncode({'quantity': next, 'reason': cleanReason}),
        'reason': cleanReason, 'occurred_at': now,
      });
    });
  }

  Future<void> archive(String itemId) async {
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();
    policy.requirePermission(context, AppPermission.inventoryManage);
    final now = _clock().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows = await txn.query('inventory_items', where: 'id = ? AND is_archived = 0', whereArgs: [itemId], limit: 1);
      if (rows.isEmpty) throw const InventoryNotFoundException();
      await txn.update('inventory_items', {'is_archived': 1, 'updated_at': now}, where: 'id = ?', whereArgs: [itemId]);
      await txn.insert('audit_events', {'id': _newId(), 'actor_user_id': context.userId, 'entity_type': 'inventory_item', 'entity_id': itemId, 'action': 'inventory.archive', 'before_json': jsonEncode(rows.single), 'occurred_at': now});
    });
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
  String _newId() => List<int>.generate(16, (_) => _random.nextInt(256)).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

String _normalizeDecimal(String value) {
  final v = value.trim();
  if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(v)) throw const InventoryValidationException('أدخل كمية رقمية صحيحة حتى 4 منازل عشرية');
  final parts = v.split('.');
  final whole = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = parts.length == 1 ? '' : parts.last.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

int _decimalCompare(String left, String right) {
  final a = left.split('.'); final b = right.split('.');
  final scale = (a.length > 1 ? a[1].length : 0).compareTo(b.length > 1 ? b[1].length : 0) >= 0
      ? (a.length > 1 ? a[1].length : 0) : (b.length > 1 ? b[1].length : 0);
  final ai = BigInt.parse(a.first) * BigInt.from(10).pow(scale) + BigInt.parse((a.length > 1 ? a[1] : '').padRight(scale, '0').isEmpty ? '0' : (a.length > 1 ? a[1] : '').padRight(scale, '0'));
  final bi = BigInt.parse(b.first) * BigInt.from(10).pow(scale) + BigInt.parse((b.length > 1 ? b[1] : '').padRight(scale, '0').isEmpty ? '0' : (b.length > 1 ? b[1] : '').padRight(scale, '0'));
  return ai.compareTo(bi);
}

class InventoryValidationException implements Exception {
  const InventoryValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
class InventoryNotFoundException implements Exception {
  const InventoryNotFoundException();
  @override
  String toString() => 'Inventory item not found';
}
