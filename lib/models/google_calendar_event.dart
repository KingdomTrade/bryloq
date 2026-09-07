class GoogleCalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;

  const GoogleCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.description,
  });

  String get timeLabel {
    if (allDay) {
      return 'All day';
    }

    return '${_hhmm(start)}–${_hhmm(end)}';
  }

  static String _hhmm(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
