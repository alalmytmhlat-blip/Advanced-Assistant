import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';

class AssistantAnswer {
  const AssistantAnswer({required this.title, required this.message, this.details = const [], this.source = 'قاعدة البيانات المحلية'});
  final String title;
  final String message;
  final List<String> details;
  final String source;
}

/// Read-only Arabic assistant with fixed SQL templates and permission checks.
class LocalAssistantService {
  LocalAssistantService(this.database, this.authorization);
  final Database database;
  final AuthorizationService authorization;

  Future<AssistantAnswer> ask(String input) async {
    final query = _normalize(input);
    if (query.isEmpty) return const AssistantAnswer(title: 'اكتب سؤالك', message: 'يمكنني البحث عن عميل أو عرض المتابعات المتأخرة أو الأصناف منخفضة الكمية.');
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();

    if (_hasAny(query, ['متاخر', 'المتأخر', 'المتأخره', 'المتأخرة'])) {
      policy.requirePermission(context, AppPermission.followupRead);
      final scope = _scope(context, column: 'customer_id', nullable: true);
      final rows = await database.rawQuery(
        "SELECT title, due_at FROM followups WHERE status IN ('new','scheduled','postponed') AND due_at < ?${scope.sql} ORDER BY due_at LIMIT 20",
        [DateTime.now().toUtc().toIso8601String(), ...scope.args],
      );
      return AssistantAnswer(
        title: 'المتابعات المتأخرة',
        message: 'عدد النتائج المعروضة: ${rows.length}.',
        details: rows.map((r) => '${r['title']} — ${r['due_at']}').toList(),
      );
    }

    if (_hasAny(query, ['مخزون', 'كمية', 'كميات', 'ناقص', 'منخفض', 'نفد'])) {
      policy.requirePermission(context, AppPermission.inventoryRead);
      final rows = await database.rawQuery(
        'SELECT original_name, quantity, minimum_quantity, unit FROM inventory_items WHERE is_archived = 0 AND CAST(quantity AS REAL) <= CAST(minimum_quantity AS REAL) ORDER BY original_name COLLATE NOCASE LIMIT 30',
      );
      return AssistantAnswer(
        title: 'الأصناف عند حد التنبيه أو أقل',
        message: 'عدد النتائج المعروضة: ${rows.length}.',
        details: rows.map((r) => '${r['original_name']}: ${r['quantity']} ${r['unit']} (الحد ${r['minimum_quantity']})').toList(),
      );
    }

    if (_hasAny(query, ['رصيد', 'ارصدة', 'حساب', 'مديون', 'مديونية'])) {
      policy.requirePermission(context, AppPermission.balanceRead);
      final term = _extractTerm(input, ['رصيد', 'ارصدة', 'حساب', 'العميل', 'عميل']);
      if (term.isEmpty) return const AssistantAnswer(title: 'رصيد عميل', message: 'اكتب اسم العميل بعد كلمة رصيد، مثل: رصيد أحمد.');
      final scope = _scope(context, column: 'id');
      final rows = await database.rawQuery(
        'SELECT name, current_balance FROM customers WHERE is_archived = 0 AND name LIKE ?${scope.sql} ORDER BY name COLLATE NOCASE LIMIT 10',
        ['%$term%', ...scope.args],
      );
      if (rows.isEmpty) return AssistantAnswer(title: 'لم أعثر على العميل', message: 'لا يوجد عميل مطابق لعبارة «$term» ضمن البيانات المسموح لك بها.');
      return AssistantAnswer(title: 'أرصدة العملاء المطابقة', message: 'أرصدة حالية كما هي محفوظة، دون أي تعديل.', details: rows.map((r) => '${r['name']}: ${r['current_balance']}').toList());
    }

    if (_hasAny(query, ['عدد العملاء', 'كم عميل'])) {
      policy.requirePermission(context, AppPermission.customerRead);
      final scope = _scope(context, column: 'id');
      final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM customers WHERE is_archived = 0${scope.sql}', scope.args);
      return AssistantAnswer(title: 'عدد العملاء', message: 'عدد العملاء النشطين: ${rows.single['count']}.');
    }

    if (_hasAny(query, ['عميل', 'العملاء', 'ابحث', 'بحث'])) {
      policy.requirePermission(context, AppPermission.customerRead);
      final term = _extractTerm(input, ['ابحث عن', 'بحث عن', 'العملاء', 'عميل', 'عن']);
      if (term.isEmpty) return const AssistantAnswer(title: 'البحث عن عميل', message: 'اكتب اسم العميل أو جزءًا منه بعد كلمة عميل.');
      final scope = _scope(context, column: 'id');
      final rows = await database.rawQuery(
        'SELECT name, phone, address FROM customers WHERE is_archived = 0 AND (name LIKE ? OR phone LIKE ?)${scope.sql} ORDER BY name COLLATE NOCASE LIMIT 15',
        ['%$term%', '%$term%', ...scope.args],
      );
      if (rows.isEmpty) return AssistantAnswer(title: 'لا توجد نتائج', message: 'لم أعثر على عميل مطابق لعبارة «$term».');
      return AssistantAnswer(title: 'نتائج البحث عن العملاء', message: 'عدد النتائج المعروضة: ${rows.length}.', details: rows.map((r) => '${r['name']} — ${r['phone'] ?? 'بدون هاتف'}').toList());
    }

    return const AssistantAnswer(
      title: 'أستطيع مساعدتك محليًا',
      message: 'جرّب: «ابحث عن عميل أحمد»، «رصيد أحمد»، «المتابعات المتأخرة»، «الأصناف منخفضة المخزون»، أو «عدد العملاء». لا يتم إرسال بياناتك إلى الإنترنت.',
    );
  }

  ({String sql, List<Object?> args}) _scope(AuthorizationContext context, {required String column, bool nullable = false}) {
    if (context.role == AppRole.manager || context.role == AppRole.employee) return (sql: '', args: <Object?>[]);
    final ids = context.scopedCustomerIds.toList(growable: false);
    if (ids.isEmpty) return (sql: nullable ? ' AND $column IS NULL' : ' AND 1 = 0', args: <Object?>[]);
    final placeholders = ids.map((_) => '?').join(',');
    return (sql: nullable ? ' AND ($column IS NULL OR $column IN ($placeholders))' : ' AND $column IN ($placeholders)', args: ids);
  }

  String _normalize(String value) => value
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي').toLowerCase().trim();

  bool _hasAny(String value, List<String> terms) => terms.any((term) => value.contains(_normalize(term)));

  String _extractTerm(String input, List<String> prefixes) {
    var value = _normalize(input);
    for (final prefix in prefixes) { value = value.replaceAll(_normalize(prefix), ' '); }
    return value.replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
