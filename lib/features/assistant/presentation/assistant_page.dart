// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/local_assistant_service.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.database, required this.authService});
  final Database database;
  final AuthService authService;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}
class _AssistantPageState extends State<AssistantPage> {
  late final LocalAssistantService _assistant;
  final _controller = TextEditingController();
  AssistantAnswer? _answer;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _assistant = LocalAssistantService(widget.database, AuthorizationService(widget.database, widget.authService));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _ask([String? prompt]) async {
    final value = (prompt ?? _controller.text).trim();
    if (value.isEmpty || _loading) return;
    setState(() { _loading = true; _answer = null; });
    try {
      final answer = await _assistant.ask(value);
      if (mounted) setState(() => _answer = answer);
    } catch (error) {
      if (mounted) setState(() => _answer = AssistantAnswer(title: 'تعذر تنفيذ الطلب', message: error.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('المساعد الذكي المحلي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.offline_bolt_outlined), SizedBox(width: 8), Text('يعمل دون إنترنت', style: TextStyle(fontWeight: FontWeight.bold))]),
            SizedBox(height: 8),
            Text('يبحث المساعد في السجلات التي تسمح بها صلاحيات حسابك. لا يرسل أسماء العملاء أو الأرصدة أو المخزون إلى أي خدمة خارجية.'),
          ]),
        )),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(label: const Text('المتابعات المتأخرة'), onPressed: () => _ask('المتابعات المتأخرة')),
          ActionChip(label: const Text('الأصناف منخفضة المخزون'), onPressed: () => _ask('الأصناف منخفضة المخزون')),
          ActionChip(label: const Text('عدد العملاء'), onPressed: () => _ask('عدد العملاء')),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _controller, minLines: 1, maxLines: 3,
          textInputAction: TextInputAction.send, onSubmitted: (_) => _ask(),
          decoration: InputDecoration(
            labelText: 'اكتب سؤالك بالعربية', hintText: 'مثال: ابحث عن عميل أحمد',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(onPressed: _loading ? null : _ask, icon: const Icon(Icons.send)),
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_answer != null) ...[
          const SizedBox(height: 16),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_answer!.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8), Text(_answer!.message),
              if (_answer!.details.isNotEmpty) ...[
                const Divider(height: 24),
                ..._answer!.details.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $line'))),
              ],
              const SizedBox(height: 8),
              Text('المصدر: ${_answer!.source}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          )),
        ],
      ]),
    ),
  );
}
