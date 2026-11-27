// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
import '../../../core/pdf/pdf_runtime.dart';

class ExtractedDocument {
  const ExtractedDocument(this.text, this.format, this.pageCount);
  final String text;
  final String format;
  final int pageCount;
}

class UniversalFileExtractor {
  static const supportedExtensions = <String>{
    'pdf','docx','xlsx','pptx','csv','tsv','txt','json','jsonl','xml','html','htm','md','markdown'
  };

  Future<ExtractedDocument> extract(File file) async {
    if (!await file.exists()) throw const FormatException('الملف غير موجود');
    final e = file.path.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(e)) throw FormatException('الصيغة غير مدعومة: .' + e);
    final bytes = await file.readAsBytes();
    if (e == 'pdf') return _pdf(file);
    if (e == 'docx') return _docx(bytes);
    if (e == 'xlsx') return _xlsx(bytes);
    if (e == 'pptx') return _pptx(bytes);
    final raw = utf8.decode(bytes, allowMalformed: true);
    if (e == 'csv' || e == 'tsv') return ExtractedDocument(_delimited(raw, e == 'tsv' ? '\t' : null), e.toUpperCase(), 1);
    if (e == 'json' || e == 'jsonl') return ExtractedDocument(_json(raw, e == 'jsonl'), e.toUpperCase(), 1);
    if (e == 'xml') return ExtractedDocument(_xml(raw), 'XML', 1);
    if (e == 'html' || e == 'htm') return ExtractedDocument(_html(raw), 'HTML', 1);
    return ExtractedDocument(raw, e.toUpperCase(), 1);
  }

  Future<ExtractedDocument> _pdf(File file) async {
    await PdfRuntime.initialize();
    final doc = await PdfDocument.openFile(file.path);
    try {
      final parts = <String>[];
      for (final page in doc.pages) {
        final result = await page.loadText();
        if (result != null && result.fullText.trim().isNotEmpty) parts.add(result.fullText);
      }
      return ExtractedDocument(parts.join('\n'), 'PDF', doc.pages.length);
    } finally {
      await doc.dispose();
    }
  }

  Archive _archive(List<int> bytes) => ZipDecoder().decodeBytes(bytes);
  String _zipText(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  ExtractedDocument _docx(List<int> bytes) {
    final f = _archive(bytes).findFile('word/document.xml');
    if (f == null) throw const FormatException('محتوى ملف Word غير مكتمل');
    final doc = XmlDocument.parse(_zipText(f));
    final rows = <String>[];
    for (final row in doc.findAllElements('w:tr')) {
      final cells = row.findElements('w:tc').map((c) => c.findAllElements('w:t').map((n) => n.innerText).join()).toList();
      if (cells.any((v) => v.trim().isNotEmpty)) rows.add(cells.join('\t'));
    }
    if (rows.isEmpty) {
      for (final p in doc.findAllElements('w:p')) {
        final s = p.findAllElements('w:t').map((n) => n.innerText).join();
        if (s.trim().isNotEmpty) rows.add(s);
      }
    }
    return ExtractedDocument(rows.join('\n'), 'DOCX', 1);
  }

  ExtractedDocument _xlsx(List<int> bytes) {
    final zip = _archive(bytes);
    final shared = <String>[];
    final sf = zip.findFile('xl/sharedStrings.xml');
    if (sf != null) {
      final d = XmlDocument.parse(_zipText(sf));
      for (final item in d.findAllElements('si')) {
        shared.add(item.findAllElements('t').map((n) => n.innerText).join());
      }
    }
    final sheets = zip.files.where((f) => f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((a,b) => _num(a.name).compareTo(_num(b.name)));
    if (sheets.isEmpty) throw const FormatException('لا توجد أوراق Excel قابلة للقراءة');
    final lines = <String>[];
    for (final sheet in sheets) {
      final d = XmlDocument.parse(_zipText(sheet));
      for (final row in d.findAllElements('row')) {
        final cells = <int,String>{};
        var max = -1;
        for (final c in row.findElements('c')) {
          final index = _col(c.getAttribute('r') ?? '');
          if (index < 0) continue;
          final type = c.getAttribute('t');
          var value = c.findElements('v').firstOrNull?.innerText ?? '';
          if (type == 's') {
            final n = int.tryParse(value);
            if (n != null && n >= 0 && n < shared.length) value = shared[n];
          } else if (type == 'inlineStr') {
            value = c.findAllElements('t').map((n) => n.innerText).join();
          }
          cells[index] = value;
          if (index > max) max = index;
        }
        if (max >= 0) lines.add(List.generate(max + 1, (i) => cells[i] ?? '').join('\t'));
      }
    }
    return ExtractedDocument(lines.join('\n'), 'XLSX', sheets.length);
  }

  ExtractedDocument _pptx(List<int> bytes) {
    final slides = _archive(bytes).files.where((f) => f.isFile && RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((a,b) => _num(a.name).compareTo(_num(b.name)));
    final lines = <String>[];
    for (final slide in slides) {
      final d = XmlDocument.parse(_zipText(slide));
      for (final p in d.findAllElements('a:p')) {
        final s = p.findAllElements('a:t').map((n) => n.innerText).join();
        if (s.trim().isNotEmpty) lines.add(s);
      }
    }
    return ExtractedDocument(lines.join('\n'), 'PPTX', slides.length);
  }

  String _delimited(String source, String? forced) {
    final lines = source.replaceAll('\r\n','\n').replaceAll('\r','\n').split('\n');
    final samples = lines.where((l) => l.trim().isNotEmpty).take(20).toList();
    final delim = forced ?? _detect(samples);
    return lines.map((l) => _csvLine(l, delim).join('\t')).join('\n');
  }

  String _detect(List<String> lines) {
    const choices = [',',';','\t','|'];
    var selected = ',';
    var highest = -1;
    for (final d in choices) {
      final counts = lines.map((l) => _csvLine(l,d).length - 1).toList()..sort();
      final score = counts.isEmpty ? 0 : counts[counts.length ~/ 2];
      if (score > highest) { highest = score; selected = d; }
    }
    return selected;
  }

  List<String> _csvLine(String line, String delimiter) {
    final out = <String>[];
    final b = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') { b.write('"'); i++; }
        else { quoted = !quoted; }
      } else if (c == delimiter && !quoted) { out.add(b.toString().trim()); b.clear(); }
      else { b.write(c); }
    }
    out.add(b.toString().trim());
    return out;
  }

  String _json(String source, bool jsonLines) {
    final records = <Map<String,dynamic>>[];
    if (jsonLines) {
      for (final line in source.split('\n')) {
        if (line.trim().isEmpty) continue;
        final value = jsonDecode(line);
        if (value is Map) records.add(value.map((k,v) => MapEntry(k.toString(),v)));
      }
    } else {
      final value = jsonDecode(source);
      if (value is List) {
        for (final item in value) { if (item is Map) records.add(item.map((k,v) => MapEntry(k.toString(),v))); }
      } else if (value is Map) {
        final map = value.map((k,v) => MapEntry(k.toString(),v));
        final list = map.values.whereType<List>().firstOrNull;
        if (list != null) {
          for (final item in list) { if (item is Map) records.add(item.map((k,v) => MapEntry(k.toString(),v))); }
        } else {
          return map.entries.map((e) => e.key + '\t' + (e.value?.toString() ?? '')).join('\n');
        }
      }
    }
    if (records.isEmpty) return '';
    final headers = <String>[];
    for (final r in records) { for (final k in r.keys) { if (!headers.contains(k)) headers.add(k); } }
    return [headers.join('\t'), ...records.map((r) => headers.map((h) => (r[h] ?? '').toString().replaceAll('\t',' ')).join('\t'))].join('\n');
  }

  String _xml(String source) {
    final d = XmlDocument.parse(source);
    return d.descendants.whereType<XmlText>().map((n) => n.value.trim()).where((s) => s.isNotEmpty).join('\n');
  }
  String _html(String source) => source
    .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive:false, dotAll:true), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '\n')
    .replaceAll('&nbsp;',' ').replaceAll('&amp;','&').replaceAll('&lt;','<')
    .replaceAll('&gt;','>').replaceAll('&quot;','"')
    .replaceAll(RegExp(r'[ \t]+'),' ').replaceAll(RegExp(r'\n{2,}'),'\n').trim();

  int _col(String ref) {
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(ref)?.group(0);
    if (letters == null) return -1;
    var n = 0;
    for (final c in letters.toUpperCase().codeUnits) { n = n * 26 + c - 64; }
    return n - 1;
  }
  int _num(String name) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ?? 0;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
