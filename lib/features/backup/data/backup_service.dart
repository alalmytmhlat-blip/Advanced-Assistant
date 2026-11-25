// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_service.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/database_schema.dart';

class BackupService {
  BackupService(this.provider, this.authService);
  final DatabaseProvider provider;
  final AuthService authService;

  Future<File> createBackupFile() async {
    final db = await provider.database;
    await AuthorizationService(db, authService).requirePermission(AppPermission.settingsManage);
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first != 'ok') {
      throw StateError('قاعدة البيانات لا تجتاز فحص السلامة');
    }
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final path = await provider.resolvedPath;
    await provider.close();
    try {
      final bytes = await File(path).readAsBytes();
      final checksum = sha256.convert(bytes).toString();
      final manifest = utf8.encode(jsonEncode({
        'format': 'advanced-assistant-backup',
        'schema_version': DatabaseSchema.version,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'sha256': checksum,
      }));
      final archive = Archive()
        ..addFile(ArchiveFile('database.sqlite', bytes.length, bytes))
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      final zipped = ZipEncoder().encode(archive);
      if (zipped.isEmpty) throw StateError('تعذر ضغط النسخة الاحتياطية');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/assistant_backup_${DateTime.now().millisecondsSinceEpoch}.zip');
      await file.writeAsBytes(zipped, flush: true);
      return file;
    } finally {
      await provider.database;
    }
  }

  Future<void> restoreBackup(Uint8List zippedBytes) async {
    final currentDb = await provider.database;
    await AuthorizationService(currentDb, authService).requirePermission(AppPermission.settingsManage);
    final archive = ZipDecoder().decodeBytes(zippedBytes);
    final dbEntry = archive.findFile('database.sqlite');
    final manifestEntry = archive.findFile('manifest.json');
    if (dbEntry == null || manifestEntry == null) throw const FormatException('ملف النسخة الاحتياطية غير مكتمل');
    final dbBytes = Uint8List.fromList(dbEntry.content as List<int>);
    final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>)) as Map<String, dynamic>;
    if (manifest['format'] != 'advanced-assistant-backup') throw const FormatException('نوع النسخة غير معروف');
    if (manifest['sha256'] != sha256.convert(dbBytes).toString()) throw const FormatException('فشل التحقق من سلامة النسخة الاحتياطية');
    if (manifest['schema_version'] != DatabaseSchema.version) throw const FormatException('إصدار قاعدة البيانات في النسخة غير متوافق مع هذا الإصدار من التطبيق');

    final dir = await getTemporaryDirectory();
    final candidate = File('${dir.path}/assistant_restore_candidate.sqlite');
    await candidate.writeAsBytes(dbBytes, flush: true);
    final check = await openDatabase(candidate.path, readOnly: true);
    try {
      final integrity = await check.rawQuery('PRAGMA integrity_check');
      final version = Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version'));
      if (integrity.isEmpty || integrity.first.values.first != 'ok' || version != DatabaseSchema.version) {
        throw const FormatException('قاعدة البيانات داخل النسخة غير سليمة أو غير متوافقة');
      }
    } finally {
      await check.close();
    }

    final targetPath = await provider.resolvedPath;
    await provider.close();
    final target = File(targetPath);
    try {
      if (await target.exists()) {
        final safety = File('$targetPath.before_restore_${DateTime.now().millisecondsSinceEpoch}');
        await target.copy(safety.path);
      }
      await candidate.copy(targetPath);
    } finally {
      await provider.database;
      if (await candidate.exists()) await candidate.delete();
    }
  }
}
