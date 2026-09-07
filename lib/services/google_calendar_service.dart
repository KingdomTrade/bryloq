import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/google_calendar_event.dart';
import '../models/saydo_task.dart';

class GoogleCalendarService {
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/calendar.events',
  ];

  final GoogleSignIn _signIn = GoogleSignIn.instance;

  GoogleSignInAccount? _account;
  bool _initialised = false;

  bool get isConnected => _account != null;
  String? get email => _account?.email;
  String? get displayName => _account?.displayName;
  String? get photoUrl => _account?.photoUrl;

  Future<void> initialise() async {
    if (_initialised) {
      return;
    }

    final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim();

    if (serverClientId == null || serverClientId.isEmpty) {
      throw Exception(
        'GOOGLE_WEB_CLIENT_ID is missing from .env.',
      );
    }

    await _signIn.initialize(
      serverClientId: serverClientId,
    );

    _initialised = true;

    final lightweight = _signIn.attemptLightweightAuthentication();
    if (lightweight != null) {
      try {
        _account = await lightweight;
      } catch (_) {
        _account = null;
      }
    }
  }

  Future<GoogleSignInAccount> connect() async {
    await initialise();

    if (!_signIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Google sign-in is not supported on this platform.',
      );
    }

    final account = await _signIn.authenticate(
      scopeHint: _scopes,
    );

    await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _account = account;
    return account;
  }

  Future<void> disconnect() async {
    await initialise();
    await _signIn.disconnect();
    _account = null;
  }

  Future<List<GoogleCalendarEvent>> eventsForDay(
    DateTime day,
  ) async {
    await initialise();

    final account = _account;
    if (account == null) {
      return const [];
    }

    final headers = await _authorizationHeaders(
      account,
      promptIfNecessary: false,
    );

    if (headers == null) {
      throw Exception(
        'Google Calendar permission needs to be renewed. Reconnect Calendar from Settings.',
      );
    }

    final startLocal = DateTime(
      day.year,
      day.month,
      day.day,
    );
    final endLocal = startLocal.add(
      const Duration(days: 1),
    );

    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
      <String, String>{
        'timeMin': startLocal.toUtc().toIso8601String(),
        'timeMax': endLocal.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '100',
      },
    );

    final response = await http.get(
      uri,
      headers: headers,
    );

    _throwForCalendarError(
      response,
      action: 'read Google Calendar',
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final items = decoded['items'];
    if (items is! List) {
      return const [];
    }

    final events = <GoogleCalendarEvent>[];

    for (final raw in items) {
      if (raw is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(raw);

      if (map['status']?.toString() == 'cancelled') {
        continue;
      }

      // Events explicitly marked transparent do not block time.
      if (map['transparency']?.toString() == 'transparent') {
        continue;
      }

      final event = _eventFromJson(map);
      if (event != null) {
        events.add(event);
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  Future<GoogleCalendarEvent> createEventForTask(
    SayDoTask task,
  ) async {
    await initialise();

    final account = _account;
    if (account == null) {
      throw Exception('Connect Google Calendar first.');
    }

    final dateText = task.date?.trim();
    if (dateText == null || dateText.isEmpty) {
      throw Exception(
        'Schedule this task with a date before adding it to Google Calendar.',
      );
    }

    final dateParts = dateText.split('-');
    if (dateParts.length != 3) {
      throw Exception('This task has an invalid date.');
    }

    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);

    if (year == null || month == null || day == null) {
      throw Exception('This task has an invalid date.');
    }

    final headers = await _authorizationHeaders(
      account,
      promptIfNecessary: true,
    );

    if (headers == null) {
      throw Exception('Google Calendar permission was not granted.');
    }

    final body = <String, dynamic>{
      'summary': task.title,
      'description': _eventDescription(task),
      'extendedProperties': {
        'private': {
          'saydoTaskId': task.id,
          'source': 'BRYLOQ',
        },
      },
    };

    final timeText = task.time?.trim();

    if (timeText == null || timeText.isEmpty) {
      final start = DateTime(year, month, day);
      final end = start.add(const Duration(days: 1));

      body['start'] = {
        'date': _dateKey(start),
      };
      body['end'] = {
        'date': _dateKey(end),
      };
    } else {
      final timeParts = timeText.split(':');
      if (timeParts.length < 2) {
        throw Exception('This task has an invalid time.');
      }

      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);

      if (hour == null || minute == null) {
        throw Exception('This task has an invalid time.');
      }

      final start = DateTime(
        year,
        month,
        day,
        hour,
        minute,
      );

      final durationMinutes =
          task.type == 'appointment' || task.type == 'event' ? 60 : 30;
      final end = start.add(
        Duration(minutes: durationMinutes),
      );

      body['start'] = {
        'dateTime': start.toUtc().toIso8601String(),
      };
      body['end'] = {
        'dateTime': end.toUtc().toIso8601String(),
      };
    }

    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
    );

    final response = await http.post(
      uri,
      headers: <String, String>{
        ...headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    _throwForCalendarError(
      response,
      action: 'create the Google Calendar event',
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Google Calendar returned an invalid event.');
    }

    final event = _eventFromJson(decoded);
    if (event == null) {
      throw Exception('Google Calendar returned an incomplete event.');
    }

    return event;
  }

  Future<Map<String, String>?> _authorizationHeaders(
    GoogleSignInAccount account, {
    required bool promptIfNecessary,
  }) {
    return account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: promptIfNecessary,
    );
  }

  GoogleCalendarEvent? _eventFromJson(
    Map<String, dynamic> map,
  ) {
    final startMap = map['start'];
    final endMap = map['end'];

    if (startMap is! Map || endMap is! Map) {
      return null;
    }

    final startDateTime = startMap['dateTime']?.toString();
    final endDateTime = endMap['dateTime']?.toString();
    final startDate = startMap['date']?.toString();
    final endDate = endMap['date']?.toString();

    final allDay = startDateTime == null;

    DateTime? start;
    DateTime? end;

    if (!allDay) {
      start = DateTime.tryParse(startDateTime)?.toLocal();
      end = DateTime.tryParse(endDateTime ?? '')?.toLocal();
    } else {
      start = DateTime.tryParse(startDate ?? '');
      end = DateTime.tryParse(endDate ?? '');
    }

    if (start == null || end == null) {
      return null;
    }

    return GoogleCalendarEvent(
      id: map['id']?.toString() ?? '',
      title: map['summary']?.toString().trim().isNotEmpty == true
          ? map['summary'].toString().trim()
          : 'Busy',
      start: start,
      end: end,
      allDay: allDay,
      location: map['location']?.toString(),
      description: map['description']?.toString(),
    );
  }

  String _eventDescription(SayDoTask task) {
    final parts = <String>[
      'Created by BRYLOQ',
    ];

    if (task.notes?.trim().isNotEmpty == true) {
      parts.add(task.notes!.trim());
    }

    if (task.recurring && task.recurrence?.trim().isNotEmpty == true) {
      parts.add('BRYLOQ recurrence: ${task.recurrence!.trim()}');
    }

    return parts.join('\n\n');
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  void _throwForCalendarError(
    http.Response response, {
    required String action,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String message =
        'Could not $action (${response.statusCode}).';

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final apiMessage = error['message']?.toString();
          if (apiMessage != null && apiMessage.trim().isNotEmpty) {
            message = apiMessage.trim();
          }
        }
      }
    } catch (_) {}

    throw Exception(message);
  }
}
