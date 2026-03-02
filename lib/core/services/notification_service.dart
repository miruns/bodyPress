import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around `flutter_local_notifications` scoped to the channels
/// BodyPress needs.
///
/// Two channels:
/// - **Background Captures** — used by the [CaptureExecutor] to surface
///   results to the user.
/// - **Daily Body Blog** — a once-per-day mindful reminder styled as a
///   "new post from your body".
class NotificationService {
  static final NotificationService _instance = NotificationService._();

  factory NotificationService() => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  // ── Channel IDs ─────────────────────────────────────────────────────────

  static const _dailyChannelId = 'bodypress_daily_reminder';
  static const _dailyChannelName = 'Daily Body Blog';
  static const _dailyChannelDescription =
      'A gentle daily reminder to check in with your body';

  static const _dailyNotifId = 9001;

  // ── Mindful notification messages ───────────────────────────────────────

  static const dailyMessages = <({String title, String body})>[
    (
      title: 'Your body published a new post',
      body:
          'A quiet check-in is waiting. See what today looks like from the inside.',
    ),
    (
      title: 'New entry in your body\'s journal',
      body: 'Your body has been writing all day. Take a moment to read.',
    ),
    (
      title: 'A letter from your body',
      body: 'Small signals, big insights. Your daily snapshot is ready.',
    ),
    (
      title: 'Your body has something to share',
      body: 'It noticed things you might have missed. Take a gentle look.',
    ),
    (
      title: 'Today\'s body blog is live',
      body: 'Steps, rest, rhythm — your body summed it all up for you.',
    ),
    (
      title: 'Fresh post from your body',
      body: 'No rush. Whenever you\'re ready, your daily read is here.',
    ),
    (
      title: 'Your body left you a note',
      body: 'A few mindful observations about your day so far.',
    ),
    (
      title: 'New chapter in your body story',
      body: 'Every day writes itself. Here\'s what yours had to say.',
    ),
    (
      title: 'A moment of body awareness',
      body: 'Pause. Breathe. Your daily body snapshot is waiting.',
    ),
    (
      title: 'Your body checked in',
      body: 'A simple, honest summary of how you\'re doing today.',
    ),
    (
      title: 'Your wellness digest is ready',
      body: 'One calm page about your body\'s day. No noise, just truth.',
    ),
    (
      title: 'A gentle nudge from within',
      body: 'Your body kept notes today. See what it observed.',
    ),
    (
      title: 'Daily body update',
      body: 'Movement, rest, environment — a mindful recap of your day.',
    ),
    (
      title: 'Your body wrote today\'s page',
      body: 'Living is writing. Here\'s what your body composed.',
    ),
    (
      title: 'Body blog · new post',
      body: 'A quiet moment to reconnect with how you\'re really feeling.',
    ),
    (
      title: 'Your inner journal was updated',
      body:
          'Your body speaks in patterns. Today\'s patterns are ready to read.',
    ),
    (
      title: 'Listen inward for a moment',
      body:
          'Your daily body snapshot was just prepared. Take a breath and look.',
    ),
    (
      title: 'Your body has news',
      body: 'Nothing urgent — just a mindful summary of your day.',
    ),
    (
      title: 'New post: Today\'s body story',
      body: 'Some days are loud, some are still. See which kind today was.',
    ),
    (
      title: 'Your daily wellness page',
      body: 'Written by your body, for you. Simple, honest, and kind.',
    ),
  ];

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Initialise the notification plugin and create Android channels.
  ///
  /// Safe to call more than once — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialised) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Create Android notification channels (no-op on iOS).
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyChannelId,
          _dailyChannelName,
          description: _dailyChannelDescription,
          importance: Importance.high,
        ),
      );
    }

    _initialised = true;
  }

  // ── Public helpers ────────────────────────────────────────────────────

  /// Request notification permission on Android 13+ / iOS.
  Future<bool> requestPermission() async {
    // Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  // ── Daily reminder scheduling ─────────────────────────────────────────

  /// Schedule a daily notification at the given [hour] and [minute].
  ///
  /// Replaces any previously scheduled daily reminder. The notification
  /// picks a random message from [dailyMessages] each time it fires.
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    await _ensureInitialised();

    // Cancel any existing daily reminder first.
    await _plugin.cancel(_dailyNotifId);

    // Pick a random message (the OS will show this; on each day it's
    // the same until the app reschedules — good enough for v1).
    final msg = dailyMessages[Random().nextInt(dailyMessages.length)];

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // If that time already passed today, start from tomorrow.
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _dailyNotifId,
      msg.title,
      msg.body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          _dailyChannelName,
          channelDescription: _dailyChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // ← repeats daily
    );
  }

  /// Cancel the daily body-blog reminder.
  Future<void> cancelDailyReminder() async {
    await _ensureInitialised();
    await _plugin.cancel(_dailyNotifId);
  }

  /// Show a test daily notification immediately (for the debug panel).
  Future<void> showTestDailyReminder() async {
    await _ensureInitialised();

    final msg = dailyMessages[Random().nextInt(dailyMessages.length)];

    await _plugin.show(
      _dailyNotifId + 1, // different ID so it doesn't cancel the real one
      msg.title,
      msg.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          _dailyChannelName,
          channelDescription: _dailyChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _ensureInitialised() async {
    if (!_initialised) await initialize();
  }
}
