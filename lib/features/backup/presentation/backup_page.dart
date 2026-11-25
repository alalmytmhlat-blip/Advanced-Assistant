import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../../../core/database/database_provider.dart';
import '../data/backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.provider, required this.authService, required this.onRestored});
  final DatabaseProvider provider;
  final AuthService authService;
  final VoidCallback onRestored;
  @override
  State<BackupPage> createState() => _BackupPageState();
}
class _BackupPageState extends State<BackupPage> {
  late final BackupService _backup;
  bool _working = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _backup = BackupService(widget.provider, widget.authService);
  }
  Future<void> _create() async {
    setState(() { _working = true; _message = null; });
    try {
      final file = await _backup.createBackupFile();
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'نسخة احتياطية من المساعد الذكي'));
      if (mounted) setState(() => _message = 'تم تجهيز النسخة الاحتياطية ومشاركتها. احتفظ بها في مكان آمن.');
    } catch (e) {
      if (mounted) setState(() => _message = 'تعذر إنشاء النسخة: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['zip'], withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد استعادة النسخة'),
        content: const Text('ستحل بيانات النسخة محل البيانات الحالية. سيتحقق التطبيق من checksum وسلامة SQLite، وينشئ نسخة أمان من قاعدة البيانات الحالية قبل الاستبدال.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() { _working = true; _message = null; });
    try {
      final selected = result.files.single;
      final Uint8List bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      await _backup.restoreBackup(bytes);
      if (mounted) {
        setState(() => _message = 'تمت الاستعادة والتحقق من قاعدة البيانات. سيتم العودة إلى شاشة الدخول.');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        widget.onRestored();
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'رفض التطبيق النسخة ولم يعتمدها: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('النسخة تشمل قاعدة البيانات المحلية وسجل العملاء والأرصدة والمتابعات والمخزون والمستخدمين. احفظ ملف النسخة خارج الهاتف بصورة آمنة.'),
        )),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _working ? null : _create, icon: const Icon(Icons.backup_outlined), label: const Text('إنشاء نسخة احتياطية ومشاركتها')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _working ? null : _restore, icon: const Icon(Icons.settings_backup_restore), label: const Text('استعادة من ملف ZIP')),
        if (_working) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_message != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_message!))),
      ]),
    ),
  );
}
