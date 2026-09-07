import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../models/ai_action.dart';
import '../models/day_plan.dart';
import '../models/google_calendar_event.dart';
import '../models/saydo_task.dart';

class AiService {
  static const String _model = 'gemini-3.6-flash';

  Future<List<AiAction>> organiseText(
    String userText,
  ) async {
    if (userText.trim().isEmpty) {
      return [];
    }

    return _sendToGemini(
      text: userText,
    );
  }

  Future<List<AiAction>> organiseImage({
    required Uint8List imageBytes,
    required String mimeType,
    String? instruction,
  }) async {
    if (imageBytes.isEmpty) {
      return [];
    }

    final prompt = instruction?.trim().isNotEmpty == true
        ? instruction!.trim()
        : '''
Analyse this image carefully.

It may contain:
- an appointment
- WhatsApp/message screenshot
- bill
- letter
- handwritten note
- event poster
- school letter
- receipt
- reminder
- task list

Extract every useful actionable item.

Do not merely describe the image.

Turn actionable information into BRYLOQ actions.

For example:

If the image says:
"Dentist appointment Friday 14 September at 3:30 PM"

create:
Appointment: Dentist
date: the appropriate date
time: 15:30

If a screenshot says:
"Can you send me those documents by Thursday?"

create:
Task: Send documents
date: Thursday

If an event poster contains an event date/time,
create an event.

If useful text is present but no action is required,
create a note.

Do not invent information that is not visible.
''';

    return _sendToGemini(
      text: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
  }

  Future<List<AiAction>> organiseFile({
    required Uint8List fileBytes,
    required String mimeType,
    required String fileName,
    String? instruction,
  }) async {
    if (fileBytes.isEmpty) {
      return [];
    }

    final lowerName =
        fileName.toLowerCase();

    if (mimeType.startsWith(
          'image/',
        ) ||
        lowerName.endsWith(
          '.jpg',
        ) ||
        lowerName.endsWith(
          '.jpeg',
        ) ||
        lowerName.endsWith(
          '.png',
        ) ||
        lowerName.endsWith(
          '.webp',
        ) ||
        lowerName.endsWith(
          '.heic',
        ) ||
        lowerName.endsWith(
          '.heif',
        )) {
      return organiseImage(
        imageBytes: fileBytes,
        mimeType: mimeType,
        instruction: instruction,
      );
    }

    final isTextFile =
        mimeType.startsWith(
          'text/',
        ) ||
        mimeType ==
            'application/json' ||
        lowerName.endsWith(
          '.txt',
        ) ||
        lowerName.endsWith(
          '.md',
        ) ||
        lowerName.endsWith(
          '.csv',
        ) ||
        lowerName.endsWith(
          '.json',
        );

    if (isTextFile) {
      final content = utf8.decode(
        fileBytes,
        allowMalformed: true,
      );

      final prompt =
          instruction?.trim().isNotEmpty ==
                  true
              ? instruction!.trim()
              : '''
The user supplied a file called "$fileName".

Read the content below and extract every
useful actionable item for BRYLOQ.

Do not merely summarize the file.

Create tasks, reminders, appointments,
events, shopping items, routines, notes,
or follow-ups when appropriate.

Preserve important names, dates, times,
amounts and deadlines.

Do not invent missing information.

FILE CONTENT:

$content
''';

      return _sendToGemini(
        text: prompt,
      );
    }

    if (mimeType ==
            'application/pdf' ||
        lowerName.endsWith(
          '.pdf',
        )) {
      final prompt =
          instruction?.trim().isNotEmpty ==
                  true
              ? instruction!.trim()
              : '''
Analyse the attached PDF "$fileName".

Extract every useful actionable item for BRYLOQ.

Do not merely summarize the PDF.

Create tasks, reminders, appointments,
events, routines, notes or follow-ups
where appropriate.

Preserve important names, dates, times,
amounts and deadlines.

Do not invent information that is not
contained in the PDF.
''';

      return _sendToGemini(
        text: prompt,
        imageBytes: fileBytes,
        mimeType: 'application/pdf',
      );
    }

    throw Exception(
      'This file type is not supported yet. '
      'Use PDF, TXT, MD, CSV, JSON or an image.',
    );
  }

  Future<DayPlan> planDay(
    List<SayDoTask> tasks, {
    List<GoogleCalendarEvent> calendarEvents = const [],
  }) async {
    final activeTasks = tasks
        .where((task) => !task.completed)
        .toList();

    if (activeTasks.isEmpty) {
      return const DayPlan(
        headline: 'A clear day',
        summary: 'You have no active tasks to schedule.',
        focus: 'Use the space for rest, preparation, or something meaningful.',
        items: [],
        carryOver: [],
      );
    }

    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final calendarLines = calendarEvents.isEmpty
        ? 'No Google Calendar events for today.'
        : calendarEvents.map((event) {
            final time = event.allDay
                ? 'ALL DAY'
                : '${_hhmm(event.start)}-${_hhmm(event.end)}';

            final location = event.location?.trim().isNotEmpty == true
                ? event.location!.trim()
                : 'none';

            return '''
CALENDAR EVENT: ${event.title}
TIME: $time
LOCATION: $location
ALL DAY: ${event.allDay}
''';
          }).join('\n---\n');

    final taskLines = activeTasks.map((task) {
      final date = task.date?.trim().isNotEmpty == true
          ? task.date!.trim()
          : 'none';
      final time = task.time?.trim().isNotEmpty == true
          ? task.time!.trim()
          : 'none';
      final notes = task.notes?.trim().isNotEmpty == true
          ? task.notes!.trim()
          : 'none';
      final recurrence = task.recurring
          ? (task.recurrence?.trim().isNotEmpty == true
              ? task.recurrence!.trim()
              : 'recurring')
          : 'not recurring';

      return '''
TASK ID: ${task.id}
TITLE: ${task.title}
TYPE: ${task.type}
DATE: $date
TIME: $time
PRIORITY: ${task.priority}
RECURRENCE: $recurrence
NOTES: $notes
''';
    }).join('\n---\n');

    final prompt = '''
You are the planning engine for BRYLOQ.

Today is $today.
The current local time is $currentTime.

Create a realistic plan for the rest of today using the user's ACTIVE tasks below.

PLANNING RULES:

1. Respect tasks that already have a specific time today. Those are fixed commitments.
2. Prioritise overdue tasks, tasks dated today, and high-priority tasks.
3. Google Calendar events are fixed commitments. Never schedule a BRYLOQ task over a timed Google Calendar event.
4. Include timed Google Calendar events in the returned flow as kind = fixed, task_id = null, using their exact start and end times.
5. All-day Google Calendar events are context. Do not automatically block the entire day unless the event clearly represents an all-day commitment.
6. Undated tasks may be scheduled if there is realistic space.
7. Do not pull ordinary future-dated tasks into today unless there is a strong reason.
8. Never schedule anything in the past. If it is already later in the day, start from a sensible time after $currentTime.
9. Avoid overlapping items.
10. For tasks without a duration, estimate a reasonable block, normally 30 to 90 minutes.
11. Include short breaks when the schedule would otherwise be too dense. Breaks must have task_id = null.
12. Do not invent appointments, deadlines, or obligations.
13. If everything cannot reasonably fit today, put the remaining task titles in carry_over.
14. Use 24-hour HH:mm times.
15. Use the exact task ID supplied when a plan item corresponds to a saved BRYLOQ task.
16. Keep the plan practical, not over-packed.

GOOGLE CALENDAR EVENTS:

$calendarLines

ACTIVE BRYLOQ TASKS:

$taskLines
''';

    final schema = {
      'type': 'object',
      'properties': {
        'headline': {'type': 'string'},
        'summary': {'type': 'string'},
        'focus': {'type': 'string'},
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'task_id': {
                'type': ['string', 'null'],
              },
              'title': {'type': 'string'},
              'start_time': {'type': 'string'},
              'end_time': {'type': 'string'},
              'kind': {
                'type': 'string',
                'enum': [
                  'fixed',
                  'focus',
                  'flexible',
                  'break',
                ],
              },
              'reason': {'type': 'string'},
            },
            'required': [
              'task_id',
              'title',
              'start_time',
              'end_time',
              'kind',
              'reason',
            ],
            'additionalProperties': false,
          },
        },
        'carry_over': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': [
        'headline',
        'summary',
        'focus',
        'items',
        'carry_over',
      ],
      'additionalProperties': false,
    };

    final model = FirebaseAI.googleAI().generativeModel(
      model: _model,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseJsonSchema: Map<String, Object?>.from(schema),
      ),
    );

    final response = await model.generateContent(
      [Content.text(prompt)],
    );

    final jsonText = response.text;

    if (jsonText == null || jsonText.trim().isEmpty) {
      throw Exception('Gemini returned an empty plan.');
    }

    final structured = jsonDecode(
      _removeCodeFences(jsonText),
    );

    if (structured is! Map) {
      throw Exception('Gemini returned an invalid plan.');
    }

    return DayPlan.fromJson(
      Map<String, dynamic>.from(structured),
    );
  }

  String _hhmm(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<List<AiAction>> _sendToGemini({
    required String text,
    Uint8List? imageBytes,
    String? mimeType,
  }) async {
    final now = DateTime.now();

    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final systemPrompt = '''
You are the intelligence engine for BRYLOQ,
a personal action assistant.

Today's date is:

$today

Your job is to extract structured actions from
natural language, images, PDFs, and supported files.

ACTION TYPES:

task
reminder
appointment
event
shopping
routine
note
follow_up

GENERAL RULES:

1. Split separate intentions into separate actions.

2. Keep titles specific and actionable.

Never use generic titles such as:

"Task"
"Routine"
"Reminder"
"Appointment"

Instead preserve the actual activity.

GOOD:
"Go jogging"
"Mark 30 scripts"
"Pay rent"
"Call Dad"

BAD:
"Routine"
"Task"

3. Resolve relative dates using today's date.

Examples:

tomorrow
Friday
next Friday
next week
tonight

4. Dates use:

YYYY-MM-DD

5. Times use:

HH:mm

24-hour format.

6. Never invent an exact time.

7. Priority values:

low
normal
high

Default:
normal

8. If information is absent, use null.

RECURRENCE:

recurrence_type must be one of:

none
daily
weekly
monthly
yearly

Examples:

"Take vitamins every day"

recurring = true
recurrence_type = daily
recurrence_interval = 1

"Gym every Monday Wednesday and Friday"

recurring = true
recurrence_type = weekly
recurrence_interval = 1
recurrence_weekdays =
["Monday", "Wednesday", "Friday"]

"Pay rent on the first of every month"

recurrence_type = monthly
recurrence_day_of_month = 1

For non-recurring actions:

recurring = false
recurrence_type = none
recurrence_interval = 1
recurrence_weekdays = []
recurrence_day_of_month = null

REMINDERS:

Keep the actual event/task time separate from
the reminder time.

Example:

"Dentist at 15:00.
Remind me at 13:00."

time = 15:00
reminder = 13:00

IMAGES AND FILES:

When analysing images or files:

- read the supplied information carefully
- understand the context
- extract actions rather than merely describing or summarizing
- preserve important names, dates, amounts and places
- do not hallucinate missing information
- if no actionable item exists but useful information should be remembered,
  return a note
''';

    final schema = {
      'type': 'object',
      'properties': {
        'actions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
              },
              'type': {
                'type': 'string',
                'enum': [
                  'task',
                  'reminder',
                  'appointment',
                  'event',
                  'shopping',
                  'routine',
                  'note',
                  'follow_up',
                ],
              },
              'date': {
                'type': [
                  'string',
                  'null',
                ],
              },
              'time': {
                'type': [
                  'string',
                  'null',
                ],
              },
              'priority': {
                'type': 'string',
                'enum': [
                  'low',
                  'normal',
                  'high',
                ],
              },
              'recurring': {
                'type': 'boolean',
              },
              'recurrence': {
                'type': [
                  'string',
                  'null',
                ],
              },
              'recurrence_type': {
                'type': 'string',
                'enum': [
                  'none',
                  'daily',
                  'weekly',
                  'monthly',
                  'yearly',
                ],
              },
              'recurrence_interval': {
                'type': 'integer',
                'minimum': 1,
              },
              'recurrence_weekdays': {
                'type': 'array',
                'items': {
                  'type': 'string',
                },
              },
              'recurrence_day_of_month': {
                'type': [
                  'integer',
                  'null',
                ],
              },
              'reminder': {
                'type': [
                  'string',
                  'null',
                ],
              },
              'notes': {
                'type': [
                  'string',
                  'null',
                ],
              },
            },
            'required': [
              'title',
              'type',
              'date',
              'time',
              'priority',
              'recurring',
              'recurrence',
              'recurrence_type',
              'recurrence_interval',
              'recurrence_weekdays',
              'recurrence_day_of_month',
              'reminder',
              'notes',
            ],
            'additionalProperties': false,
          },
        },
      },
      'required': [
        'actions',
      ],
      'additionalProperties': false,
    };

    final model = FirebaseAI.googleAI().generativeModel(
      model: _model,
      systemInstruction: Content.system(systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseJsonSchema: Map<String, Object?>.from(schema),
      ),
    );

    final Content requestContent;

    if (imageBytes != null && imageBytes.isNotEmpty) {
      requestContent = Content.multi(
        [
          TextPart(text),
          InlineDataPart(
            mimeType ?? 'image/jpeg',
            imageBytes,
          ),
        ],
      );
    } else {
      requestContent = Content.text(text);
    }

    final response = await model.generateContent(
      [requestContent],
    );

    final jsonText = response.text;

    if (jsonText == null || jsonText.trim().isEmpty) {
      throw Exception(
        'Gemini returned empty output.',
      );
    }

    final structured =
        jsonDecode(
      _removeCodeFences(
        jsonText,
      ),
    );

    if (structured is! Map) {
      return [];
    }

    final rawActions =
        structured['actions'];

    if (rawActions is! List) {
      return [];
    }

    return rawActions
        .whereType<Map>()
        .map(
          (item) =>
              AiAction.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .toList();
  }

  String _removeCodeFences(
    String value,
  ) {
    var result =
        value.trim();

    if (result.startsWith(
      '```json',
    )) {
      result =
          result.substring(7);
    } else if (result
        .startsWith('```')) {
      result =
          result.substring(3);
    }

    if (result.endsWith(
      '```',
    )) {
      result =
          result.substring(
        0,
        result.length - 3,
      );
    }

    return result.trim();
  }
}
