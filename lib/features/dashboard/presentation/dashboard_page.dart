// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'المساعد الذكي',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مرحبًا بك', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'تم تسجيل الدخول بنجاح. ستظهر هنا مؤشرات العملاء والمخزون '
                    'والمتابعات بعد تنفيذ الأنظمة وربطها بقاعدة البيانات.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.psychology_alt_outlined),
              title: Text('محرك الذكاء الهجين'),
              subtitle: Text(
                'الوظائف المحلية والسحابية قيد التخطيط والتنفيذ وفق وثائق المشروع.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
