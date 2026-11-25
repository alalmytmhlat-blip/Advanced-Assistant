// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../customers/presentation/customers_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onLogout, required this.database, required this.authService});
  final VoidCallback onLogout;
  final Database database;
  final AuthService authService;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المساعد الذكي', style: TextStyle(fontWeight: FontWeight.w700)),
      actions: [IconButton(tooltip: 'تسجيل الخروج', onPressed: onLogout, icon: const Icon(Icons.logout))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مرحبًا بك', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8),
        const Text('إدارة العملاء والمتابعات والمخزون من مكان واحد، مع حفظ بياناتك محليًا.')] ))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.people_alt_outlined)),
        title: const Text('إدارة العملاء', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('إضافة العملاء والبحث وتحديث بياناتهم'), trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomersPage(database: database, authService: authService))))),
      const SizedBox(height: 12),
      const Card(child: ListTile(leading: Icon(Icons.psychology_alt_outlined), title: Text('محرك الذكاء الهجين'),
        subtitle: Text('المهام المحلية والسحابية تُفعّل وفق إعدادات مزود الخدمة.'))),
    ]));
}
