import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/authorization_service.dart';

class AppSettingsRepository {
  AppSettingsRepository(this.database, this.authorization);
  final Database database;
  final AuthorizationService authorization;

  Future<({Map<String, dynamic> profile, Map<String, dynamic> cloud})> load() async {
    await authorization.requirePermission(AppPermission.settingsManage);
    final rows = await database.query('app_settings', where: "key IN ('store_profile','cloud_ai')");
    Map<String, dynamic> profile = {};
    Map<String, dynamic> cloud = {};
    for (final row in rows) {
      final value = jsonDecode(row['value_json']! as String) as Map<String, dynamic>;
      if (row['key'] == 'store_profile') profile = value;
      if (row['key'] == 'cloud_ai') cloud = value;
    }
    return (profile: profile, cloud: cloud);
  }

  Future<void> save({
    required Map<String, dynamic> profile,
    required Map<String, dynamic> cloud,
  }) async {
    final context = await authorization.loadContext();
    authorization.policy.requirePermission(context, AppPermission.settingsManage);
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      for (final entry in {'store_profile': profile, 'cloud_ai': cloud}.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value_json': jsonEncode(entry.value),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('audit_events', {
        'id': _id(),
        'actor_user_id': context.userId,
        'entity_type': 'app_settings',
        'action': 'settings.update',
        'after_json': jsonEncode({
          'store_profile': profile,
          'cloud_ai': {
            'enabled': cloud['enabled'] == true,
            'consent': cloud['consent'] == true,
            'endpoint': cloud['endpoint'],
            'model': cloud['model'],
          },
        }),
        'occurred_at': now,
      });
    });
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}${database.hashCode.toRadixString(16)}';
}
