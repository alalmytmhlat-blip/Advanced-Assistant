// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/auth/session_secret_store.dart';
import '../../../core/database/database_provider.dart';
import '../../dashboard/presentation/dashboard_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.databaseProvider});

  final DatabaseProvider databaseProvider;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthService? _auth;
  AuthenticatedUser? _user;
  bool _needsSetup = false;
  bool _loading = true;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final Database db = await widget.databaseProvider.database;
      final auth = AuthService(db, FlutterSessionSecretStore());
      final user = await auth.currentUser();
      final hasUsers = await auth.hasAnyUser();
      if (!mounted) return;
      setState(() {
        _auth = auth;
        _user = user;
        _needsSetup = !hasUsers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupError = 'تعذر فتح قاعدة البيانات أو تهيئة الأمان: $error';
        _loading = false;
      });
    }
  }

  Future<void> _onAuthenticated(AuthenticatedUser user) async {
    if (!mounted) return;
    setState(() {
      _user = user;
      _needsSetup = false;
    });
  }

  Future<void> _logout() async {
    await _auth?.logout();
    if (!mounted) return;
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_startupError != null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_startupError!, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }
    if (_user != null) {
      return DashboardPage(onLogout: _logout);
    }
    return AuthPage(
      auth: _auth!,
      needsSetup: _needsSetup,
      onAuthenticated: _onAuthenticated,
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.auth,
    required this.needsSetup,
    required this.onAuthenticated,
  });

  final AuthService auth;
  final bool needsSetup;
  final ValueChanged<AuthenticatedUser> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.needsSetup) {
        await widget.auth.createInitialManager(
          username: _username.text,
          displayName: _displayName.text,
          password: _password.text,
        );
      }
      final user = await widget.auth.login(
        username: _username.text,
        password: _password.text,
      );
      widget.onAuthenticated(user);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    return 'تعذر إكمال العملية. تحقق من البيانات وحاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.security, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            widget.needsSetup ? 'إعداد المدير الأول' : 'تسجيل الدخول',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.needsSetup
                                ? 'أنشئ حساب المدير لتأمين التطبيق. هذه الخطوة تظهر مرة واحدة فقط.'
                                : 'سجّل الدخول للمتابعة إلى لوحة التحكم.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _username,
                            textInputAction: widget.needsSetup
                                ? TextInputAction.next
                                : TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'اسم المستخدم',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => (value == null || value.trim().length < 3)
                                ? 'أدخل اسم مستخدم من 3 أحرف على الأقل'
                                : null,
                          ),
                          if (widget.needsSetup) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _displayName,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'الاسم الظاهر',
                                prefixIcon: Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => (value == null || value.trim().isEmpty)
                                  ? 'أدخل الاسم الظاهر'
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'أدخل كلمة المرور';
                              if (widget.needsSetup && value.length < 10) {
                                return 'كلمة المرور يجب ألا تقل عن 10 أحرف';
                              }
                              return null;
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(widget.needsSetup ? 'إنشاء المدير والدخول' : 'دخول'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
