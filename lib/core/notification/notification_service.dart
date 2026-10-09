import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/database.dart';

/// Thin wrapper around flutter_local_notifications (Android only).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channel = AndroidNotificationDetails(
    'doqit_reminders',
    'Reminders',
    channelDescription: 'Reminders for your notes',
    importance: Importance.high,
    priority: Priority.high,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Asks for the Android 13+ notification permission.
  /// Returns true if notifications are allowed.
  Future<bool> requestPermission() async {
    final android = _android;
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? await android.areNotificationsEnabled() ?? false;
  }

  /// Schedules a one-shot reminder. The note id doubles as the notification id,
  /// so scheduling again for the same note replaces the old reminder.
  /// Returns false if the time has passed or scheduling failed.
  Future<bool> schedule({
    required int noteId,
    required String title,
    required DateTime when,
  }) async {
    if (!when.isAfter(DateTime.now())) {
      await cancel(noteId);
      return false;
    }
    try {
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      await _plugin.zonedSchedule(
        id: noteId,
        title: title.trim().isEmpty ? 'Reminder' : title.trim(),
        body: 'Tap to open Doqit',
        // Only the instant matters for one-shot reminders, so UTC is enough.
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel(int noteId) => _plugin.cancel(id: noteId);

  /// Re-schedules every upcoming reminder (used after importing a backup).
  Future<void> syncAll(AppDatabase db) async {
    for (final n in await db.upcomingReminders()) {
      await schedule(noteId: n.id, title: n.title, when: n.reminderAt!);
    }
  }
}