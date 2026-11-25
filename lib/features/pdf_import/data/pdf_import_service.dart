// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'package:pdfrx/pdfrx.dart';
import '../../../core/pdf/pdf_runtime.dart';
import '../../../core/auth/authorization_service.dart';
import '../../customers/data/customer_model.dart';
import '../../customers/data/customer_repository.dart';
import '../../inventory/data/inventory_repository.dart';

enum PdfImportKind { customers, inventory }

class PdfImportRow {
  const PdfImportRow({
    required this.values,
    required this.isDuplicate,
    required this.duplicateReason,
    required this.selected,
  });
  final List<String> values;
  final bool isDuplicate;
  final String? duplicateReason;
  final bool selected;
  PdfImportRow copyWith({bool? selected}) => PdfImportRow(
    values: values,
    isDuplicate: isDuplicate,
    duplicateReason: duplicateReason,
    selected: selected ?? this.selected,
  );
}

class PdfImportPreview {
  const PdfImportPreview({required this.kind, required this.rows, required this.ignoredLines, required this.pageCount});
  final PdfImportKind kind;
  final List<PdfImportRow> rows;
  final int ignoredLines;
  final int pageCount;
  int get selectedCount => rows.where((r) => r.selected && !r.isDuplicate).length;
}

class PdfImportResult {
  const PdfImportResult({required this.imported, required this.failed, required this.duplicatesSkipped});
  final int imported;
  final int failed;
  final int duplicatesSkipped;
}

class PdfImportService {
  PdfImportService(this.authorization);
  final AuthorizationService authorization;
  Future<PdfImportPreview> prepare(File file, PdfImportKind kind) async {
    await PdfRuntime.initialize();
    final document = await PdfDocument.openFile(file.path);
    try {
      if (document.pages.isEmpty || document.pages.length > 300) {
        throw const FormatException('عدد صفحات PDF غير صالح أو يتجاوز الحد المسموح (300 صفحة)');
      }
      final text = StringBuffer();
      for (final page in document.pages) {
        final raw = await page.loadText();
        if (raw != null && raw.fullText.isNotEmpty) {
          text.writeln(raw.fullText);
        }
      }
      final extracted = text.toString();
      if (extracted.trim().isEmpty) {
        throw const FormatException('لم أجد نصًا قابلًا للاستخراج. قد يكون الملف صورة ممسوحة؛ OCR غير مفعل في هذه المرحلة.');
      }
      return await (kind == PdfImportKind.customers
          ? _prepareCustomers(extracted, document.pages.length)
          : _prepareInventory(extracted, document.pages.length));
    } finally {
      await document.dispose();
    }
  }

  Future<PdfImportPreview> _prepareCustomers(String text, int pages) async {
    final existing = await CustomerRepository(authorization.database, authorization).search('', includeArchived: true);
    final names = existing.map((c) => _normalize(c.name)).toSet();
    final phones = existing.map((c) => _normalize(c.phone ?? '')).where((p) => p.isNotEmpty).toSet();
    final parsed = _parseLines(text);
    final rows = parsed.rows.map((values) {
      final name = values[0];
      final phone = values.length > 1 ? values[1] : '';
      final duplicate = names.contains(_normalize(name)) || (phone.isNotEmpty && phones.contains(_normalize(phone)));
      return PdfImportRow(
        values: [name, phone, values.length > 2 ? values[2] : '', values.length > 3 ? values[3] : ''],
        isDuplicate: duplicate,
        duplicateReason: duplicate ? 'اسم أو هاتف موجود مسبقًا' : null,
        selected: !duplicate,
      );
    }).toList();
    return PdfImportPreview(kind: PdfImportKind.customers, rows: rows, ignoredLines: parsed.ignored, pageCount: pages);
  }

  Future<PdfImportPreview> _prepareInventory(String text, int pages) async {
    final existing = await InventoryRepository(authorization.database, authorization).list(includeArchived: true, limit: 1000);
    final keys = existing.map((i) => '${_normalize(i.name)}|${_normalize(i.code ?? '')}').toSet();
    final parsed = _parseLines(text);
    final rows = parsed.rows.map((values) {
      final name = values[0];
      final code = values.length > 1 ? values[1] : '';
      final duplicate = keys.contains('${_normalize(name)}|${_normalize(code)}');
      return PdfImportRow(
        values: [
          name, code, values.length > 2 ? values[2] : '',
          values.length > 3 ? values[3] : '0',
          values.length > 4 ? values[4] : '',
          values.length > 5 ? values[5] : '0',
          values.length > 6 ? values[6] : '',
        ],
        isDuplicate: duplicate,
        duplicateReason: duplicate ? 'اسم الصنف والكود موجودان مسبقًا' : null,
        selected: !duplicate,
      );
    }).toList();
    return PdfImportPreview(kind: PdfImportKind.inventory, rows: rows, ignoredLines: parsed.ignored, pageCount: pages);
  }

  Future<PdfImportResult> commit(PdfImportPreview preview) async {
    var imported = 0;
    var failed = 0;
    var duplicates = preview.rows.where((r) => r.isDuplicate).length;
    if (preview.kind == PdfImportKind.customers) {
      final repo = CustomerRepository(authorization.database, authorization);
      for (final row in preview.rows.where((r) => r.selected && !r.isDuplicate)) {
        try {
          await repo.create(CustomerDraft(
            name: row.values[0],
            phone: row.values[1],
            address: row.values[2],
            category: row.values[3],
          ));
          imported++;
        } catch (_) { failed++; }
      }
    } else {
      final repo = InventoryRepository(authorization.database, authorization);
      for (final row in preview.rows.where((r) => r.selected && !r.isDuplicate)) {
        try {
          await repo.create(
            name: row.values[0], code: row.values[1], size: row.values[2],
            quantity: row.values[3].isEmpty ? '0' : row.values[3],
            unit: row.values[4], minimumQuantity: row.values[5].isEmpty ? '0' : row.values[5],
            category: row.values[6],
          );
          imported++;
        } catch (_) { failed++; }
      }
    }
    return PdfImportResult(imported: imported, failed: failed, duplicatesSkipped: duplicates);
  }

  ({List<List<String>> rows, int ignored}) _parseLines(String text) {
    final rows = <List<String>>[];
    var ignored = 0;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.length < 2) { ignored++; continue; }
      final lower = _normalize(line);
      if (['الاسم', 'اسم العميل', 'العميل', 'الصنف', 'اسم الصنف', 'name', 'customer', 'item'].any(lower.startsWith)) {
        ignored++;
        continue;
      }
      List<String> columns;
      if (line.contains('|')) {
        columns = line.split('|');
      } else if (line.contains('\t')) {
        columns = line.split('\t');
      } else if (line.contains(';')) {
        columns = line.split(';');
      } else {
        columns = line.split(RegExp(r'\s{2,}'));
      }
      columns = columns.map((v) => v.trim()).toList();
      if (columns.length < 2 || columns.first.isEmpty || columns.first.length > 240) { ignored++; continue; }
      rows.add(columns);
    }
    return (rows: rows, ignored: ignored);
  }

  String _normalize(String value) => value.trim().toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي').replaceAll(RegExp(r'\s+'), ' ');
}
