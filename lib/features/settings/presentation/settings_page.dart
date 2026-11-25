// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/app_settings_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  late final AppSettingsRepository _repository;
  final _storeName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _endpoint = TextEditingController(text: 'https://api.openai.com/v1/chat/completions');
  final _model = TextEditingController(text: 'gpt-4o-mini');
  final _apiKey = TextEditingController();
  final _secure = const FlutterSecureStorage();
  bool _cloudEnabled = false;
  bool _consent = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = AppSettingsRepository(widget.database, AuthorizationService(widget.database, widget.authService));
    _load();
  }
  @override
  void dispose() {
    _storeName.dispose(); _phone.dispose(); _address.dispose();
    _endpoint.dispose(); _model.dispose(); _apiKey.dispose();
    super.dispose();
  }
  Future<void> _load() async {
    try {
      final data = await _repository.load();
      _storeName.text = data.profile['name'] as String? ?? '';
      _phone.text = data.profile['phone'] as String? ?? '';
      _address.text = data.profile['address'] as String? ?? '';
      _endpoint.text = data.cloud['endpoint'] as String? ?? _endpoint.text;
      _model.text = data.cloud['model'] as String? ?? _model.text;
      _cloudEnabled = data.cloud['enabled'] == true;
      _consent = data.cloud['consent'] == true;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }
  Future<void> _save() async {
    if (_cloudEnabled && (!_consent || _endpoint.text.trim().isEmpty || _model.text.trim().isEmpty)) {
      setState(() => _error = 'يلزم تفعيل الموافقة وإدخال عنوان المزود واسم النموذج');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await _repository.save(
        profile: {'name': _storeName.text.trim(), 'phone': _phone.text.trim(), 'address': _address.text.trim()},
        cloud: {'enabled': _cloudEnabled, 'consent': _consent, 'consent_updated_at': _consent ? DateTime.now().toUtc().toIso8601String() : null, 'endpoint': _endpoint.text.trim(), 'model': _model.text.trim()},
      );
      if (_apiKey.text.trim().isNotEmpty) {
        await _secure.write(key: 'advanced_assistant_cloud_api_key', value: _apiKey.text.trim());
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات. مفتاح API محفوظ في التخزين الآمن فقط.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  Future<void> _clearKey() async {
    await _secure.delete(key: 'advanced_assistant_cloud_api_key');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح مفتاح API من التخزين الآمن')));
  }
  Widget _field(TextEditingController c, String label, {String? hint, bool obscure = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, obscureText: obscure, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder())),
  );
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
        const Text('بيانات النشاط', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        _field(_storeName, 'اسم النشاط'),
        _field(_phone, 'رقم الهاتف'),
        _field(_address, 'العنوان'),
        const Divider(height: 30),
        const Text('الذكاء السحابي الاختياري', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تفعيل مزود ذكاء سحابي'),
          subtitle: const Text('المساعد المحلي يبقى متاحًا دون إنترنت.'),
          value: _cloudEnabled,
          onChanged: (v) => setState(() => _cloudEnabled = v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('أوافق على إرسال نص السؤال الذي أختاره إلى المزود الخارجي'),
          subtitle: const Text('لا تُرسل قاعدة العملاء أو الأرصدة أو المخزون تلقائيًا. يظهر تأكيد مستقل قبل كل إرسال.'),
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
        ),
        _field(_endpoint, 'عنوان API المتوافق مع OpenAI', hint: 'https://.../v1/chat/completions'),
        _field(_model, 'اسم النموذج'),
        _field(_apiKey, 'مفتاح API (لا يُحفظ في قاعدة البيانات)', obscure: true),
        OutlinedButton.icon(onPressed: _clearKey, icon: const Icon(Icons.key_off), label: const Text('مسح مفتاح API المحفوظ')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات')),
      ]),
    ),
  );
}
