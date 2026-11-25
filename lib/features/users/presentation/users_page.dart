import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/user_repository.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key,required this.database,required this.authService});
  final Database database;
  final AuthService authService;
  @override State<UsersPage> createState()=>_UsersPageState();
}
class _UsersPageState extends State<UsersPage> {
  late final UserRepository _repo;
  List<ManagedUser> _users=const [];
  bool _loading=true;
  String? _error;
  @override void initState(){super.initState();_repo=UserRepository(widget.database,AuthorizationService(widget.database,widget.authService),widget.authService);_load();}
  Future<void> _load() async {
    setState(()=>_loading=true);
    try {final users=await _repo.list();if(mounted)setState(()=>_users=users);}
    catch(e){if(mounted)setState(()=>_error='تعذر تحميل المستخدمين: $e');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _add() async {
    final username=TextEditingController(),name=TextEditingController(),password=TextEditingController();
    AppRole role=AppRole.employee;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:const Text('إضافة مستخدم'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        _field(username,'اسم المستخدم (إنجليزي)'),_field(name,'الاسم الظاهر'),_field(password,'كلمة المرور (10 أحرف على الأقل)',obscure:true),
        DropdownButtonFormField<AppRole>(value:role,decoration:const InputDecoration(labelText:'الدور'),items:const [
          DropdownMenuItem(value:AppRole.employee,child:Text('موظف')),
          DropdownMenuItem(value:AppRole.inventoryManager,child:Text('مدير مخزون')),
          DropdownMenuItem(value:AppRole.debtCollector,child:Text('محصل ديون')),
        ],onChanged:(v)=>setDialog(()=>role=v??AppRole.employee)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('إنشاء'))],
    )));
    if(ok==true){try{await _repo.create(username:username.text,displayName:name.text,password:password.text,role:role);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إنشاء المستخدم')));await _load();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر الإنشاء: $e')));}}
    username.dispose();name.dispose();password.dispose();
  }
  Future<void> _toggle(ManagedUser user) async {
    try{await _repo.setActive(userId:user.id,active:!user.isActive);await _load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  String _role(String value)=>switch(value){'manager'=>'مدير','employee'=>'موظف','inventory_manager'=>'مدير مخزون','debt_collector'=>'محصل ديون',_=>'غير معروف'};
  Widget _field(TextEditingController c,String label,{bool obscure=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,obscureText:obscure,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('إدارة المستخدمين'),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:_add,icon:const Icon(Icons.person_add_alt_1),label:const Text('إضافة مستخدم')),
    body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):_users.isEmpty?const Center(child:Text('لا يوجد مستخدمون')):ListView.separated(padding:const EdgeInsets.all(12),itemCount:_users.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(ctx,i){
      final u=_users[i];return Card(child:ListTile(leading:CircleAvatar(child:Icon(u.isActive?Icons.person:Icons.person_off)),title:Text(u.displayName,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('@${u.username} • ${_role(u.role)} • ${u.isActive?'نشط':'موقوف'}'),trailing:Switch(value:u.isActive,onChanged:(_)=>_toggle(u)));
    })),
  ));
}
