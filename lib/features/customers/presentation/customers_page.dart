// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/customer_model.dart';
import '../data/customer_repository.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}
class _CustomersPageState extends State<CustomersPage> {
  late final AuthorizationService authz;
  late final CustomerRepository repo;
  final search = TextEditingController();
  List<CustomerRecord> customers = [];
  AuthorizationContext? access;
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); authz = AuthorizationService(widget.database, widget.authService); repo = CustomerRepository(widget.database, authz); load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  bool can(String p) => access != null && const AuthorizationPolicy().hasPermission(access!, p);
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final a = await authz.loadContext();
      final rows = await repo.search(search.text);
      if (!mounted) { return; }
      setState(() { access = a; customers = rows; loading = false; });
    } on Object catch (e) {
      if (!mounted) { return; }
      setState(() { error = e is AuthorizationException ? e.message : 'تعذر تحميل العملاء'; loading = false; });
    }
  }
  Future<void> edit([CustomerRecord? customer]) async {
    final draft = await showDialog<CustomerDraft>(context: context, builder: (_) => _CustomerDialog(customer: customer));
    if (draft == null || !mounted) { return; }
    try {
      if (customer == null) { await repo.create(draft); } else { await repo.update(customer.id, draft); }
      await load();
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
  Future<void> archive(CustomerRecord c) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('أرشفة العميل'), content: Text('هل تريد أرشفة ${c.name}؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرشفة'))]));
    if (yes != true) { return; }
    try { await repo.archive(c.id); await load(); }
    on Object { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر أرشفة العميل'))); } }
  }
  @override
  Widget build(BuildContext context) {
    final create = can(AppPermission.customerCreate), update = can(AppPermission.customerUpdate), remove = can(AppPermission.customerArchive), balance = can(AppPermission.balanceRead);
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      floatingActionButton: create ? FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة عميل')) : null,
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(
          controller: search, onChanged: (_) => load(),
          decoration: InputDecoration(hintText: 'ابحث باسم العميل أو رقم الهاتف', prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: () { search.clear(); load(); }, icon: const Icon(Icons.close)), border: const OutlineInputBorder()))),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : error != null
          ? Center(child: Text(error!))
          : customers.isEmpty ? const Center(child: Text('لا يوجد عملاء مطابقون للبحث'))
          : RefreshIndicator(onRefresh: load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88), itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = customers[i];
              return Card(child: ListTile(
                leading: CircleAvatar(child: Text(c.name.characters.first)),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (c.phone != null) Text(c.phone!),
                  if (balance) Text('الرصيد: ${c.currentBalance}'),
                ]),
                onTap: update ? () => edit(c) : null,
                trailing: update || remove ? PopupMenuButton<String>(
                  onSelected: (v) { if (v == 'edit') { edit(c); } if (v == 'archive') { archive(c); } },
                  itemBuilder: (_) => [
                    if (update) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    if (remove) const PopupMenuItem(value: 'archive', child: Text('أرشفة'))]) : null,
              ));
            }))),
      ]),
    );
  }
}
class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer});
  final CustomerRecord? customer;
  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}
class _CustomerDialogState extends State<_CustomerDialog> {
  final keyForm = GlobalKey<FormState>();
  late final TextEditingController name, phone, address, category, notes;
  @override
  void initState() {
    super.initState(); final c = widget.customer;
    name = TextEditingController(text: c?.name ?? ''); phone = TextEditingController(text: c?.phone ?? '');
    address = TextEditingController(text: c?.address ?? ''); category = TextEditingController(text: c?.category ?? '');
    notes = TextEditingController(text: c?.notes ?? '');
  }
  @override
  void dispose() { name.dispose(); phone.dispose(); address.dispose(); category.dispose(); notes.dispose(); super.dispose(); }
  Widget field(TextEditingController c, String label, {bool required = false, int lines = 1, TextInputType? type}) =>
    Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(controller: c, maxLines: lines, keyboardType: type,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.customer == null ? 'إضافة عميل' : 'تعديل بيانات العميل'),
    content: SingleChildScrollView(child: Form(key: keyForm, child: Column(mainAxisSize: MainAxisSize.min, children: [
      field(name, 'اسم العميل', required: true), field(phone, 'رقم الهاتف', type: TextInputType.phone),
      field(address, 'العنوان'), field(category, 'التصنيف'), field(notes, 'ملاحظات', lines: 3)]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      FilledButton(onPressed: () { if (!keyForm.currentState!.validate()) { return; }
        Navigator.pop(context, CustomerDraft(name: name.text, phone: phone.text, address: address.text, category: category.text, notes: notes.text)); },
        child: const Text('حفظ'))]);
}
