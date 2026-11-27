// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'dart:io';
import 'universal_file_extractor.dart';
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
  final UniversalFileExtractor _extractor = UniversalFileExtractor();

  Future<PdfImportPreview> prepare(File file, PdfImportKind kind) async {
    final extracted = await _extractor.extract(file);
    if (extracted.text.trim().isEmpty) {
      throw FormatException('لم يتم استخراج بيانات من ملف ' + extracted.format + '. قد يكون PDF مصورًا ويحتاج OCR.');
    }
    return kind == PdfImportKind.customers
        ? _prepareCustomers(extracted.text, extracted.pageCount)
        : _prepareInventory(extracted.text, extracted.pageCount);
  }

  Future<PdfImportPreview> _prepareCustomers(String text, int pages) async {
    final existing = await CustomerRepository(authorization.database, authorization).search('', includeArchived: true);
    final names = existing.map((c) => _normalize(c.name)).toSet();
    final phones = existing.map((c) => _normalize(c.phone ?? '')).where((p) => p.isNotEmpty).toSet();
    final seenNames = <String>{};
    final seenPhones = <String>{};
    final parsed = _parseLines(text, PdfImportKind.customers);
    final rows = parsed.rows.map((values) {
      final name = values[0];
      final phone = values.length > 1 ? values[1] : '';
      final normalizedName = _normalize(name);
      final normalizedPhone = _normalize(phone);
      final duplicate = names.contains(normalizedName) ||
          (phone.isNotEmpty && phones.contains(normalizedPhone)) ||
          !seenNames.add(normalizedName) ||
          (phone.isNotEmpty && !seenPhones.add(normalizedPhone));
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
    final seenKeys = <String>{};
    final parsed = _parseLines(text, PdfImportKind.inventory);
    final rows = parsed.rows.map((values) {
      final name = values[0];
      final code = values.length > 1 ? values[1] : '';
      final key = '${_normalize(name)}|${_normalize(code)}';
      final duplicate = keys.contains(key) || !seenKeys.add(key);
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

  ({List<List<String>> rows, int ignored}) _parseLines(
    String text,
    PdfImportKind kind,
  ) {
    final rows = <List<String>>[];
    var ignored = 0;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '').trim();
      if (line.isEmpty || line.length < 2 || _isHeaderOrNoise(line)) {
        ignored++;
        continue;
      }

      final delimiter = line.contains('\t')
          ? '\t'
          : line.contains('|')
              ? '|'
              : line.contains(';')
                  ? ';'
                  : line.contains(',')
                      ? ','
                      : null;
      List<String> columns;
      if (delimiter != null) {
        columns = _splitQuoted(line, delimiter);
      } else {
        columns = line.split(RegExp(r'\s{2,}'));
        if (columns.length == 1 && kind == PdfImportKind.customers) {
          final phone = RegExp(r'(?:\+?967[- ]?)?7\d{8}|\b\d{7,15}\b').firstMatch(line);
          if (phone != null) {
            final name = line.replaceFirst(phone.group(0)!, '').trim();
            columns = [name, phone.group(0)!];
          }
        }
      }
      columns = columns.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      if (columns.isEmpty || columns.first.length > 240) {
        ignored++;
        continue;
      }

      // A single non-numeric text line is a valid customer/item name in simple lists.
      if (columns.length == 1) {
        final value = columns.single;
        final hasArabicOrLatin = RegExp(r'[\u0600-\u06FFa-zA-Z]').hasMatch(value);
        final looksNumeric = RegExp(r'^[-+]?\d+(?:[.,]\d+)?$').hasMatch(value);
        if (!hasArabicOrLatin || looksNumeric) {
          ignored++;
          continue;
        }
      }

      // Keep the source order; the preview lets the operator inspect every imported value.
      rows.add(columns);
    }
    return (rows: rows, ignored: ignored);
  }

  bool _isHeaderOrNoise(String line) {
    final value = _normalize(line);
    if (RegExp(r'^\d{1,4}$').hasMatch(value)) return true;
    const headers = [
      'الاسم', 'اسم العميل', 'اسم الزبون', 'العميل', 'العملاء',
      'الزبون', 'الزبائن', 'رقم الهاتف', 'الهاتف', 'الجوال',
      'اسم الصنف', 'الصنف', 'الاصناف', 'الكمية', 'الرصيد',
      'name', 'customer', 'customers', 'phone', 'mobile', 'item',
      'items', 'quantity', 'balance'
    ];
    if (headers.any((h) => value == _normalize(h))) return true;
    if (value.startsWith('عام #العملاء') || value.startsWith('عام العملاء')) return true;
    return false;
  }

  List<String> _splitQuoted(String line, String delimiter) {
    final result = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        result.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(char);
      }
    }
    result.add(cell.toString().trim());
    return result;
  }

  String _normalize(String value) => value.trim().toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي').replaceAll(RegExp(r'\s+'), ' ');
}
