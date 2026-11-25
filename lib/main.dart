// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/database_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AdvancedAssistantApp(databaseProvider: DatabaseProvider()));
}
