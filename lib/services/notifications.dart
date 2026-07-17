import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications for the package exporter:
/// a single immediate "export ready" notification shown when a job finishes
/// while the app is backgrounded. No scheduling, so no timezone setup.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _permissionAsked = false;

  static const _exportReadyId = 1001;

  /// Called when the user taps a notification (app brought to foreground).
  static void Function()? onTap;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );
    _ready = true;
  }

  /// Lazy permission request — called once, the first time an export starts.
  /// Denial is fine: the in-app flow doesn't depend on notifications.
  static Future<void> requestPermissionOnce() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    await init();
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: false, sound: true);
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  static NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'exports',
      'Exports',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> showExportReady(String label) async {
    await init();
    try {
      await _plugin.show(
        _exportReadyId,
        'Export ready',
        '"$label" is ready to share — open Metro Sound.',
        _details,
      );
    } catch (_) {}
  }

  static Future<void> cancelExportReady() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_exportReadyId);
    } catch (_) {}
  }
}
