// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/database/database_provider.dart';
import 'core/notifications/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotificationService.instance.initialize();
  runApp(AdvancedAssistantApp(databaseProvider: DatabaseProvider()));
}
