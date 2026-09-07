class SayDoTask {
  final String id;
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

  final bool completed;
  final DateTime createdAt;

  const SayDoTask({
    required this.id,
    required this.title,
    required this.type,
    this.date,
    this.time,
    required this.priority,
    required this.recurring,
    this.recurrence,
    this.recurrenceType = 'none',
    this.recurrenceInterval = 1,
    this.recurrenceWeekdays =
        const [],
    this.recurrenceDayOfMonth,
    this.reminder,
    this.notes,
    required this.completed,
    required this.createdAt,
  });

  SayDoTask copyWith({
    String? id,
    String? title,
    String? type,
    String? date,
    String? time,
    String? priority,
    bool? recurring,
    String? recurrence,
    String? recurrenceType,
    int? recurrenceInterval,
    List<String>?
        recurrenceWeekdays,
    int? recurrenceDayOfMonth,
    String? reminder,
    String? notes,
    bool? completed,
    DateTime? createdAt,
  }) {
    return SayDoTask(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      date: date ?? this.date,
      time: time ?? this.time,
      priority:
          priority ?? this.priority,
      recurring:
          recurring ?? this.recurring,
      recurrence:
          recurrence ?? this.recurrence,
      recurrenceType:
          recurrenceType ??
              this.recurrenceType,
      recurrenceInterval:
          recurrenceInterval ??
              this.recurrenceInterval,
      recurrenceWeekdays:
          recurrenceWeekdays ??
              this.recurrenceWeekdays,
      recurrenceDayOfMonth:
          recurrenceDayOfMonth ??
              this.recurrenceDayOfMonth,
      reminder:
          reminder ?? this.reminder,
      notes: notes ?? this.notes,
      completed:
          completed ?? this.completed,
      createdAt:
          createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'date': date,
      'time': time,
      'priority': priority,
      'recurring': recurring,
      'recurrence': recurrence,
      'recurrenceType':
          recurrenceType,
      'recurrenceInterval':
          recurrenceInterval,
      'recurrenceWeekdays':
          recurrenceWeekdays,
      'recurrenceDayOfMonth':
          recurrenceDayOfMonth,
      'reminder': reminder,
      'notes': notes,
      'completed': completed,
      'createdAt':
          createdAt.toIso8601String(),
    };
  }

  factory SayDoTask.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    final weekdays =
        map['recurrenceWeekdays'];

    return SayDoTask(
      id: map['id']?.toString() ?? '',
      title:
          map['title']?.toString() ??
              '',
      type:
          map['type']?.toString() ??
              'task',
      date: map['date']?.toString(),
      time: map['time']?.toString(),
      priority:
          map['priority']?.toString() ??
              'normal',

      recurring:
          map['recurring'] == true,

      recurrence:
          map['recurrence']?.toString(),

      recurrenceType:
          map['recurrenceType']
                  ?.toString() ??
              'none',

      recurrenceInterval:
          map['recurrenceInterval']
                  is int
              ? map[
                  'recurrenceInterval']
              : int.tryParse(
                    map[
                                'recurrenceInterval']
                            ?.toString() ??
                        '',
                  ) ??
                  1,

      recurrenceWeekdays:
          weekdays is List
              ? weekdays
                  .map(
                    (item) =>
                        item.toString(),
                  )
                  .toList()
              : const [],

      recurrenceDayOfMonth:
          map['recurrenceDayOfMonth']
                  is int
              ? map[
                  'recurrenceDayOfMonth']
              : int.tryParse(
                  map[
                              'recurrenceDayOfMonth']
                          ?.toString() ??
                      '',
                ),

      reminder:
          map['reminder']?.toString(),

      notes:
          map['notes']?.toString(),

      completed:
          map['completed'] == true,

      createdAt:
          DateTime.tryParse(
            map['createdAt']
                    ?.toString() ??
                '',
          ) ??
          DateTime.now(),
    );
  }
}