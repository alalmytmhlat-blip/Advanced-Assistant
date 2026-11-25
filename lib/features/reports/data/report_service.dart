// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_service.dart';
import '../../customers/data/customer_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../inventory/data/inventory_repository.dart';

class ReportData {
  const ReportData({required this.title, required this.headers, required this.rows});
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
}

class ReportService {
  ReportService(this.database, this.authorization);
  final Database database;
  final AuthorizationService authorization;

  Future<ReportData> load(String type) async {
    await authorization.requirePermission(AppPermission.reportsRead);
    switch (type) {
      case 'customers':
        final customers = await CustomerRepository(database, authorization).search('');
        final context = await authorization.loadContext();
        final canReadBalance = authorization.policy.hasPermission(context, AppPermission.balanceRead);
        final headers = <String>['العميل', 'الهاتف', 'العنوان', if (canReadBalance) 'الرصيد الحالي'];
        return ReportData(
          title: 'تقرير العملاء',
          headers: headers,
          rows: customers.map((c) => <String>[c.name, c.phone ?? '', c.address ?? '', if (canReadBalance) c.currentBalance]).toList(),
        );
      case 'followups':
        final items = await ReminderRepository(database, authorization).list(limit: 500);
        return ReportData(
          title: 'تقرير المتابعات',
          headers: const ['المتابعة', 'العميل', 'الموعد', 'الحالة', 'الأولوية', 'المسؤول'],
          rows: items.map((r) => [
            r.title, r.customerName ?? 'بدون عميل', r.dueAt.toString(),
            r.status, r.priority, r.assigneeName ?? '',
          ]).toList(),
        );
      case 'inventory':
        final items = await InventoryRepository(database, authorization).list(limit: 1000);
        return ReportData(
          title: 'تقرير المخزون',
          headers: const ['الصنف', 'الكود', 'المقاس', 'الفئة', 'الكمية', 'الوحدة', 'حد التنبيه'],
          rows: items.map((i) => [
            i.name, i.code ?? '', i.size ?? '', i.category ?? '',
            i.quantity, i.unit, i.minimumQuantity,
          ]).toList(),
        );
      default:
        throw ArgumentError.value(type, 'type');
    }
  }

  Future<void> shareCsv(ReportData report) async {
    final csv = const ListToCsvConverter(fieldDelimiter: ',', eol: '\r\n')
        .convert([report.headers, ...report.rows]);
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...csv.codeUnits]);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(report.title)}.csv');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: report.title));
  }

  Future<void> sharePdf(ReportData report) async {
    final doc = pw.Document();
    final rowsPerPage = 24;
    final pageCount = report.rows.isEmpty ? 1 : (report.rows.length / rowsPerPage).ceil();
    for (var page = 0; page < pageCount; page++) {
      final start = page * rowsPerPage;
      final end = (start + rowsPerPage).clamp(0, report.rows.length);
      final lines = <String>[
        report.headers.join('   |   '),
        ...report.rows.skip(start).take(end - start).map((r) => r.join('   |   ')),
      ];
      final png = await _renderArabicPage(report.title, lines, page + 1, pageCount);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
      ));
    }
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(report.title)}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: report.title));
  }

  Future<Uint8List> _renderArabicPage(String title, List<String> lines, int page, int pages) async {
    const width = 1240;
    const height = 1754;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final titlePainter = ui.TextPainter(
      text: ui.TextSpan(text: title, style: const ui.TextStyle(fontSize: 42, fontWeight: ui.FontWeight.bold, color: ui.Color(0xFF123A5A))),
      textDirection: ui.TextDirection.rtl, textAlign: ui.TextAlign.right,
    )..layout(maxWidth: 1120);
    titlePainter.paint(canvas, const ui.Offset(60, 60));
    final subtitle = ui.TextPainter(
      text: ui.TextSpan(text: 'تاريخ التقرير: ${DateTime.now().toLocal()}   •   صفحة $page من $pages', style: const ui.TextStyle(fontSize: 22, color: ui.Color(0xFF555555))),
      textDirection: ui.TextDirection.rtl, textAlign: ui.TextAlign.right,
    )..layout(maxWidth: 1120);
    subtitle.paint(canvas, const ui.Offset(60, 130));
    var y = 210.0;
    for (var i = 0; i < lines.length; i++) {
      final painter = ui.TextPainter(
        text: ui.TextSpan(text: lines[i], style: ui.TextStyle(fontSize: i == 0 ? 23 : 20, fontWeight: i == 0 ? ui.FontWeight.bold : ui.FontWeight.normal, color: const ui.Color(0xFF202020))),
        textDirection: ui.TextDirection.rtl, textAlign: ui.TextAlign.right, maxLines: 2, ellipsis: '…',
      )..layout(maxWidth: 1120);
      painter.paint(canvas, ui.Offset(60, y));
      y += i == 0 ? 52 : 48;
      canvas.drawLine(ui.Offset(60, y - 8), ui.Offset(width - 60, y - 8), ui.Paint()..color = const ui.Color(0xFFE1E7ED)..strokeWidth = 1);
      if (y > height - 70) break;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('تعذر تجهيز صورة التقرير');
    return data.buffer.asUint8List();
  }

  String _safeName(String value) => value.replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9_-]'), '_');
}
