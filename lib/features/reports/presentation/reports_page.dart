import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/report_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}
class _ReportsPageState extends State<ReportsPage> {
  late final ReportService _reports;
  String _type = 'customers';
  ReportData? _data;
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reports = ReportService(widget.database, AuthorizationService(widget.database, widget.authService));
    _load();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _reports.load(_type);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }
  Future<void> _share(bool pdf) async {
    final data = _data;
    if (data == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      if (pdf) { await _reports.sharePdf(data); } else { await _reports.shareCsv(data); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير التقرير: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('التقارير والتصدير')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'customers', label: Text('العملاء')),
            ButtonSegment(value: 'followups', label: Text('المتابعات')),
            ButtonSegment(value: 'inventory', label: Text('المخزون')),
          ],
          selected: {_type},
          onSelectionChanged: (v) { setState(() => _type = v.first); _load(); },
        ),
        const SizedBox(height: 14),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('لا يمكن عرض هذا التقرير: $_error'))),
        if (_data != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_data!.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('عدد السجلات: ${_data!.rows.length}'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _sharing ? null : () => _share(false), icon: const Icon(Icons.table_view), label: const Text('تصدير CSV')),
              OutlinedButton.icon(onPressed: _sharing ? null : () => _share(true), icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF')),
            ]),
            if (_sharing) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          ]))),
          const SizedBox(height: 10),
          ..._data!.rows.take(50).map((row) => Card(
            child: ListTile(
              dense: true,
              title: Text(row.isEmpty ? '' : row.first),
              subtitle: Text(row.skip(1).where((v) => v.isNotEmpty).join(' • ')),
            ),
          )),
          if (_data!.rows.length > 50) Center(child: Text('تظهر أول 50 سجلاً في المعاينة، ويشمل التصدير جميع السجلات')),
        ],
      ]),
    ),
  );
}
