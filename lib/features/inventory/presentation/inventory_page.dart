// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/inventory_repository.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final InventoryRepository _repo;
  final _search = TextEditingController();
  List<InventoryItemRecord> _items = const [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _repo = InventoryRepository(widget.database, AuthorizationService(widget.database, widget.authService));
    _load();
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _repo.list(query: _search.text);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'تعذر تحميل المخزون: $e'; _loading = false; });
    }
  }
  Future<void> _add() async {
    final name = TextEditingController(); final code = TextEditingController();
    final size = TextEditingController(); final unit = TextEditingController(text: 'قطعة');
    final category = TextEditingController(); final qty = TextEditingController(text: '0');
    final min = TextEditingController(text: '0');
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إضافة صنف للمخزون'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(name, 'اسم الصنف *'), _field(code, 'الكود الأصلي'), _field(size, 'المقاس الأصلي'),
        _field(unit, 'الوحدة'), _field(category, 'الفئة'), _field(qty, 'الكمية الحالية'),
        _field(min, 'حد التنبيه الأدنى'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
    ));
    if (result == true) {
      try {
        await _repo.create(name: name.text, code: code.text, size: size.text, unit: unit.text, category: category.text, quantity: qty.text, minimumQuantity: min.text);
        await _load();
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    }
    for (final c in [name, code, size, unit, category, qty, min]) { c.dispose(); }
  }
  Future<void> _change(InventoryItemRecord item) async {
    final qty = TextEditingController(text: item.quantity); final reason = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('تحديث كمية ${item.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [_field(qty, 'الكمية الجديدة'), _field(reason, 'سبب التعديل *')]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد'))],
    ));
    if (result == true) {
      try { await _repo.updateQuantity(itemId: item.id, quantity: qty.text, reason: reason.text); await _load(); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التعديل: $e'))); }
    }
    qty.dispose(); reason.dispose();
  }
  Widget _field(TextEditingController c, String label) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('إدارة المخزون'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _search, onSubmitted: (_) => _load(), decoration: InputDecoration(labelText: 'بحث بالاسم أو الكود أو المقاس', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.arrow_forward))))),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : _items.isEmpty ? const Center(child: Text('لا توجد أصناف مسجلة')) : RefreshIndicator(onRefresh: _load, child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) { final item = _items[index]; return Card(child: ListTile(
          title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(['الكود: ${item.code ?? '—'}', 'المقاس: ${item.size ?? '—'}', 'الفئة: ${item.category ?? '—'}', 'الكمية: ${item.quantity} ${item.unit}', 'حد التنبيه: ${item.minimumQuantity}'].join(' • ')),
          trailing: Icon(item.isLowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, color: item.isLowStock ? Theme.of(context).colorScheme.error : null),
          onTap: () => _change(item),
        )); },
      ))),
    ]),
  ));
}
