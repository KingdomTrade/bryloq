import '../models/saydo_task.dart';

class RecurrenceService {
  DateTime? nextOccurrence(SayDoTask task) {
    if (!task.recurring) {
      return null;
    }

    final anchor = _parseDate(task.date) ?? DateTime.now();
    return _nextAfter(
      task,
      DateTime(anchor.year, anchor.month, anchor.day),
    );
  }

  List<DateTime> generateOccurrences(
    SayDoTask task, {
    int count = 12,
  }) {
    if (!task.recurring || count <= 0) {
      return const [];
    }

    final anchor = _parseDate(task.date) ?? DateTime.now();
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final result = <DateTime>[];
    var cursor = DateTime(anchor.year, anchor.month, anchor.day);

    if (!cursor.isBefore(todayDate)) {
      result.add(cursor);
    }

    for (int guard = 0; guard < 2000 && result.length < count; guard++) {
      cursor = _nextAfter(task, cursor);

      if (!cursor.isBefore(todayDate)) {
        result.add(cursor);
      }
    }

    return result.take(count).toList();
  }

  DateTime _nextAfter(SayDoTask task, DateTime current) {
    final interval = task.recurrenceInterval <= 0
        ? 1
        : task.recurrenceInterval;

    switch (task.recurrenceType) {
      case 'daily':
        return current.add(Duration(days: interval));
      case 'weekly':
        return _nextWeekly(current, task.recurrenceWeekdays, interval);
      case 'monthly':
        return _nextMonthly(
          current,
          interval,
          task.recurrenceDayOfMonth,
        );
      case 'yearly':
        return _safeDate(
          current.year + interval,
          current.month,
          current.day,
        );
      default:
        return _fallbackNext(current, task);
    }
  }

  DateTime _nextWeekly(
    DateTime current,
    List<String> weekdays,
    int interval,
  ) {
    final wanted = weekdays
        .map(_weekdayNumber)
        .whereType<int>()
        .toSet();

    if (wanted.isEmpty) {
      return current.add(Duration(days: 7 * interval));
    }

    final anchorWeekStart = current.subtract(
      Duration(days: current.weekday - DateTime.monday),
    );

    for (int offset = 1; offset <= (7 * interval) + 7; offset++) {
      final candidate = current.add(Duration(days: offset));

      if (!wanted.contains(candidate.weekday)) {
        continue;
      }

      final candidateWeekStart = candidate.subtract(
        Duration(days: candidate.weekday - DateTime.monday),
      );

      final weekDistance =
          candidateWeekStart.difference(anchorWeekStart).inDays ~/ 7;

      if (weekDistance == 0 || weekDistance % interval == 0) {
        return candidate;
      }
    }

    return current.add(Duration(days: 7 * interval));
  }

  DateTime _nextMonthly(
    DateTime current,
    int interval,
    int? requestedDay,
  ) {
    var month = current.month + interval;
    var year = current.year;

    while (month > 12) {
      month -= 12;
      year++;
    }

    final day = requestedDay ?? current.day;
    return _safeDate(year, month, day);
  }

  DateTime _fallbackNext(
    DateTime current,
    SayDoTask task,
  ) {
    final text = (task.recurrence ?? '').toLowerCase();

    if (text.contains('weekday')) {
      var candidate = current.add(const Duration(days: 1));
      while (candidate.weekday == DateTime.saturday ||
          candidate.weekday == DateTime.sunday) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    if (text.contains('day')) {
      return current.add(const Duration(days: 1));
    }

    if (text.contains('month')) {
      return _nextMonthly(current, 1, task.recurrenceDayOfMonth);
    }

    if (text.contains('year')) {
      return _safeDate(current.year + 1, current.month, current.day);
    }

    return current.add(const Duration(days: 7));
  }

  DateTime _safeDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value.trim());
  }

  int? _weekdayNumber(String value) {
    switch (value.trim().toLowerCase()) {
      case 'monday':
      case 'mon':
        return DateTime.monday;
      case 'tuesday':
      case 'tue':
        return DateTime.tuesday;
      case 'wednesday':
      case 'wed':
        return DateTime.wednesday;
      case 'thursday':
      case 'thu':
        return DateTime.thursday;
      case 'friday':
      case 'fri':
        return DateTime.friday;
      case 'saturday':
      case 'sat':
        return DateTime.saturday;
      case 'sunday':
      case 'sun':
        return DateTime.sunday;
    }

    return null;
  }

  String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
