class DayPlan {
  final String headline;
  final String summary;
  final String focus;
  final List<DayPlanItem> items;
  final List<String> carryOver;

  const DayPlan({
    required this.headline,
    required this.summary,
    required this.focus,
    required this.items,
    required this.carryOver,
  });

  factory DayPlan.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawCarryOver = json['carry_over'];

    return DayPlan(
      headline: json['headline']?.toString() ?? "Today's plan",
      summary: json['summary']?.toString() ?? '',
      focus: json['focus']?.toString() ?? '',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) => DayPlanItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : const [],
      carryOver: rawCarryOver is List
          ? rawCarryOver.map((item) => item.toString()).toList()
          : const [],
    );
  }

  factory DayPlan.fromMap(Map<dynamic, dynamic> map) {
    final rawItems = map['items'];
    final rawCarryOver = map['carry_over'];

    return DayPlan(
      headline: map['headline']?.toString() ?? "Today's plan",
      summary: map['summary']?.toString() ?? '',
      focus: map['focus']?.toString() ?? '',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(DayPlanItem.fromMap)
              .toList()
          : const [],
      carryOver: rawCarryOver is List
          ? rawCarryOver.map((item) => item.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'headline': headline,
      'summary': summary,
      'focus': focus,
      'items': items.map((item) => item.toMap()).toList(),
      'carry_over': carryOver,
    };
  }
}

class DayPlanItem {
  final String? taskId;
  final String title;
  final String startTime;
  final String endTime;
  final String kind;
  final String reason;

  const DayPlanItem({
    this.taskId,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.kind,
    required this.reason,
  });

  factory DayPlanItem.fromJson(Map<String, dynamic> json) {
    return DayPlanItem(
      taskId: json['task_id']?.toString(),
      title: json['title']?.toString() ?? 'Untitled',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'flexible',
      reason: json['reason']?.toString() ?? '',
    );
  }

  factory DayPlanItem.fromMap(Map<dynamic, dynamic> map) {
    return DayPlanItem(
      taskId: map['task_id']?.toString(),
      title: map['title']?.toString() ?? 'Untitled',
      startTime: map['start_time']?.toString() ?? '',
      endTime: map['end_time']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'flexible',
      reason: map['reason']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'task_id': taskId,
      'title': title,
      'start_time': startTime,
      'end_time': endTime,
      'kind': kind,
      'reason': reason,
    };
  }
}
