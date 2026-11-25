// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/app_permission.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/balance_change_model.dart';
import '../data/customer_balance_repository.dart';
import '../data/customer_model.dart';

class CustomerBalancePage extends StatefulWidget {
  const CustomerBalancePage({
    super.key,
    required this.database,
    required this.authService,
    required this.customer,
  });

  final Database database;
  final AuthService authService;
  final CustomerRecord customer;

  @override
  State<CustomerBalancePage> createState() => _CustomerBalancePageState();
}

class _CustomerBalancePageState extends State<CustomerBalancePage> {
  late final AuthorizationService _authorization;
  late final CustomerBalanceRepository _repository;
  final AuthorizationPolicy _policy = const AuthorizationPolicy();
  List<BalanceChangeRecord> _history = [];
  AuthorizationContext? _access;
  String? _balance;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  bool get _canUpdate =>
      _access != null &&
      _policy.hasPermission(_access!, AppPermission.balanceUpdate);

  @override
  void initState() {
    super.initState();
    _authorization = AuthorizationService(widget.database, widget.authService);
    _repository = CustomerBalanceRepository(widget.database, _authorization);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await _authorization.loadContext();
      final balance = await _repository.readBalance(widget.customer.id);
      final history = await _repository.history(widget.customer.id);
      if (!mounted) return;
      setState(() {
        _access = access;
        _balance = balance;
        _history = history;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AuthorizationException
            ? error.message
            : 'تعذر تحميل بيانات الرصيد';
        _loading = false;
      });
    }
  }

  Future<void> _editBalance() async {
    final balanceController = TextEditingController(text: _balance ?? '');
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<_BalanceDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل رصيد العميل'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الرصيد الجديد',
                    helperText: 'يمكن إدخال قيمة موجبة أو سالبة',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'أدخل الرصيد الجديد';
                    }
                    if (value.trim().length > 120 ||
                        !RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$')
                            .hasMatch(value.trim())) {
                      return 'أدخل قيمة رقمية صحيحة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonController,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'سبب تعديل الرصيد',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'سبب التعديل مطلوب'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                dialogContext,
                _BalanceDraft(
                  balance: balanceController.text.trim(),
                  reason: reasonController.text.trim(),
                ),
              );
            },
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
    balanceController.dispose();
    reasonController.dispose();
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.updateBalance(
        customerId: widget.customer.id,
        newBalance: result.balance,
        reason: result.reason,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الرصيد وحفظ سجل التغيير')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('رصيد العميل'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canUpdate
          ? FloatingActionButton.extended(
              onPressed: _saving || _loading ? null : _editBalance,
              icon: const Icon(Icons.edit),
              label: const Text('تعديل الرصيد'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.customer.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              const Text('الرصيد الحالي'),
                              const SizedBox(height: 6),
                              Text(
                                _balance ?? '—',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                textDirection: TextDirection.ltr,
                              ),
                              if (_saving) ...[
                                const SizedBox(height: 12),
                                const LinearProgressIndicator(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'سجل تغييرات الرصيد',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (_history.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text('لا توجد تغييرات مسجلة لهذا الرصيد'),
                            ),
                          ),
                        )
                      else
                        ..._history.map(
                          (entry) => Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.history),
                              ),
                              title: Text(
                                '${entry.previousBalance}  ←  ${entry.newBalance}',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.reason),
                                  const SizedBox(height: 4),
                                  Text(_formatDate(entry.changedAt)),
                                  if (entry.changedBy != null)
                                    Text('بواسطة: ${entry.changedBy}'),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _BalanceDraft {
  const _BalanceDraft({required this.balance, required this.reason});

  final String balance;
  final String reason;
}
