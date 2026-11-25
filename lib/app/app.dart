// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/database/database_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_gate.dart';

class AdvancedAssistantApp extends StatelessWidget {
  const AdvancedAssistantApp({super.key, required this.databaseProvider});

  final DatabaseProvider databaseProvider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'المساعد الذكي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: AuthGate(databaseProvider: databaseProvider),
    );
  }
}
