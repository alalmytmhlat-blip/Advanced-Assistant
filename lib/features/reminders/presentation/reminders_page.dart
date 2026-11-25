// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/reminder_model.dart';
import '../data/reminder_repository.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late final ReminderRepository _repository;
  List<ReminderRecord> _items = const [];
  List<ReminderCustomer> _customers = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'active';

  @override
  void initState() {
    super.initState();
    _repository = ReminderRepository(widget.database, AuthorizationService(widget.database, widget.authService));
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final status = switch (_filter) {
        'active' => null, 'completed' => 'completed', 'postponed' => 'postponed', _ => null,
      };
      final results = await Future.wait([_repository.list(status: status), _repository.customerChoices()]);
      if (!mounted) return;
      setState(() { _items = results[0] as List<ReminderRecord>; _customers = results[1] as List<ReminderCustomer>; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = 'تعذر تحميل المتابعات: $error'; _loading = false; });
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final note = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(hours: 1));
    String priority = 'normal';
    String? customerId;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('متابعة جديدة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان المتابعة *')),
          const SizedBox(height: 10),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظة')),
          const SizedBox(height: 10),
          if (_customers.isNotEmpty) DropdownButtonFormField<String?>(
            value: customerId,
            decoration: const InputDecoration(labelText: 'ربط بعميل (اختياري)'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('بدون عميل')), ..._customers.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))],
            onChanged: (value) => setDialogState(() => customerId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: priority, decoration: const InputDecoration(labelText: 'الأولوية'),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('منخفضة')),
              DropdownMenuItem(value: 'normal', child: Text('عادية')),
              DropdownMenuItem(value: 'high', child: Text('مرتفعة')),
              DropdownMenuItem(value: 'urgent', child: Text('عاجلة')),
            ],
            onChanged: (value) => setDialogState(() => priority = value ?? 'normal'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event),
            title: const Text('التاريخ والوقت'), subtitle: Text(_formatDate(due)),
            onTap: () async {
              final date = await showDatePicker(context: context, initialDate: due, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (date == null || !dialogContext.mounted) return;
              final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(due));
              if (time != null) setDialogState(() => due = DateTime(date.year, date.month, date.day, time.hour, time.minute));
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
        ],
      )),
    );
    if (result == true) {
      try {
        await _repository.create(title: title.text, note: note.text, dueAt: due, priority: priority, customerId: customerId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المتابعة')));
        await _load();
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $error')));
      }
    }
    title.dispose();
    note.dispose();
  }

  Future<void> _changeStatus(ReminderRecord item, String status) async {
    try { await _repository.updateStatus(id: item.id, status: status); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث المتابعة: $error'))); }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('المتابعات والتذكيرات'), actions: [IconButton(onPressed: _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('متابعة جديدة')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'active', label: Text('النشطة'), icon: Icon(Icons.pending_actions)),
            ButtonSegment(value: 'completed', label: Text('المكتملة'), icon: Icon(Icons.task_alt)),
            ButtonSegment(value: 'postponed', label: Text('المؤجلة'), icon: Icon(Icons.snooze)),
          ],
          selected: {_filter},
          onSelectionChanged: (value) { setState(() => _filter = value.first); _load(); },
        )),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
          : _items.isEmpty ? const Center(child: Text('لا توجد متابعات في هذا القسم'))
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), itemCount: _items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ReminderCard(
              item: _items[index],
              onComplete: () => _changeStatus(_items[index], 'completed'),
              onPostpone: () => _changeStatus(_items[index], 'postponed'),
              onSchedule: () => _changeStatus(_items[index], 'scheduled'),
            ),
          ))),
      ]),
    ),
  );

  String _formatDate(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} — ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.item, required this.onComplete, required this.onPostpone, required this.onSchedule});
  final ReminderRecord item;
  final VoidCallback onComplete;
  final VoidCallback onPostpone;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final overdue = item.dueAt.isBefore(DateTime.now()) && item.status != 'completed' && item.status != 'cancelled';
    final priority = switch (item.priority) {'urgent' => 'عاجلة', 'high' => 'مرتفعة', 'low' => 'منخفضة', _ => 'عادية'};
    final status = switch (item.status) {'completed' => 'مكتملة', 'scheduled' => 'مجدولة', 'postponed' => 'مؤجلة', 'cancelled' => 'ملغاة', _ => 'جديدة'};
    final d = item.dueAt;
    final date = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        if (overdue) const Chip(label: Text('متأخرة'), avatar: Icon(Icons.warning_amber, size: 16)),
      ]),
      if (item.customerName != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('العميل: ${item.customerName}')),
      if (item.note != null && item.note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.note!)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [Chip(avatar: const Icon(Icons.schedule, size: 16), label: Text(date)), Chip(label: Text('الأولوية: $priority')), Chip(label: Text(status))]),
      if (item.status != 'completed' && item.status != 'cancelled') Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
        TextButton.icon(onPressed: onComplete, icon: const Icon(Icons.check_circle_outline), label: const Text('تمت')),
        TextButton.icon(onPressed: onSchedule, icon: const Icon(Icons.event_repeat), label: const Text('جدولة')),
        TextButton.icon(onPressed: onPostpone, icon: const Icon(Icons.snooze), label: const Text('تأجيل')),
      ]),
    ])));
  }
}
