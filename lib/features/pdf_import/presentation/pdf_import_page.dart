// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/pdf_import_service.dart';

class PdfImportPage extends StatefulWidget {
  const PdfImportPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<PdfImportPage> createState() => _PdfImportPageState();
}
class _PdfImportPageState extends State<PdfImportPage> {
  late final PdfImportService _service;
  PdfImportKind _kind = PdfImportKind.customers;
  PdfImportPreview? _preview;
  String? _fileName;
  String? _message;
  bool _working = false;
  @override
  void initState() {
    super.initState();
    _service = PdfImportService(AuthorizationService(widget.database, widget.authService));
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.single.path;
    if (path == null) {
      setState(() => _message = 'تعذر الوصول إلى مسار الملف المحدد');
      return;
    }
    setState(() { _working = true; _preview = null; _message = null; _fileName = result.files.single.name; });
    try {
      final preview = await _service.prepare(File(path), _kind);
      if (mounted) setState(() { _preview = preview; _working = false; });
    } catch (e) {
      if (mounted) setState(() { _message = e.toString(); _working = false; });
    }
  }

  void _toggle(int index, bool selected) {
    final p = _preview;
    if (p == null) return;
    final rows = [...p.rows];
    rows[index] = rows[index].copyWith(selected: selected && !rows[index].isDuplicate);
    setState(() => _preview = PdfImportPreview(kind: p.kind, rows: rows, ignoredLines: p.ignoredLines, pageCount: p.pageCount));
  }

  Future<void> _commit() async {
    final p = _preview;
    if (p == null || p.selectedCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد الاستيراد'),
        content: Text('سيتم حفظ ${p.selectedCount} سجلًا محددًا. لن يتم دمج السجلات المكررة أو استبدال بيانات موجودة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('مراجعة')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _working = true; _message = null; });
    try {
      final result = await _service.commit(p);
      if (mounted) {
        setState(() {
          _message = 'تم الاستيراد: ${result.imported} • مكرر تم تجاوزه: ${result.duplicatesSkipped} • تعذر حفظه: ${result.failed}';
          _preview = null;
          _working = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _message = 'فشل الاستيراد: $e'; _working = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('استيراد بيانات PDF')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('اختر نوع البيانات أولًا. يدعم الاستيراد ملفات PDF النصية ذات الأعمدة المفصولة بعلامة | أو فاصلة منقوطة أو تبويب أو مسافات متعددة. الملفات المصورة تحتاج OCR منفصلًا.'))),
        const SizedBox(height: 12),
        SegmentedButton<PdfImportKind>(
          segments: const [
            ButtonSegment(value: PdfImportKind.customers, label: Text('العملاء')),
            ButtonSegment(value: PdfImportKind.inventory, label: Text('الأصناف')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() { _kind = v.first; _preview = null; _fileName = null; _message = null; }),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _working ? null : _pick, icon: const Icon(Icons.picture_as_pdf), label: const Text('اختيار ملف PDF')),
        if (_fileName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('الملف: $_fileName')),
        if (_working) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (_message != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_message!))),
        if (_preview != null) ...[
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('معاينة الاستيراد', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('الصفحات: ${_preview!.pageCount} • سجلات مقروءة: ${_preview!.rows.length} • أسطر متجاهلة: ${_preview!.ignoredLines}'),
            Text('المحدد للحفظ: ${_preview!.selectedCount}'),
          ]))),
          ...List.generate(_preview!.rows.length, (i) {
            final row = _preview!.rows[i];
            final title = row.values.first;
            return Card(child: CheckboxListTile(
              value: row.selected,
              onChanged: row.isDuplicate ? null : (v) => _toggle(i, v ?? false),
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(row.isDuplicate ? row.duplicateReason! : row.values.skip(1).where((v) => v.isNotEmpty).join(' • ')),
              secondary: row.isDuplicate ? const Icon(Icons.copy_all_outlined) : null,
            ));
          }),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _working || _preview!.selectedCount == 0 ? null : _commit, icon: const Icon(Icons.check), label: const Text('اعتماد السجلات المحددة')),
        ],
      ]),
    ),
  );
}
