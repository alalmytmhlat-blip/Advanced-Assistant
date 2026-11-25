// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../customers/presentation/customers_page.dart';
import '../../reminders/presentation/reminders_page.dart';
import '../../inventory/presentation/inventory_page.dart';
import '../../users/presentation/users_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key,required this.onLogout,required this.database,required this.authService});
  final VoidCallback onLogout;
  final Database database;
  final AuthService authService;
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('المساعد الذكي',style:TextStyle(fontWeight:FontWeight.w700)),actions:[IconButton(tooltip:'تسجيل الخروج',onPressed:onLogout,icon:const Icon(Icons.logout))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('مرحبًا بك',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:8),
        const Text('إدارة العملاء والأرصدة والمتابعات والمخزون والمستخدمين من مكان واحد، مع حفظ بياناتك محليًا.'),
      ]))),
      const SizedBox(height:12),
      _module(context,Icons.people_alt_outlined,'إدارة العملاء','إضافة العملاء والبحث وتحديث بياناتهم',()=>CustomersPage(database:database,authService:authService)),
      _module(context,Icons.notifications_active_outlined,'المتابعات والتذكيرات','مواعيد العملاء والمهام والتنبيهات المتأخرة',()=>RemindersPage(database:database,authService:authService)),
      _module(context,Icons.inventory_2_outlined,'إدارة المخزون','الأصناف والكميات والفئات وحدود التنبيه',()=>InventoryPage(database:database,authService:authService)),
      _module(context,Icons.manage_accounts_outlined,'إدارة المستخدمين','إنشاء حسابات الموظفين وإيقافها وتفعيلها',()=>UsersPage(database:database,authService:authService)),
      const Card(child:ListTile(leading:CircleAvatar(child:Icon(Icons.psychology_alt_outlined)),title:Text('محرك الذكاء الهجين'),subtitle:Text('سيتم تفعيل المحرك المحلي والبوابة السحابية بعد استكمال ضوابط الخصوصية والصلاحيات.'))),
    ]),
  );
  Widget _module(BuildContext context,IconData icon,String title,String subtitle,Widget Function() page)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(
    leading:CircleAvatar(child:Icon(icon)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_left),
    onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>page())),
  )));
}
