import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_service.dart';

class CloudAiGateway {
  CloudAiGateway(this.database, this.authorization, {FlutterSecureStorage? secureStorage})
      : secureStorage = secureStorage ?? const FlutterSecureStorage();
  final Database database;
  final AuthorizationService authorization;
  final FlutterSecureStorage secureStorage;

  Future<String> ask(String prompt) async {
    await authorization.requirePermission(AppPermission.assistantCloud);
    final rows = await database.query('app_settings', where: "key = 'cloud_ai'", limit: 1);
    if (rows.isEmpty) throw StateError('لم يتم إعداد مزود الذكاء السحابي');
    final config = jsonDecode(rows.single['value_json']! as String) as Map<String, dynamic>;
    if (config['enabled'] != true || config['consent'] != true) {
      throw StateError('الذكاء السحابي غير مفعل أو لم توافق على مشاركة نص السؤال');
    }
    final endpoint = (config['endpoint'] as String? ?? '').trim();
    final model = (config['model'] as String? ?? '').trim();
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'https' && uri.host != 'localhost')) {
      throw const FormatException('عنوان مزود الذكاء يجب أن يكون HTTPS صالحًا');
    }
    if (model.isEmpty) throw StateError('أدخل اسم النموذج في الإعدادات');
    final key = await secureStorage.read(key: 'advanced_assistant_cloud_api_key');
    if (key == null || key.trim().isEmpty) throw StateError('أدخل مفتاح API في الإعدادات أولًا');

    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'temperature': 0.2,
        'max_tokens': 700,
        'messages': [
          {'role': 'system', 'content': 'أنت مساعد أعمال عربي. أجب باللغة العربية بوضوح. لا تدّع الوصول إلى قاعدة بيانات التطبيق أو معلومات غير موجودة في سؤال المستخدم. ميّز بين الحقيقة والاقتراح.'},
          {'role': 'user', 'content': prompt},
        ],
      }),
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('فشل مزود الذكاء السحابي (HTTP ${response.statusCode}). تحقق من الرابط والمفتاح واسم النموذج.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) throw const FormatException('استجابة المزود لا تحتوي على إجابة');
    final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    if (content is List) {
      final text = content.whereType<Map>().map((part) => part['text']?.toString() ?? '').join('\n').trim();
      if (text.isNotEmpty) return text;
    }
    throw const FormatException('لم يرجع مزود الذكاء نصًا صالحًا');
  }
}
