import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_ce/hive.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/saydo_task.dart';
import 'recurrence_service.dart';

class BryloqNotificationAction {
  final String kind;
  final String actionId;
  final String? taskId;
  final int? minutesBefore;

  const BryloqNotificationAction({
    required this.kind,
    required this.actionId,
    this.taskId,
    this.minutesBefore,
  });

  bool get isTask => kind == 'task';
  bool get isDueNow => isTask && minutesBefore == 0;
  bool get isMorningBriefing => kind == 'morning';
  bool get isDone => actionId == NotificationService.actionDone;
  bool get isSnooze5 => actionId == NotificationService.actionSnooze5;
  bool get isSnooze15 => actionId == NotificationService.actionSnooze15;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String actionDone = 'bryloq_done';
  static const String actionSnooze5 = 'bryloq_snooze_5';
  static const String actionSnooze15 = 'bryloq_snooze_15';

  static const String _taskFinalCategory = 'bryloq_task_final';
  static const int _morningBaseId = 1500000000;
  static const String _metaBoxName = 'bryloq_notification_meta';
  static const String _lastMorningOpenKey = 'last_morning_open_briefing';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final RecurrenceService _recurrenceService = RecurrenceService();

  bool _initialised = false;
  Future<void> Function(BryloqNotificationAction action)? _actionHandler;
  BryloqNotificationAction? _pendingAction;

  bool get _supportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get _isApplePlatform {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  void setActionHandler(
    Future<void> Function(BryloqNotificationAction action)? handler,
  ) {
    _actionHandler = handler;

    final pending = _pendingAction;
    if (handler != null && pending != null) {
      _pendingAction = null;
      unawaited(handler(pending));
    }
  }

  Future<void> initialise() async {
    if (_initialised) {
      return;
    }

    if (!_supportedPlatform) {
      _initialised = true;
      return;
    }

    tz.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(
        tz.getLocation(timezoneInfo.identifier),
      );
    } catch (e) {
      debugPrint('Timezone setup warning: $e');
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const foregroundOption = DarwinNotificationActionOption.foreground;

    final darwinSettings = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _taskFinalCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              actionDone,
              'Done',
              options: <DarwinNotificationActionOption>{
                foregroundOption,
              },
            ),
            DarwinNotificationAction.plain(
              actionSnooze5,
              'Snooze 5 min',
              options: <DarwinNotificationActionOption>{
                foregroundOption,
              },
            ),
            DarwinNotificationAction.plain(
              actionSnooze15,
              'Snooze 15 min',
              options: <DarwinNotificationActionOption>{
                foregroundOption,
              },
            ),
          ],
        ),
      ],
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _receiveNotificationResponse,
    );

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;

      if (launchDetails?.didNotificationLaunchApp == true &&
          response != null) {
        _receiveNotificationResponse(response);
      }
    } catch (e) {
      debugPrint('Notification launch details warning: $e');
    }

    _initialised = true;
  }

  void _receiveNotificationResponse(NotificationResponse response) {
    final action = _decodeResponse(response);
    if (action == null) {
      return;
    }

    final handler = _actionHandler;
    if (handler == null) {
      _pendingAction = action;
      return;
    }

    unawaited(handler(action));
  }

  BryloqNotificationAction? _decodeResponse(NotificationResponse response) {
    final payload = response.payload?.trim();
    if (payload == null || payload.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return null;
      }

      final kind = decoded['kind']?.toString() ?? '';
      if (kind.isEmpty) {
        return null;
      }

      return BryloqNotificationAction(
        kind: kind,
        actionId: response.actionId?.trim() ?? '',
        taskId: decoded['taskId']?.toString(),
        minutesBefore: int.tryParse(decoded['minutesBefore']?.toString() ?? ''),
      );
    } catch (e) {
      debugPrint('Notification payload decode warning: $e');
      return null;
    }
  }

  Future<bool> requestPermissions() async {
    await initialise();

    if (!_supportedPlatform) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macos = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();

      final granted = await macos?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  Future<bool> canScheduleExactReminders() async {
    await initialise();

    if (!_supportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final allowed = await android?.canScheduleExactNotifications();
    return allowed ?? true;
  }

  Future<bool> requestExactReminderPermission() async {
    await initialise();

    if (!_supportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final alreadyAllowed = await android?.canScheduleExactNotifications();
    if (alreadyAllowed == true) {
      return true;
    }

    final granted = await android?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  Future<bool> requestFullScreenIntentPermission() async {
    await initialise();

    if (!_supportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.requestFullScreenIntentPermission();
    return granted ?? false;
  }

  Future<bool> openNotificationSettings() async {
    await initialise();

    if (!_supportedPlatform) {
      return false;
    }

    return await _plugin.openAppNotificationSettings() ?? false;
  }

  Future<void> showTestNotification() async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    await _plugin.show(
      id: 100,
      title: 'BRYLOQ is ready',
      body: 'Notifications are working on this device.',
      notificationDetails: _testDetails,
      payload: _encodePayload(kind: 'test'),
    );
  }

  Future<bool> scheduleTaskReminder(SayDoTask task) async {
    await initialise();

    if (!_supportedPlatform || task.completed) {
      return false;
    }

    await cancelTaskReminder(task.id);

    if (task.recurring && task.time?.trim().isNotEmpty == true) {
      final occurrences = _recurrenceService.generateOccurrences(
        task,
        count: _isApplePlatform ? 4 : 12,
      );

      int scheduled = 0;

      for (int i = 0; i < occurrences.length; i++) {
        final target = _withTaskTime(occurrences[i], task.time!);
        scheduled += await _scheduleReminderSequence(
          task: task,
          target: target,
          occurrenceIndex: i,
        );
      }

      return scheduled > 0;
    }

    final date = _parseDate(task.date);

    if (date != null && task.time?.trim().isNotEmpty == true) {
      final target = _withTaskTime(date, task.time!);
      final scheduled = await _scheduleReminderSequence(
        task: task,
        target: target,
        occurrenceIndex: 0,
      );
      return scheduled > 0;
    }

    final legacyTarget = _singleLegacyReminderDateTime(task);
    if (legacyTarget == null || !legacyTarget.isAfter(DateTime.now())) {
      return false;
    }

    await _schedule(
      id: _taskNotificationId(task.id, 0),
      title: 'BRYLOQ reminder',
      body: task.title,
      when: legacyTarget,
      payload: _encodePayload(
        kind: 'task',
        taskId: task.id,
        minutesBefore: 0,
      ),
      details: _detailsForTask(
        task,
        atTaskTime: true,
      ),
    );

    return true;
  }

  Future<int> _scheduleReminderSequence({
    required SayDoTask task,
    required DateTime target,
    required int occurrenceIndex,
  }) async {
    final now = DateTime.now();
    final alerts = <({int minutesBefore, String label})>[
      (minutesBefore: 30, label: '30 min'),
      (minutesBefore: 15, label: '15 min'),
      (minutesBefore: 5, label: '5 min'),
      (minutesBefore: 0, label: 'now'),
    ];

    int scheduled = 0;

    for (int stage = 0; stage < alerts.length; stage++) {
      final alert = alerts[stage];
      final when = target.subtract(
        Duration(minutes: alert.minutesBefore),
      );

      if (!when.isAfter(now)) {
        continue;
      }

      final atTaskTime = alert.minutesBefore == 0;
      final slot = (occurrenceIndex * 4) + stage;

      await _schedule(
        id: _taskNotificationId(task.id, slot),
        title: _taskNotificationTitle(
          task,
          minutesBefore: alert.minutesBefore,
        ),
        body: _taskNotificationBody(
          task,
          target: target,
          minutesBefore: alert.minutesBefore,
        ),
        when: when,
        payload: _encodePayload(
          kind: 'task',
          taskId: task.id,
          minutesBefore: alert.minutesBefore,
        ),
        details: _detailsForTask(
          task,
          atTaskTime: atTaskTime,
        ),
      );

      scheduled++;
    }

    return scheduled;
  }

  Future<void> snoozeTask(
    SayDoTask task,
    Duration duration,
  ) async {
    await initialise();

    if (!_supportedPlatform || task.completed) {
      return;
    }

    // Stop any currently ringing/insistent alert for this task first.
    // Rebuild future recurring occurrences, then add the requested snooze.
    await cancelTaskReminder(task.id);
    await scheduleTaskReminder(task);

    final when = DateTime.now().add(duration);

    await _schedule(
      id: _taskNotificationId(task.id, 79),
      title: '${task.title} — snoozed reminder',
      body: '${_priorityLabel(task.priority)} priority • Due now',
      when: when,
      payload: _encodePayload(
        kind: 'task',
        taskId: task.id,
        minutesBefore: 0,
      ),
      details: _detailsForTask(
        task,
        atTaskTime: true,
      ),
    );
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    for (int i = 0; i < 80; i++) {
      await _plugin.cancel(
        id: _taskNotificationId(taskId, i),
      );
    }
  }

  /// Rebuild Android task alarms from the saved task database.
  ///
  /// This is deliberately Android-only: it upgrades reminders that may have
  /// been created before exact-alarm access was granted, and repairs alarms
  /// after an app update. Android's AlarmManager delivers these notifications
  /// even when the Flutter UI process is not running.
  Future<int> refreshTaskReminders(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (!_supportedPlatform ||
        defaultTargetPlatform != TargetPlatform.android) {
      return 0;
    }

    int scheduled = 0;

    for (final task in tasks) {
      if (task.completed) {
        await cancelTaskReminder(task.id);
        continue;
      }

      if (await scheduleTaskReminder(task)) {
        scheduled++;
      }
    }

    return scheduled;
  }

  Future<void> maybeShowMorningBriefingOnAppOpen(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    final now = DateTime.now();

    // Closest safe approximation to "when the user starts their day":
    // if BRYLOQ itself is opened between 06:00 and 08:00, show the briefing
    // once immediately and skip the scheduled 08:00 copy for that date.
    if (now.hour < 6 || now.hour >= 8) {
      return;
    }

    try {
      final box = await Hive.openBox<dynamic>(_metaBoxName);
      final key = _dateKey(now);
      final alreadyShown = box.get(_lastMorningOpenKey)?.toString() == key;

      if (alreadyShown) {
        return;
      }

      await _plugin.cancel(id: _morningBaseId);
      await _showMorningBriefingForDate(tasks, now, id: _morningBaseId + 99);
      await box.put(_lastMorningOpenKey, key);
    } catch (e) {
      debugPrint('Morning app-open briefing warning: $e');
    }
  }

  Future<void> refreshMorningBriefings(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    for (int i = 0; i < 8; i++) {
      await _plugin.cancel(id: _morningBaseId + i);
    }

    final now = DateTime.now();
    String? morningAlreadyShownFor;

    try {
      final box = await Hive.openBox<dynamic>(_metaBoxName);
      morningAlreadyShownFor = box.get(_lastMorningOpenKey)?.toString();
    } catch (_) {
      // Notification scheduling should continue even if metadata cannot open.
    }

    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day + dayOffset,
      );

      final when = DateTime(
        day.year,
        day.month,
        day.day,
        8,
      );

      if (!when.isAfter(now)) {
        continue;
      }

      if (dayOffset == 0 && morningAlreadyShownFor == _dateKey(day)) {
        continue;
      }

      await _schedule(
        id: _morningBaseId + dayOffset,
        title: _briefingTitleForDate(tasks, day),
        body: _buildBriefingForDate(tasks, day),
        when: when,
        payload: _encodePayload(kind: 'morning'),
        details: _morningDetails,
      );
    }
  }

  Future<void> showMorningBriefingNow(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    await _showMorningBriefingForDate(
      tasks,
      DateTime.now(),
      id: _morningBaseId + 98,
    );
  }

  Future<void> _showMorningBriefingForDate(
    List<SayDoTask> tasks,
    DateTime day, {
    required int id,
  }) async {
    await _plugin.show(
      id: id,
      title: _briefingTitleForDate(tasks, day),
      body: _buildBriefingForDate(tasks, day),
      notificationDetails: _morningDetails,
      payload: _encodePayload(kind: 'morning'),
    );
  }

  Future<void> cancelAll() async {
    await initialise();

    if (!_supportedPlatform) {
      return;
    }

    await _plugin.cancelAll();
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    required NotificationDetails details,
  }) async {
    final scheduledDate = tz.TZDateTime(
      tz.local,
      when.year,
      when.month,
      when.day,
      when.hour,
      when.minute,
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: await canScheduleExactReminders()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  NotificationDetails _detailsForTask(
    SayDoTask task, {
    required bool atTaskTime,
  }) {
    final priority = _normalisePriority(task.priority);

    final androidActions = atTaskTime
        ? const <AndroidNotificationAction>[
            AndroidNotificationAction(
              actionDone,
              'Done',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              actionSnooze5,
              'Snooze 5m',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              actionSnooze15,
              'Snooze 15m',
              showsUserInterface: true,
            ),
          ]
        : const <AndroidNotificationAction>[];

    final AndroidNotificationDetails android;
    final InterruptionLevel interruptionLevel;

    switch (priority) {
      case 'high':
        final isDueAlarm = atTaskTime;

        android = AndroidNotificationDetails(
          isDueAlarm
              ? 'bryloq_high_due_alarm_v1'
              : 'bryloq_task_high_upcoming_v4',
          isDueAlarm
              ? 'High priority due alarms'
              : 'High priority task reminders',
          channelDescription: isDueAlarm
              ? 'Alarm-style alerts when a high priority BRYLOQ task is due'
              : 'Prominent advance reminders for high priority BRYLOQ tasks',
          importance: Importance.max,
          priority: Priority.max,
          category: isDueAlarm
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          enableVibration: true,
          vibrationPattern: isDueAlarm
              ? Int64List.fromList(<int>[
                  0,
                  700,
                  250,
                  700,
                  250,
                  1200,
                ])
              : null,
          playSound: true,
          audioAttributesUsage: isDueAlarm
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          fullScreenIntent: isDueAlarm,
          // FLAG_INSISTENT: repeat the alert sound until the notification is
          // acted on/dismissed. This is used only for HIGH priority at due time.
          additionalFlags:
              isDueAlarm ? Int32List.fromList(<int>[4]) : null,
          ticker: isDueAlarm ? 'High priority task due now' : null,
          timeoutAfter: isDueAlarm ? 180000 : null,
          actions: androidActions,
        );
        interruptionLevel = InterruptionLevel.timeSensitive;
        break;
      case 'low':
        android = AndroidNotificationDetails(
          'bryloq_task_low_v3',
          'Low priority tasks',
          channelDescription: 'Gentle reminders for low priority BRYLOQ tasks',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          enableVibration: false,
          playSound: true,
          actions: androidActions,
        );
        interruptionLevel = InterruptionLevel.passive;
        break;
      default:
        android = AndroidNotificationDetails(
          'bryloq_task_medium_v3',
          'Medium priority tasks',
          channelDescription: 'Standard reminders for BRYLOQ tasks',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          enableVibration: true,
          playSound: true,
          actions: androidActions,
        );
        interruptionLevel = InterruptionLevel.active;
    }

    final darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: interruptionLevel,
      threadIdentifier: 'bryloq_tasks',
      categoryIdentifier: atTaskTime ? _taskFinalCategory : null,
    );

    return NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
  }

  static const NotificationDetails _morningDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'bryloq_morning_v2',
      'Morning briefing',
      channelDescription: 'Your daily BRYLOQ task summary',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
      threadIdentifier: 'bryloq_morning',
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
      threadIdentifier: 'bryloq_morning',
    ),
  );

  static const NotificationDetails _testDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'bryloq_test_v2',
      'BRYLOQ test notifications',
      channelDescription: 'Used to verify BRYLOQ notification permissions',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  String _taskNotificationTitle(
    SayDoTask task, {
    required int minutesBefore,
  }) {
    final title = task.title.trim().isEmpty ? 'Your task' : task.title.trim();
    final priority = _normalisePriority(task.priority);

    if (minutesBefore == 0) {
      if (priority == 'high') {
        return 'HIGH PRIORITY • $title — due now';
      }
      return '$title — due now';
    }

    if (priority == 'high') {
      return 'HIGH PRIORITY • $minutesBefore min until $title';
    }

    return '$minutesBefore min until $title';
  }

  String _taskNotificationBody(
    SayDoTask task, {
    required DateTime target,
    required int minutesBefore,
  }) {
    final priority = _priorityLabel(task.priority);
    final dueTime = _formatClock(target);

    if (minutesBefore == 0) {
      return '$priority priority • Due now • Use Done or Snooze below';
    }

    return 'Due at $dueTime • $priority priority';
  }

  String _formatClock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _priorityLabel(String value) {
    switch (_normalisePriority(value)) {
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Medium';
    }
  }

  DateTime? _singleLegacyReminderDateTime(SayDoTask task) {
    final date = _parseDate(task.date);

    if (date == null) {
      return null;
    }

    final explicitReminderTime = _extractClock(task.reminder);

    if (explicitReminderTime != null) {
      return DateTime(
        date.year,
        date.month,
        date.day,
        explicitReminderTime.$1,
        explicitReminderTime.$2,
      );
    }

    final value = task.reminder?.trim().toLowerCase() ?? '';
    if (value.contains('morning')) {
      return DateTime(
        date.year,
        date.month,
        date.day,
        8,
      );
    }

    return null;
  }

  DateTime _withTaskTime(DateTime date, String time) {
    final parts = time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
  }

  (int, int)? _extractClock(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    final match = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b')
        .firstMatch(text.trim());

    if (match == null) {
      return null;
    }

    return (
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value.trim());
  }

  String _briefingTitleForDate(
    List<SayDoTask> tasks,
    DateTime day,
  ) {
    final active = _tasksForDate(tasks, day);
    final highCount = active
        .where((task) => _normalisePriority(task.priority) == 'high')
        .length;

    if (active.isEmpty) {
      return 'Good morning • Your day is clear';
    }

    if (highCount > 0) {
      return '${active.length} today • $highCount high priority';
    }

    return '${active.length} ${active.length == 1 ? 'task' : 'tasks'} today';
  }

  String _buildBriefingForDate(
    List<SayDoTask> tasks,
    DateTime day,
  ) {
    final active = _tasksForDate(tasks, day);

    final todayOnly = DateTime.now();
    final isToday = day.year == todayOnly.year &&
        day.month == todayOnly.month &&
        day.day == todayOnly.day;

    final overdue = isToday
        ? tasks.where((task) {
            if (task.completed || task.date == null) {
              return false;
            }
            final parsed = DateTime.tryParse(task.date!);
            return parsed != null &&
                parsed.isBefore(DateTime(day.year, day.month, day.day));
          }).length
        : 0;

    if (active.isEmpty && overdue == 0) {
      return 'Nothing scheduled yet. Add anything you need and BRYLOQ will organise it.';
    }

    final lines = <String>[];

    for (final task in active.take(3)) {
      final time = task.time?.trim().isNotEmpty == true ? task.time! : 'Any time';
      final priority = _normalisePriority(task.priority);
      final marker = priority == 'high'
          ? 'High'
          : priority == 'low'
              ? 'Low'
              : 'Medium';
      lines.add('$time — ${task.title} ($marker)');
    }

    var body = lines.join(' • ');

    if (active.length > 3) {
      body += ' • +${active.length - 3} more';
    }

    if (overdue > 0) {
      body += ' • $overdue overdue';
    }

    return body;
  }


  List<SayDoTask> _tasksForDate(
    List<SayDoTask> tasks,
    DateTime day,
  ) {
    final key = _dateKey(day);

    final active = tasks.where((task) {
      return !task.completed && task.date == key;
    }).toList();

    active.sort((a, b) {
      final priorityCompare = _priorityRank(a.priority).compareTo(
        _priorityRank(b.priority),
      );

      if (priorityCompare != 0) {
        return priorityCompare;
      }

      final at = a.time ?? '99:99';
      final bt = b.time ?? '99:99';
      final timeCompare = at.compareTo(bt);

      if (timeCompare != 0) {
        return timeCompare;
      }

      return a.createdAt.compareTo(b.createdAt);
    });

    return active;
  }

  static String _normalisePriority(String value) {
    final priority = value.trim().toLowerCase();

    if (priority == 'high') {
      return 'high';
    }
    if (priority == 'low') {
      return 'low';
    }
    return 'normal';
  }

  static int _priorityRank(String value) {
    switch (_normalisePriority(value)) {
      case 'high':
        return 0;
      case 'normal':
        return 1;
      case 'low':
        return 2;
    }

    return 1;
  }

  String _encodePayload({
    required String kind,
    String? taskId,
    int? minutesBefore,
  }) {
    final payload = <String, dynamic>{
      'kind': kind,
    };

    if (taskId != null) {
      payload['taskId'] = taskId;
    }

    if (minutesBefore != null) {
      payload['minutesBefore'] = minutesBefore;
    }

    return jsonEncode(payload);
  }

  static String _dateKey(DateTime day) {
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  int _taskNotificationId(String taskId, int slot) {
    var hash = 2166136261;

    for (final unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    final base = hash % 900000000;
    return base + slot;
  }
}
