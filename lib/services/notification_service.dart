import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/saydo_task.dart';
import 'recurrence_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final RecurrenceService _recurrenceService = RecurrenceService();

  bool _initialised = false;

  static const int _morningBaseId = 1500000000;

  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'BRYLOQ_reminders',
      'BRYLOQ reminders',
      channelDescription: 'Task, appointment and routine reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const NotificationDetails _morningDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'saydo_morning',
      'Morning briefing',
      channelDescription: 'Your daily BRYLOQ morning briefing',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<void> initialise() async {
    if (_initialised) {
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
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

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );

    _initialised = true;
  }

  Future<bool> requestPermissions() async {
    await initialise();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> showTestNotification() async {
    await initialise();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _plugin.show(
      id: 100,
      title: 'BRYLOQ is ready',
      body: 'Android reminders are working.',
      notificationDetails: _reminderDetails,
      payload: 'test',
    );
  }

  Future<bool> scheduleTaskReminder(SayDoTask task) async {
    await initialise();

    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        task.completed) {
      return false;
    }

    await cancelTaskReminder(task.id);

    if (task.recurring && task.time?.trim().isNotEmpty == true) {
      final occurrences = _recurrenceService.generateOccurrences(
        task,
        count: 16,
      );

      int scheduled = 0;

      for (int i = 0; i < occurrences.length; i++) {
        final target = _withTaskTime(occurrences[i], task.time!);
        final reminderTarget = _applyReminderRule(target, task.reminder);

        if (reminderTarget == null ||
            !reminderTarget.isAfter(DateTime.now())) {
          continue;
        }

        await _schedule(
          id: _taskNotificationId(task.id, i),
          title: task.type == 'appointment'
              ? 'Upcoming appointment'
              : 'BRYLOQ reminder',
          body: task.title,
          when: reminderTarget,
          payload: task.id,
        );

        scheduled++;
      }

      return scheduled > 0;
    }

    final target = _singleReminderDateTime(task);

    if (target == null || !target.isAfter(DateTime.now())) {
      return false;
    }

    await _schedule(
      id: _taskNotificationId(task.id, 0),
      title: task.type == 'appointment'
          ? 'Upcoming appointment'
          : 'SayDo reminder',
      body: task.title,
      when: target,
      payload: task.id,
    );

    return true;
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await initialise();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    for (int i = 0; i < 20; i++) {
      await _plugin.cancel(
        id: _taskNotificationId(taskId, i),
      );
    }
  }

  Future<void> refreshMorningBriefings(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    for (int i = 0; i < 8; i++) {
      await _plugin.cancel(id: _morningBaseId + i);
    }

    final now = DateTime.now();
    int scheduled = 0;

    for (int dayOffset = 0; dayOffset < 8 && scheduled < 7; dayOffset++) {
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

      final message = _buildBriefingForDate(tasks, day);

      await _schedule(
        id: _morningBaseId + scheduled,
        title: 'Good morning 👋',
        body: message,
        when: when,
        payload: 'morning_briefing',
        details: _morningDetails,
      );

      scheduled++;
    }
  }

  Future<void> showMorningBriefingNow(
    List<SayDoTask> tasks,
  ) async {
    await initialise();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final today = DateTime.now();

    await _plugin.show(
      id: _morningBaseId + 99,
      title: 'Your BRYLOQ briefing',
      body: _buildBriefingForDate(tasks, today),
      notificationDetails: _morningDetails,
      payload: 'morning_briefing_test',
    );
  }

  Future<void> cancelAll() async {
    await initialise();
    await _plugin.cancelAll();
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    NotificationDetails details = _reminderDetails,
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
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  DateTime? _singleReminderDateTime(SayDoTask task) {
    final date = _parseDate(task.date);

    if (date == null) {
      return null;
    }

    if (task.time?.trim().isNotEmpty == true) {
      final target = _withTaskTime(date, task.time!);
      return _applyReminderRule(target, task.reminder);
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

    return null;
  }

  DateTime? _applyReminderRule(
    DateTime taskTime,
    String? reminder,
  ) {
    if (reminder == null || reminder.trim().isEmpty) {
      return taskTime;
    }

    final value = reminder.trim().toLowerCase();
    final explicit = _extractClock(value);

    if (explicit != null && !value.contains('before')) {
      return DateTime(
        taskTime.year,
        taskTime.month,
        taskTime.day,
        explicit.$1,
        explicit.$2,
      );
    }

    final minuteMatch = RegExp(r'(\d+)\s*minute').firstMatch(value);
    if (minuteMatch != null && value.contains('before')) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '');
      if (minutes != null) {
        return taskTime.subtract(Duration(minutes: minutes));
      }
    }

    final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(value);
    if (hourMatch != null && value.contains('before')) {
      final hours = int.tryParse(hourMatch.group(1) ?? '');
      if (hours != null) {
        return taskTime.subtract(Duration(hours: hours));
      }
    }

    if (value.contains('morning')) {
      return DateTime(
        taskTime.year,
        taskTime.month,
        taskTime.day,
        8,
      );
    }

    return taskTime;
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

  String _buildBriefingForDate(
    List<SayDoTask> tasks,
    DateTime day,
  ) {
    final key = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';

    final active = tasks.where((task) {
      return !task.completed && task.date == key;
    }).toList()
      ..sort((a, b) {
        final at = a.time ?? '99:99';
        final bt = b.time ?? '99:99';
        return at.compareTo(bt);
      });

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
      return 'Your day is clear. Add anything you need and BRYLOQ will organise it.';
    }

    final parts = <String>[];

    if (active.isNotEmpty) {
      parts.add(
        '${active.length} ${active.length == 1 ? 'item' : 'items'} today',
      );

      final first = active.first;
      if (first.time?.trim().isNotEmpty == true) {
        parts.add('first: ${first.title} at ${first.time}');
      } else {
        parts.add('first: ${first.title}');
      }
    }

    if (overdue > 0) {
      parts.add('$overdue overdue');
    }

    return '${parts.join(' • ')}.';
  }

  int _taskNotificationId(String taskId, int slot) {
    var hash = 2166136261;

    for (final unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    final base = hash % 1000000000;
    return base + slot;
  }
}
