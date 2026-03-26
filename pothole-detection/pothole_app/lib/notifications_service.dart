import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Request permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> showSubmitted(int total, String severity) async {
    await init();
    await _plugin.show(
      1,
      '✅ Report Submitted',
      '$total pothole(s) detected — Severity: $severity',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'report_submitted',
          'Report Submitted',
          channelDescription: 'Notifies when a pothole report is submitted',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showQueued() async {
    await init();
    await _plugin.show(
      2,
      '📥 Report Queued',
      'No internet — your report will be sent automatically when online.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'report_queued',
          'Report Queued',
          channelDescription: 'Notifies when a report is queued offline',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showQueueFlushed(int count) async {
    await init();
    await _plugin.show(
      3,
      '📡 Offline Reports Sent',
      '$count queued report(s) successfully submitted!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'report_flushed',
          'Queue Flushed',
          channelDescription: 'Queued offline reports were submitted',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showStatusChange(String reportId, String newStatus) async {
    await init();
    await _plugin.show(
      4,
      '🔔 Report Status Updated',
      'Report #$reportId → $newStatus',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'status_change',
          'Status Change',
          channelDescription: 'Notifies when a report status is updated',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
