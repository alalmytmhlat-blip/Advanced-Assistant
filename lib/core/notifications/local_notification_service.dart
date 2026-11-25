import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../features/reminders/data/reminder_model.dart';

/// Local notifications use inexact scheduling; no exact-alarm permission.
class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final offset = DateTime.now().timeZoneOffset;
    if (offset.inMinutes % 60 == 0) {
      final hours = offset.inHours;
      final name = 'Etc/GMT${hours >= 0 ? '-' : '+'}${hours.abs()}';
      try { tz.setLocalLocation(tz.getLocation(name)); } catch (_) { tz.setLocalLocation(tz.UTC); }
    } else {
      tz.setLocalLocation(tz.UTC);
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<void> syncFollowups(List<ReminderRecord> reminders) async {
    await initialize();
    if (!await requestPermission()) return;
    await _plugin.cancelAll();
    final now = DateTime.now();
    for (final item in reminders) {
      if (item.status == 'completed' || item.status == 'cancelled' || !item.dueAt.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        _stableId(item.id),
        'تذكير: ${item.title}',
        item.customerName == null ? 'حان موعد المتابعة المحددة' : 'موعد متابعة العميل: ${item.customerName}',
        tz.TZDateTime.from(item.dueAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'followups_channel', 'متابعات العملاء',
            channelDescription: 'تنبيهات مواعيد المتابعات والمهام',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: item.id,
      );
    }
  }

  int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
