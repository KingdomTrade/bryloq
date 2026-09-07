class AiAction {
  final String title;
  final String type;
  final String? date;
  final String? time;
  final String priority;

  final bool recurring;
  final String? recurrence;

  final String recurrenceType;
  final int recurrenceInterval;
  final List<String> recurrenceWeekdays;
  final int? recurrenceDayOfMonth;

  final String? reminder;
  final String? notes;

  const AiAction({
    required this.title,
    required this.type,
    this.date,
    this.time,
    required this.priority,
    required this.recurring,
    this.recurrence,
    this.recurrenceType = 'none',
    this.recurrenceInterval = 1,
    this.recurrenceWeekdays = const [],
    this.recurrenceDayOfMonth,
    this.reminder,
    this.notes,
  });

  factory AiAction.fromJson(
    Map<String, dynamic> json,
  ) {
    final weekdaysRaw =
        json['recurrence_weekdays'];

    return AiAction(
      title:
          json['title']?.toString() ??
              'Untitled',
      type:
          json['type']?.toString() ??
              'task',
      date: json['date']?.toString(),
      time: json['time']?.toString(),
      priority:
          json['priority']?.toString() ??
              'normal',
      recurring:
          json['recurring'] == true,
      recurrence:
          json['recurrence']?.toString(),
      recurrenceType:
          json['recurrence_type']
                  ?.toString() ??
              'none',
      recurrenceInterval:
          json['recurrence_interval']
                  is int
              ? json['recurrence_interval']
              : int.tryParse(
                    json['recurrence_interval']
                            ?.toString() ??
                        '',
                  ) ??
                  1,
      recurrenceWeekdays:
          weekdaysRaw is List
              ? weekdaysRaw
                  .map(
                    (item) =>
                        item.toString(),
                  )
                  .toList()
              : const [],
      recurrenceDayOfMonth:
          json['recurrence_day_of_month']
                  is int
              ? json[
                  'recurrence_day_of_month']
              : int.tryParse(
                  json[
                              'recurrence_day_of_month']
                          ?.toString() ??
                      '',
                ),
      reminder:
          json['reminder']?.toString(),
      notes:
          json['notes']?.toString(),
    );
  }
}