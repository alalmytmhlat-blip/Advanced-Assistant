import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:advanced_assistant/app/app.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';

class _FailingDatabaseProvider extends DatabaseProvider {
  @override
  Future<Database> get database async {
    throw StateError('database unavailable in widget test');
  }
}

void main() {
  testWidgets('application shell exposes the Arabic product title and startup error',
      (tester) async {
    await tester.pumpWidget(
      AdvancedAssistantApp(databaseProvider: _FailingDatabaseProvider()),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'المساعد الذكي');
    expect(find.textContaining('تعذر فتح قاعدة البيانات'), findsOneWidget);
  });
}
