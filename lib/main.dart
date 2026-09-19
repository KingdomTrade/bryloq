import 'package:file_picker/file_picker.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import 'models/ai_action.dart';
import 'models/day_plan.dart';
import 'models/google_calendar_event.dart';
import 'models/saydo_task.dart';

import 'screens/search_history_screen.dart';

import 'services/ai_service.dart';
import 'services/android_share_service.dart';
import 'services/notification_service.dart';
import 'services/recurrence_service.dart';
import 'services/day_plan_database_service.dart';
import 'services/google_calendar_service.dart';
import 'services/task_database_service.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  await FirebaseAppCheck.instance.activate(
  providerAndroid: kReleaseMode
      ? const AndroidPlayIntegrityProvider()
      : const AndroidDebugProvider(),
  providerApple: kReleaseMode
      ? const AppleAppAttestWithDeviceCheckFallbackProvider()
      : const AppleDebugProvider(),
);

  await Hive.initFlutter();

  await NotificationService.instance.initialise();

  runApp(const SayDoApp());
}

class SayDoApp extends StatelessWidget {
  const SayDoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF6D3DF5);
    const deepPurple = Color(0xFF5427C8);
    const lavender = Color(0xFFF2ECFF);
    const background = Color(0xFFFAF8FF);
    const ink = Color(0xFF211B2D);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BRYLOQ',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          surface: background,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF4B4260),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: Color(0xFFE9DEFF),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: deepPurple,
            side: const BorderSide(
              color: Color(0xFFDCCFFF),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: deepPurple,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primary,
          linearTrackColor: lavender,
          circularTrackColor: lavender,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2B1E47),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F3FD),
          labelStyle: const TextStyle(
            color: Color(0xFF6F6680),
          ),
          prefixIconColor: primary,
          suffixIconColor: primary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xFFE8E1F1),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: primary,
              width: 1.6,
            ),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const String _privacyPolicyUrl =
      'https://kingdomtrade.github.io/bryloq-privacy/';

  late stt.SpeechToText _speech;

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isProcessingAi = false;
  bool _databaseReady = false;
  int _selectedNavIndex = 0;

  String _spokenText = '';

  final AiService _aiService = AiService();

  final TaskDatabaseService _taskDatabase =
      TaskDatabaseService();

  final DayPlanDatabaseService _dayPlanDatabase =
      DayPlanDatabaseService();

  final RecurrenceService _recurrenceService =
      RecurrenceService();

  final ImagePicker _imagePicker = ImagePicker();

  final AndroidShareService _shareService =
      AndroidShareService();

  final GoogleCalendarService _calendarService =
      GoogleCalendarService();

  bool _calendarConnected = false;
  bool _calendarSyncing = false;
  List<GoogleCalendarEvent> _calendarEventsToday = [];

  List<AiAction> _aiActions = [];
  final Map<int, String> _aiPriorityOverrides = <int, String>{};
  List<SayDoTask> _savedTasks = [];
  DayPlan? _todayPlan;
  BryloqNotificationAction? _pendingNotificationAction;
  bool _exactReminderPromptShown = false;
  bool _fullScreenAlertPromptShown = false;
  String? _activeHighPriorityAlarmTaskId;

  String? _inputSourceLabel;

  final TextEditingController _typeController =
      TextEditingController();

  bool _showTypeComposer = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.10,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    NotificationService.instance.setActionHandler(
      _handleNotificationAction,
    );

    _initializeSpeech();
    _initialiseDatabase();
    _requestNotificationPermissions();
    _initialiseGoogleCalendar();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialiseShareIntake();
    });
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      await NotificationService.instance.requestPermissions();
    } catch (e) {
      debugPrint(
        'Notification permission error: $e',
      );
    }
  }

  Future<void> _handleNotificationAction(
    BryloqNotificationAction action,
  ) async {
    if (!mounted) {
      return;
    }

    if (!_databaseReady) {
      _pendingNotificationAction = action;
      return;
    }

    if (action.isMorningBriefing) {
      setState(() {
        _selectedNavIndex = 0;
      });
      return;
    }

    if (!action.isTask || action.taskId == null) {
      return;
    }

    SayDoTask? task;
    for (final candidate in _savedTasks) {
      if (candidate.id == action.taskId) {
        task = candidate;
        break;
      }
    }

    if (task == null) {
      await _loadSavedTasks();

      for (final candidate in _savedTasks) {
        if (candidate.id == action.taskId) {
          task = candidate;
          break;
        }
      }
    }

    if (task == null || !mounted) {
      return;
    }

    if (action.isDueNow &&
        !action.isDone &&
        !action.isSnooze5 &&
        !action.isSnooze15 &&
        _normalisePriority(task.priority) == 'high') {
      await _showHighPriorityAlarm(task);
      return;
    }

    if (action.isDone) {
      if (!task.completed) {
        await _toggleTask(task);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${task.title} marked done.'),
        ),
      );
      return;
    }

    if (action.isSnooze5 || action.isSnooze15) {
      final minutes = action.isSnooze5 ? 5 : 15;

      await NotificationService.instance.snoozeTask(
        task,
        Duration(minutes: minutes),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${task.title} snoozed for $minutes minutes.'),
        ),
      );
      return;
    }

    setState(() {
      _selectedNavIndex = 0;
    });
  }

  Future<void> _showHighPriorityAlarm(
    SayDoTask task,
  ) async {
    if (!mounted || _activeHighPriorityAlarmTaskId == task.id) {
      return;
    }

    _activeHighPriorityAlarmTaskId = task.id;

    final dueTime = task.time?.trim().isNotEmpty == true
        ? task.time!.trim()
        : 'now';

    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (routeContext, animation, secondaryAnimation) {
            return PopScope(
              canPop: false,
              child: Scaffold(
                body: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF25133F),
                        Color(0xFF5B2CC8),
                        Color(0xFF7D55E8),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: const Text(
                                  'BRYLOQ • HIGH PRIORITY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.20),
                                  blurRadius: 30,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.alarm_rounded,
                              color: Colors.white,
                              size: 58,
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'DUE NOW',
                            style: TextStyle(
                              color: Color(0xFFE7DCFF),
                              fontSize: 14,
                              letterSpacing: 2.3,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            task.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.08,
                              letterSpacing: -0.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            dueTime == 'now'
                                ? 'This high-priority task needs your attention.'
                                : 'Scheduled for $dueTime • High priority',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (task.notes?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                task.notes!.trim(),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF4E24B5),
                                padding: const EdgeInsets.symmetric(vertical: 17),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: () async {
                                Navigator.of(routeContext).pop();
                                if (!task.completed) {
                                  await _toggleTask(task);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${task.title} marked done.'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.check_circle_rounded),
                              label: const Text(
                                'DONE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.55),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(routeContext).pop();
                                    await NotificationService.instance.snoozeTask(
                                      task,
                                      const Duration(minutes: 5),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${task.title} snoozed for 5 minutes.',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'SNOOZE 5 MIN',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.55),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(routeContext).pop();
                                    await NotificationService.instance.snoozeTask(
                                      task,
                                      const Duration(minutes: 15),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${task.title} snoozed for 15 minutes.',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'SNOOZE 15 MIN',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'High-priority alarms are designed to be acted on, '
                            'completed or snoozed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
        ),
      );
    } finally {
      _activeHighPriorityAlarmTaskId = null;
    }
  }

  Future<void> _processPendingNotificationAction() async {
    final action = _pendingNotificationAction;
    if (action == null) {
      return;
    }

    _pendingNotificationAction = null;
    await _handleNotificationAction(action);
  }

  Future<void> _requestNotificationPermissionFromSettings() async {
    final notificationsGranted =
        await NotificationService.instance.requestPermissions();

    if (!mounted) {
      return;
    }

    if (!notificationsGranted) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Turn on BRYLOQ notifications'),
            content: const Text(
              'Notifications are currently blocked for BRYLOQ. '
              'Open your phone settings and allow notifications so reminders can appear.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Open settings'),
              ),
            ],
          );
        },
      );

      if (openSettings == true) {
        await NotificationService.instance.openNotificationSettings();
      }
      return;
    }

    final exactTimingGranted =
        await NotificationService.instance.requestExactReminderPermission();

    final fullScreenGranted =
        await NotificationService.instance.requestFullScreenIntentPermission();

    if (exactTimingGranted) {
      try {
        await NotificationService.instance
            .refreshTaskReminders(_savedTasks);
        await NotificationService.instance
            .refreshMorningBriefings(_savedTasks);
      } catch (e) {
        debugPrint('Reminder refresh after permission error: $e');
      }
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exactTimingGranted && fullScreenGranted
              ? 'BRYLOQ notifications, precise timing and high-priority full-screen alerts are enabled.'
              : exactTimingGranted
                  ? 'Precise reminders are enabled. Full-screen high-priority alerts are optional and may need to be allowed in Android settings.'
                  : 'Notifications are enabled, but precise reminder timing is off. '
                      'Allow Alarms & reminders for exact 30, 15, 5 minute and due-time alerts.',
        ),
      ),
    );
  }

  Future<void> _maybePromptForHighPriorityFullScreenAlerts() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _fullScreenAlertPromptShown ||
        !mounted) {
      return;
    }

    _fullScreenAlertPromptShown = true;

    final enable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.alarm_rounded,
            color: Color(0xFF6D3DF5),
            size: 36,
          ),
          title: const Text('High-priority full-screen alerts'),
          content: const Text(
            'For tasks you mark High, BRYLOQ can wake the screen and show a '
            'full-screen alarm when the task is due. Android requires separate '
            'permission for this. If you leave it off, you will still receive '
            'the normal high-priority notification.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Allow full-screen alerts'),
            ),
          ],
        );
      },
    );

    if (enable != true) {
      return;
    }

    final granted =
        await NotificationService.instance.requestFullScreenIntentPermission();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'High-priority full-screen alerts are enabled.'
              : 'Full-screen alerts are not enabled. BRYLOQ will use a maximum-importance heads-up alarm instead.',
        ),
      ),
    );
  }

  Future<void> _maybePromptForPreciseReminders() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _exactReminderPromptShown) {
      return;
    }

    final exactAllowed =
        await NotificationService.instance.canScheduleExactReminders();

    if (exactAllowed || !mounted) {
      return;
    }

    _exactReminderPromptShown = true;

    final enable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Keep BRYLOQ reminders on time'),
          content: const Text(
            'Android needs Alarms & reminders access so BRYLOQ can alert you '
            'at the exact 30, 15, 5 minute and due-time points even when '
            'BRYLOQ is not open.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enable precise reminders'),
            ),
          ],
        );
      },
    );

    if (enable != true) {
      return;
    }

    final granted =
        await NotificationService.instance.requestExactReminderPermission();

    if (granted) {
      await NotificationService.instance.refreshTaskReminders(_savedTasks);
      await NotificationService.instance.refreshMorningBriefings(_savedTasks);
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Precise BRYLOQ reminders are enabled.'
              : 'Precise reminders are still off. You can enable them later '
                  'from BRYLOQ → Notification permission.',
        ),
      ),
    );
  }

  Future<void> _initialiseGoogleCalendar() async {
    try {
      await _calendarService.initialise();

      if (!mounted) {
        return;
      }

      setState(() {
        _calendarConnected = _calendarService.isConnected;
      });

      if (_calendarService.isConnected) {
        await _syncGoogleCalendar(silent: true);
      }
    } catch (e) {
      debugPrint('Google Calendar startup error: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _calendarConnected = false;
      });
    }
  }

  Future<void> _connectGoogleCalendar() async {
    if (_calendarSyncing) {
      return;
    }

    setState(() {
      _calendarSyncing = true;
    });

    try {
      final account = await _calendarService.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _calendarConnected = true;
      });

      await _syncGoogleCalendar(silent: true);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Google Calendar connected • ${account.email}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Calendar connection error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _calendarSyncing = false;
        });
      }
    }
  }

  Future<void> _syncGoogleCalendar({
    bool silent = false,
  }) async {
    if (!_calendarService.isConnected) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect Google Calendar first.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _calendarSyncing = true;
      });
    }

    try {
      final events = await _calendarService.eventsForDay(
        DateTime.now(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _calendarConnected = true;
        _calendarEventsToday = events;
      });

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${events.length} ${events.length == 1 ? 'event' : 'events'} synced from Google Calendar.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calendar sync error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarSyncing = false;
        });
      }
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    try {
      await _calendarService.disconnect();

      if (!mounted) {
        return;
      }

      setState(() {
        _calendarConnected = false;
        _calendarEventsToday = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Calendar disconnected.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calendar disconnect error: $e'),
        ),
      );
    }
  }

  Future<void> _addTaskToGoogleCalendar(
    SayDoTask task,
  ) async {
    if (!_calendarService.isConnected) {
      await _connectGoogleCalendar();

      if (!_calendarService.isConnected) {
        return;
      }
    }

    try {
      final event = await _calendarService.createEventForTask(task);
      await _syncGoogleCalendar(silent: true);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${event.title} added to Google Calendar.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calendar event error: $e'),
        ),
      );
    }
  }

  Future<void> _initializeSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(
          'Speech status: $status',
        );

        if (status == 'done' ||
            status == 'notListening') {
          if (!mounted) {
            return;
          }

          setState(() {
            _isListening = false;
          });

          _pulseController.stop();
          _pulseController.reset();
        }
      },
      onError: (error) {
        debugPrint(
          'Speech error: ${error.errorMsg}',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _isListening = false;
        });

        _pulseController.stop();
        _pulseController.reset();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Speech error: ${error.errorMsg}',
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _speechAvailable = available;
    });
  }

  Future<void> _initialiseDatabase() async {
    try {
      await _taskDatabase.initialise();
      await _dayPlanDatabase.initialise();
      await _loadSavedTasks();

      // Rebuild Android alarms from the saved task database. This makes
      // reminders independent of the Flutter UI process and also upgrades
      // schedules after exact-alarm access or an app update.
      try {
        await NotificationService.instance
            .refreshTaskReminders(_savedTasks);
      } catch (e) {
        debugPrint('Startup task reminder refresh error: $e');
      }

      await _loadTodayPlan();

      if (!mounted) {
        return;
      }

      setState(() {
        _databaseReady = true;
      });

      await _processPendingNotificationAction();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _databaseReady = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Database error: $e',
          ),
        ),
      );
    }
  }

  Future<void> _loadSavedTasks() async {
    final tasks =
        await _taskDatabase.getTasks();

    tasks.sort(
      (a, b) {
        final aDate =
            '${a.date ?? '9999-99-99'} ${a.time ?? '99:99'}';

        final bDate =
            '${b.date ?? '9999-99-99'} ${b.time ?? '99:99'}';

        return aDate.compareTo(
          bDate,
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _savedTasks = tasks;
    });

    try {
      await NotificationService.instance
          .maybeShowMorningBriefingOnAppOpen(tasks);
      await NotificationService.instance
          .refreshMorningBriefings(tasks);
    } catch (e) {
      debugPrint('Morning briefing refresh error: $e');
    }
  }

  String _todayKey() {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _greetingText() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning 👋';
    }

    if (hour < 17) {
      return 'Good afternoon 👋';
    }

    return 'Good evening 👋';
  }

  Future<void> _loadTodayPlan() async {
    final plan = _dayPlanDatabase.getPlan(
      _todayKey(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _todayPlan = plan;
    });
  }

  Future<void> _initialiseShareIntake() async {
    try {
      await _shareService.initialise();

      _shareService.onSharedContent = (shared) async {
        await _handleSharedContent(shared);
      };

      final initial = await _shareService.getInitialShare();

      if (initial != null) {
        await _handleSharedContent(initial);
      }
    } catch (e) {
      debugPrint('Share intake setup error: $e');
    }
  }

  Future<void> _handleSharedContent(
    SharedContent shared,
  ) async {
    if (!mounted) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (shared.kind == SharedContentKind.text) {
      final text = shared.text?.trim() ?? '';

      if (text.isEmpty) {
        return;
      }

      setState(() {
        _selectedNavIndex = 0;
        _showTypeComposer = false;
        _spokenText = text;
        _aiActions = [];
        _aiPriorityOverrides.clear();
        _inputSourceLabel = null;
      });

      await _organiseWithAi();
      return;
    }

    final uri = shared.uri?.trim() ?? '';

    if (uri.isEmpty) {
      return;
    }

    final fileName =
        shared.fileName?.trim().isNotEmpty == true
            ? shared.fileName!.trim()
            : 'shared-file';

    final mimeType =
        shared.mimeType?.trim().isNotEmpty == true
            ? shared.mimeType!.trim()
            : _mimeTypeFromName(fileName);

    setState(() {
      _selectedNavIndex = 0;
      _showTypeComposer = false;
      _spokenText = '';
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _isProcessingAi = true;
      _inputSourceLabel = 'Reading shared $fileName...';
    });

    try {
      final bytes = await _shareService.readSharedBytes(uri);

      final List<AiAction> actions;

      if (mimeType.startsWith('image/')) {
        actions = await _aiService.organiseImage(
          imageBytes: bytes,
          mimeType: mimeType,
        );
      } else {
        actions = await _aiService.organiseFile(
          fileBytes: bytes,
          mimeType: mimeType,
          fileName: fileName,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _aiActions = actions;
        _aiPriorityOverrides
          ..clear()
          ..addEntries(
            actions.asMap().entries.map(
              (entry) => MapEntry(
                entry.key,
                _normalisePriority(entry.value.priority),
              ),
            ),
          );
      });

      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BRYLOQ could not find an action in the shared item.',
            ),
          ),
        );
      } else {
        await _choosePrioritiesForActions(actions);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not read shared item: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAi = false;
          _inputSourceLabel = null;
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Speech recognition is not available on this device.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _spokenText = '';
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _inputSourceLabel = null;
      _isListening = true;
    });

    _pulseController.repeat(
      reverse: true,
    );

    await _speech.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }

        setState(() {
          _spokenText =
              result.recognizedWords;
        });
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
    });

    _pulseController.stop();
    _pulseController.reset();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  void _clearText() {
    _typeController.clear();

    setState(() {
      _spokenText = '';
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _inputSourceLabel = null;
      _showTypeComposer = false;
    });
  }

  void _toggleTypeComposer() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _showTypeComposer = !_showTypeComposer;

      if (_showTypeComposer) {
        _aiActions = [];
        _aiPriorityOverrides.clear();
        _inputSourceLabel = null;
      }
    });
  }

  Future<void> _submitTypedText() async {
    final typedText = _typeController.text.trim();

    if (typedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Type something for BRYLOQ first.',
          ),
        ),
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _typeController.clear();

    setState(() {
      _spokenText = typedText;
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _inputSourceLabel = null;
      _showTypeComposer = false;
    });

    await _organiseWithAi();
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2200,
      );

      if (image == null) {
        return;
      }

      await _handlePickedImage(
        image,
        'Reading your photo...',
      );
    } catch (e) {
      _showInputError(
        'Camera',
        e,
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2400,
      );

      if (image == null) {
        return;
      }

      await _handlePickedImage(
        image,
        'Reading your image...',
      );
    } catch (e) {
      _showInputError(
        'Image',
        e,
      );
    }
  }

  Future<void> _handlePickedImage(
    XFile image,
    String progressLabel,
  ) async {
    final bytes = await image.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception(
        'The selected image is empty.',
      );
    }

    final mimeType =
        image.mimeType ??
        _mimeTypeFromName(
          image.name,
        );

    await _analyseImageBytes(
      bytes: bytes,
      mimeType: mimeType,
      progressLabel: progressLabel,
    );
  }

  Future<void> _analyseImageBytes({
    required Uint8List bytes,
    required String mimeType,
    required String progressLabel,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _spokenText = '';
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _isProcessingAi = true;
      _inputSourceLabel = progressLabel;
    });

    try {
      final actions =
          await _aiService.organiseImage(
        imageBytes: bytes,
        mimeType: mimeType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _aiActions = actions;
        _aiPriorityOverrides
          ..clear()
          ..addEntries(
            actions.asMap().entries.map(
              (entry) => MapEntry(
                entry.key,
                _normalisePriority(entry.value.priority),
              ),
            ),
          );
      });

      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BRYLOQ could not find an action in that image.',
            ),
          ),
        );
      } else {
        await _choosePrioritiesForActions(actions);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not analyse image: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAi = false;
          _inputSourceLabel = null;
        });
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'txt',
          'md',
          'csv',
          'json',
          'jpg',
          'jpeg',
          'png',
          'webp',
          'heic',
          'heif',
        ],
      );

      if (file == null) {
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception(
          'BRYLOQ could not read that file.',
        );
      }

      final mimeType =
          _mimeTypeFromFile(
        file.name,
        file.extension,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _spokenText = '';
        _aiActions = [];
        _aiPriorityOverrides.clear();
        _isProcessingAi = true;
        _inputSourceLabel =
            'Reading ${file.name}...';
      });

      final actions =
          await _aiService.organiseFile(
        fileBytes: bytes,
        mimeType: mimeType,
        fileName: file.name,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _aiActions = actions;
        _aiPriorityOverrides
          ..clear()
          ..addEntries(
            actions.asMap().entries.map(
              (entry) => MapEntry(
                entry.key,
                _normalisePriority(entry.value.priority),
              ),
            ),
          );
      });

      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BRYLOQ could not find an action in that file.',
            ),
          ),
        );
      } else {
        await _choosePrioritiesForActions(actions);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAi = false;
          _inputSourceLabel = null;
        });
      }
    }
  }

  String _mimeTypeFromName(
    String name,
  ) {
    return _mimeTypeFromFile(
      name,
      name.contains('.')
          ? name.split('.').last
          : null,
    );
  }

  String _mimeTypeFromFile(
    String name,
    String? extension,
  ) {
    final ext =
        (extension ??
                (name.contains('.')
                    ? name.split('.').last
                    : ''))
            .toLowerCase();

    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  void _showInputError(
    String source,
    Object error,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$source error: $error',
        ),
      ),
    );
  }

  Future<void> _organiseWithAi() async {
    if (_isListening) {
      await _stopListening();
    }

    final input = _spokenText.trim();

    if (input.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Say or type something first.',
          ),
        ),
      );

      return;
    }

    _typeController.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _spokenText = '';
      _isProcessingAi = true;
      _aiActions = [];
      _aiPriorityOverrides.clear();
      _inputSourceLabel = null;
      _showTypeComposer = false;
    });

    try {
      final actions = await _aiService.organiseText(input);

      if (!mounted) {
        return;
      }

      setState(() {
        _aiActions = actions;
        _aiPriorityOverrides
          ..clear()
          ..addEntries(
            actions.asMap().entries.map(
              (entry) => MapEntry(
                entry.key,
                _normalisePriority(entry.value.priority),
              ),
            ),
          );
      });

      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BRYLOQ could not find any actions in that message.',
            ),
          ),
        );
        return;
      }

      await _choosePrioritiesForActions(actions);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAi = false;
        });
      }
    }
  }

  String _normalisePriority(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'high':
        return 'high';
      case 'low':
        return 'low';
      case 'medium':
      case 'normal':
      default:
        return 'normal';
    }
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

  int _priorityRank(String value) {
    switch (_normalisePriority(value)) {
      case 'high':
        return 0;
      case 'normal':
        return 1;
      case 'low':
      default:
        return 2;
    }
  }

  Future<void> _choosePrioritiesForActions(
    List<AiAction> actions,
  ) async {
    if (!mounted || actions.isEmpty) {
      return;
    }

    final initial = <int, String>{
      for (int i = 0; i < actions.length; i++)
        i: _aiPriorityOverrides[i] ??
            _normalisePriority(actions[i].priority),
    };

    final selected = await showModalBottomSheet<Map<int, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final choices = Map<int, String>.from(initial);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFAF8FF),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5D2DC),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Choose priority',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      actions.length == 1
                          ? 'How important is this task?'
                          : 'Set the priority for each action before adding them to BRYLOQ.',
                      style: const TextStyle(
                        color: Color(0xFF77747F),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (int i = 0; i < actions.length; i++) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFE8E1F1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              actions[i].title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final priority in const [
                                  'high',
                                  'normal',
                                  'low',
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      _priorityLabel(priority),
                                    ),
                                    selected: choices[i] == priority,
                                    onSelected: (_) {
                                      setSheetState(() {
                                        choices[i] = priority;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            sheetContext,
                            Map<int, String>.from(choices),
                          );
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 13),
                          child: Text('Continue'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _aiPriorityOverrides
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _saveAiActions() async {
    if (_aiActions.isEmpty) {
      return;
    }

    try {
      final baseId =
          DateTime.now()
              .microsecondsSinceEpoch;

      int scheduledCount = 0;
      bool hasHighTimedTask = false;

      for (int i = 0;
          i < _aiActions.length;
          i++) {
        final action =
            _aiActions[i];

        final task = SayDoTask(
          id: '${baseId}_$i',
          title: action.title,
          type: action.type,
          date: action.date,
          time: action.time,
          priority: _aiPriorityOverrides[i] ??
              _normalisePriority(action.priority),
          recurring: action.recurring,
          recurrence: action.recurrence,
          recurrenceType: action.recurrenceType,
          recurrenceInterval: action.recurrenceInterval,
          recurrenceWeekdays: action.recurrenceWeekdays,
          recurrenceDayOfMonth: action.recurrenceDayOfMonth,
          reminder: action.reminder,
          notes: action.notes,
          completed: false,
          createdAt: DateTime.now(),
        );

        await _taskDatabase.saveTask(
          task,
        );

        if (_normalisePriority(task.priority) == 'high' &&
            task.date?.trim().isNotEmpty == true &&
            task.time?.trim().isNotEmpty == true) {
          hasHighTimedTask = true;
        }

        try {
          final reminderScheduled =
              await NotificationService.instance.scheduleTaskReminder(
            task,
          );

          if (reminderScheduled) {
            scheduledCount++;
          }
        } catch (e) {
          debugPrint(
            'Reminder scheduling error for ${task.title}: $e',
          );
        }
      }

      await _loadSavedTasks();

      if (!mounted) {
        return;
      }

      final taskCount =
          _aiActions.length;

      setState(() {
        _aiActions = [];
        _aiPriorityOverrides.clear();
        _spokenText = '';
        _inputSourceLabel = null;
      });

      String message =
          '$taskCount ${taskCount == 1 ? 'action' : 'actions'} added to BRYLOQ';

      if (scheduledCount > 0) {
        message +=
            ' • $scheduledCount ${scheduledCount == 1 ? 'reminder sequence' : 'reminder sequences'} scheduled';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );

      if (scheduledCount > 0) {
        await _maybePromptForPreciseReminders();
      }

      if (hasHighTimedTask) {
        await _maybePromptForHighPriorityFullScreenAlerts();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save tasks: $e',
          ),
        ),
      );
    }
  }

  Future<void> _toggleTask(
    SayDoTask task,
  ) async {
    if (task.recurring && !task.completed) {
      final next = _recurrenceService.nextOccurrence(task);

      if (next != null) {
        final updated = SayDoTask(
          id: task.id,
          title: task.title,
          type: task.type,
          date: _recurrenceService.formatDate(next),
          time: task.time,
          priority: task.priority,
          recurring: true,
          recurrence: task.recurrence,
          recurrenceType: task.recurrenceType,
          recurrenceInterval: task.recurrenceInterval,
          recurrenceWeekdays: task.recurrenceWeekdays,
          recurrenceDayOfMonth: task.recurrenceDayOfMonth,
          reminder: task.reminder,
          notes: task.notes,
          completed: false,
          createdAt: task.createdAt,
        );

        await _taskDatabase.saveTask(updated);

        try {
          await NotificationService.instance
              .cancelTaskReminder(task.id);
          await NotificationService.instance
              .scheduleTaskReminder(updated);
        } catch (e) {
          debugPrint(
            'Recurring reminder refresh error for ${task.title}: $e',
          );
        }

        await _loadSavedTasks();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Completed ✓ Next: ${updated.date}',
            ),
          ),
        );

        return;
      }
    }

    await _taskDatabase.toggleComplete(task);

    if (!task.completed) {
      await NotificationService.instance
          .cancelTaskReminder(task.id);
    }

    await _loadSavedTasks();
  }

  SayDoTask _taskWithChanges(
    SayDoTask task, {
    String? title,
    String? date,
    bool clearDate = false,
    String? time,
    bool clearTime = false,
    String? priority,
    String? notes,
    bool clearNotes = false,
    bool? completed,
  }) {
    return SayDoTask(
      id: task.id,
      title: title ?? task.title,
      type: task.type,
      date: clearDate ? null : (date ?? task.date),
      time: clearTime ? null : (time ?? task.time),
      priority: priority ?? task.priority,
      recurring: task.recurring,
      recurrence: task.recurrence,
      recurrenceType: task.recurrenceType,
      recurrenceInterval: task.recurrenceInterval,
      recurrenceWeekdays: task.recurrenceWeekdays,
      recurrenceDayOfMonth: task.recurrenceDayOfMonth,
      reminder: task.reminder,
      notes: clearNotes ? null : (notes ?? task.notes),
      completed: completed ?? task.completed,
      createdAt: task.createdAt,
    );
  }

  Future<void> _saveEditedTask(
    SayDoTask updated,
  ) async {
    await _taskDatabase.saveTask(updated);

    try {
      await NotificationService.instance.cancelTaskReminder(
        updated.id,
      );

      if (!updated.completed) {
        await NotificationService.instance.scheduleTaskReminder(
          updated,
        );
      }
    } catch (e) {
      debugPrint(
        'Reminder refresh error for ${updated.title}: $e',
      );
    }

    await _loadSavedTasks();
  }

  Future<void> _editTask(
    SayDoTask task,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final updated = await showModalBottomSheet<SayDoTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskEditSheet(
        task: task,
      ),
    );

    if (updated == null) {
      return;
    }

    await _saveEditedTask(updated);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Task updated.'),
      ),
    );
  }

  Future<void> _moveTaskToToday(
    SayDoTask task,
  ) async {
    final updated = _taskWithChanges(
      task,
      date: _todayKey(),
      completed: false,
    );

    await _saveEditedTask(updated);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${task.title} moved to Today.'),
      ),
    );
  }

  Future<void> _scheduleTask(
    SayDoTask task,
  ) async {
    DateTime initialDate = DateTime.now();

    if (task.date != null && task.date!.trim().isNotEmpty) {
      initialDate = DateTime.tryParse(task.date!) ?? initialDate;
    }

    final chosenDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365),
      ),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
    );

    if (chosenDate == null || !mounted) {
      return;
    }

    TimeOfDay? initialTime;
    if (task.time != null && task.time!.contains(':')) {
      final parts = task.time!.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          initialTime = TimeOfDay(
            hour: hour,
            minute: minute,
          );
        }
      }
    }

    final chosenTime = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      helpText: 'Optional time — Cancel to keep date only',
    );

    final formattedDate =
        '${chosenDate.year.toString().padLeft(4, '0')}-'
        '${chosenDate.month.toString().padLeft(2, '0')}-'
        '${chosenDate.day.toString().padLeft(2, '0')}';

    final formattedTime = chosenTime == null
        ? task.time
        : '${chosenTime.hour.toString().padLeft(2, '0')}:'
            '${chosenTime.minute.toString().padLeft(2, '0')}';

    final updated = _taskWithChanges(
      task,
      date: formattedDate,
      time: formattedTime,
      completed: false,
    );

    await _saveEditedTask(updated);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${task.title} scheduled.'),
      ),
    );
  }

  Future<void> _deleteTask(
    SayDoTask task,
  ) async {
    await NotificationService.instance
        .cancelTaskReminder(
      task.id,
    );

    await _taskDatabase.deleteTask(
      task.id,
    );

    await _loadSavedTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${task.title} deleted',
        ),
      ),
    );
  }

  Future<void> _openPlanMyDay() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_calendarService.isConnected) {
      await _syncGoogleCalendar(silent: true);
    }

    final appliedCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DayPlanSheet(
          tasks: List<SayDoTask>.from(_savedTasks),
          calendarEvents: List<GoogleCalendarEvent>.from(
            _calendarEventsToday,
          ),
          aiService: _aiService,
          onApplyPlan: _applyDayPlan,
        );
      },
    );

    if (!mounted || appliedCount == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appliedCount == 0
              ? 'Plan saved. No task times needed changing.'
              : 'Plan applied • $appliedCount ${appliedCount == 1 ? 'task' : 'tasks'} scheduled for today.',
        ),
      ),
    );
  }

  Future<int> _applyDayPlan(
    DayPlan plan,
  ) async {
    final today = _todayKey();
    int appliedCount = 0;

    for (final item in plan.items) {
      final taskId = item.taskId;

      if (taskId == null || taskId.trim().isEmpty) {
        continue;
      }

      SayDoTask? original;

      for (final task in _savedTasks) {
        if (task.id == taskId) {
          original = task;
          break;
        }
      }

      if (original == null) {
        continue;
      }

      final updated = SayDoTask(
        id: original.id,
        title: original.title,
        type: original.type,
        date: today,
        time: item.startTime,
        priority: original.priority,
        recurring: original.recurring,
        recurrence: original.recurrence,
        recurrenceType: original.recurrenceType,
        recurrenceInterval: original.recurrenceInterval,
        recurrenceWeekdays: original.recurrenceWeekdays,
        recurrenceDayOfMonth: original.recurrenceDayOfMonth,
        reminder: original.reminder,
        notes: original.notes,
        completed: original.completed,
        createdAt: original.createdAt,
      );

      await _taskDatabase.saveTask(
        updated,
      );

      try {
        await NotificationService.instance
            .cancelTaskReminder(
          updated.id,
        );

        await NotificationService.instance
            .scheduleTaskReminder(
          updated,
        );
      } catch (e) {
        debugPrint(
          'Plan reminder update error for ${updated.title}: $e',
        );
      }

      appliedCount++;
    }

    await _dayPlanDatabase.savePlan(
      today,
      plan,
    );

    await _loadSavedTasks();
    await _loadTodayPlan();

    return appliedCount;
  }

  Future<void> _sendTestNotification() async {
    try {
      await NotificationService.instance
          .showTestNotification();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test notification sent.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Notification error: $e',
          ),
        ),
      );
    }
  }

  Future<void> _sendMorningBriefingNow() async {
    try {
      await NotificationService.instance
          .showMorningBriefingNow(_savedTasks);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Morning briefing sent.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Briefing error: $e'),
        ),
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the BRYLOQ Privacy Policy.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the Privacy Policy: $e',
          ),
        ),
      );
    }
  }

  Future<void> _showAboutBryloq() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFBF9FF),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            10,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFE4D8FA),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D3DF5)
                          .withValues(alpha: 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/bryloq_final_logo_256.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'BRYLOQ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF32146F),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Speak it once. Consider it handled.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6D3DF5),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'BRYLOQ is a voice-first productivity assistant that turns '
                'thoughts into organised tasks, reminders and daily plans.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.45,
                  color: Color(0xFF77747F),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EDFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFF6D3DF5),
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4A3D5B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _openPrivacyPolicy();
              },
              icon: const Icon(
                Icons.privacy_tip_outlined,
                size: 18,
              ),
              label: const Text('Privacy Policy'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    NotificationService.instance.setActionHandler(null);
    _speech.stop();
    _shareService.dispose();
    _typeController.dispose();
    _pulseController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFBF9FF),
                    Color(0xFFF8F4FF),
                    Color(0xFFFAF8FF),
                  ],
                  stops: [0.0, 0.46, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE3D6FF).withValues(alpha: 0.34),
              ),
            ),
          ),
          Positioned(
            top: 240,
            left: -120,
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF2EBFF).withValues(alpha: 0.42),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(),
                  if (_selectedNavIndex == 0) ...[
                    const SizedBox(height: 28),
                    _buildHeroIntro(),
                    const SizedBox(height: 34),
                    _buildMicrophone(),
                    const SizedBox(height: 28),
                    if (_spokenText.isNotEmpty) _buildSpeechCard(),
                    if (_spokenText.isNotEmpty) const SizedBox(height: 22),
                    if (_isProcessingAi &&
                        _spokenText.isEmpty &&
                        _inputSourceLabel != null)
                      _buildExternalProcessingCard(),
                    if (_isProcessingAi &&
                        _spokenText.isEmpty &&
                        _inputSourceLabel != null)
                      const SizedBox(height: 22),
                    if (_aiActions.isNotEmpty) _buildAiResults(),
                    if (_aiActions.isNotEmpty) const SizedBox(height: 24),
                    _buildQuickActions(),
                    if (_showTypeComposer) const SizedBox(height: 16),
                    if (_showTypeComposer) _buildTypeComposer(),
                    const SizedBox(height: 34),
                    if (!_databaseReady)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      _buildTodayContent(),
                  ] else ...[
                    const SizedBox(height: 26),
                    if (!_databaseReady)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      _buildInboxContent(),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Color(0xFFF8F3FF),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFE8E1F1),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF302B63).withValues(alpha: 0.10),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              height: 70,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedIndex: _selectedNavIndex,
              onDestinationSelected: (index) async {
                if (index == 2) {
                  await _openPlanMyDay();
                  return;
                }

                if (!mounted) {
                  return;
                }

                setState(() {
                  _selectedNavIndex = index;
                  _showTypeComposer = false;
                });

                FocusManager.instance.primaryFocus?.unfocus();
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today_rounded),
                  label: 'Today',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox_rounded),
                  label: 'Inbox',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Plan',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: const Color(0xFFE4D8FA),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6D3DF5).withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/branding/bryloq_final_logo_256.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BRYLOQ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                  color: Color(0xFF32146F),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34B77C),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _calendarConnected
                          ? 'AI ready • Calendar connected'
                          : 'AI ready • Voice first',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF81788E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _topBarAction(
          tooltip: 'Search & history',
          icon: Icons.search_rounded,
          onPressed: _openSearchHistory,
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE6DDF2),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5C35B5).withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: PopupMenuButton<String>(
            tooltip: 'Settings',
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: (value) async {
              if (value == 'calendar_connect') {
                await _connectGoogleCalendar();
              }
              if (value == 'calendar_sync') {
                await _syncGoogleCalendar();
              }
              if (value == 'calendar_disconnect') {
                await _disconnectGoogleCalendar();
              }
              if (value == 'test_notification') {
                await _sendTestNotification();
              }
              if (value == 'morning_briefing') {
                await _sendMorningBriefingNow();
              }
              if (value == 'notification_permission') {
                await _requestNotificationPermissionFromSettings();
              }
              if (value == 'privacy_policy') {
                await _openPrivacyPolicy();
              }
              if (value == 'about_bryloq') {
                await _showAboutBryloq();
              }
            },
            itemBuilder: (context) => [
              if (!_calendarConnected)
                const PopupMenuItem(
                  value: 'calendar_connect',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_outlined),
                      SizedBox(width: 10),
                      Text('Connect Google Calendar'),
                    ],
                  ),
                ),
              if (_calendarConnected)
                const PopupMenuItem(
                  value: 'calendar_sync',
                  child: Row(
                    children: [
                      Icon(Icons.sync_rounded),
                      SizedBox(width: 10),
                      Text('Sync Google Calendar'),
                    ],
                  ),
                ),
              if (_calendarConnected)
                const PopupMenuItem(
                  value: 'calendar_disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.link_off_rounded),
                      SizedBox(width: 10),
                      Text('Disconnect Google Calendar'),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'test_notification',
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined),
                    SizedBox(width: 10),
                    Text('Test notification'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'morning_briefing',
                child: Row(
                  children: [
                    Icon(Icons.wb_sunny_outlined),
                    SizedBox(width: 10),
                    Text('Test morning briefing'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'notification_permission',
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_outlined),
                    SizedBox(width: 10),
                    Text('Notification permission'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'privacy_policy',
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 10),
                    Text('Privacy Policy'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about_bryloq',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 10),
                    Text('About BRYLOQ'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(
                Icons.tune_rounded,
                size: 21,
                color: Color(0xFF5B2CC8),
              ),
            ),
          ),
        ),
      ],
    );
  }



  Widget _topBarAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE6DDF2),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5C35B5).withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 21,
          color: const Color(0xFF5B2CC8),
        ),
      ),
    );
  }

  String _friendlyTodayLabel() {
    final now = DateTime.now();
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  Widget _buildHeroIntro() {
    final activeToday = _savedTasks.where((task) {
      return !task.completed && _isTaskForTodayOrOverdue(task);
    }).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFF7F1FF),
                Color(0xFFFFFFFF),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFE4D8FA),
            ),
          ),
          child: Text(
            _friendlyTodayLabel().toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF6E5D85),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _greetingText(),
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF796F86),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          "What's on your mind?",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: Color(0xFF21172E),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          activeToday == 0
              ? 'Speak naturally. BRYLOQ turns your words into a plan.'
              : '$activeToday ${activeToday == 1 ? 'thing' : 'things'} on your radar • Speak and BRYLOQ will organise it.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8A8096),
            fontSize: 13,
            height: 1.38,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  Widget _buildMicrophone() {
    final accent = _isListening
        ? const Color(0xFFFF5A6F)
        : const Color(0xFF6D3DF5);

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleListening,
            child: SizedBox(
              width: 178,
              height: 178,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 174,
                      height: 174,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: 0.13),
                            accent.withValues(alpha: 0.03),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.82),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6D3DF5)
                              .withValues(alpha: 0.08),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.10),
                    ),
                  ),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isListening
                              ? const [
                                  Color(0xFFFF5A6F),
                                  Color(0xFFFF7564),
                                ]
                              : const [
                                  Color(0xFF9A72FF),
                                  Color(0xFF6D3DF5),
                                  Color(0xFF4F22B8),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.34),
                            blurRadius: 34,
                            spreadRadius: 2,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              _isListening
                  ? 'Listening…'
                  : _isProcessingAi
                      ? 'BRYLOQ is thinking…'
                      : 'Tap to speak',
              key: ValueKey('$_isListening-$_isProcessingAi'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _isListening
                    ? accent
                    : const Color(0xFF241833),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFE5DCF0),
              ),
            ),
            child: Text(
              _isListening
                  ? 'Tap again when finished'
                  : 'Tasks • reminders • appointments • ideas',
              style: const TextStyle(
                color: Color(0xFF897F94),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: const Color(
            0xFFEAE2F7,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                color: Color(
                  0xFF6D3DF5,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'I heard',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _clearText,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _spokenText,
            style: const TextStyle(
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isProcessingAi ? null : _organiseWithAi,
              icon: _isProcessingAi
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  _isProcessingAi
                      ? 'Understanding...'
                      : 'Organise with AI',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF6D3DF5),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'BRYLOQ understood',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF0E8FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_aiActions.length} ${_aiActions.length == 1 ? 'action' : 'actions'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6D3DF5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._aiActions.asMap().entries.map(
          (entry) => _buildAiActionCard(
            entry.value,
            entry.key,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saveAiActions,
            icon: const Icon(Icons.check_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Add all to BRYLOQ'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiActionCard(
    AiAction action,
    int index,
  ) {
    IconData icon;

    switch (action.type) {
      case 'reminder':
        icon = Icons.notifications_outlined;
        break;
      case 'appointment':
        icon = Icons.calendar_month_outlined;
        break;
      case 'event':
        icon = Icons.event_outlined;
        break;
      case 'shopping':
        icon = Icons.shopping_bag_outlined;
        break;
      case 'routine':
        icon = Icons.repeat_rounded;
        break;
      case 'note':
        icon = Icons.lightbulb_outline_rounded;
        break;
      case 'follow_up':
        icon = Icons.schedule_send_outlined;
        break;
      default:
        icon = Icons.check_circle_outline_rounded;
    }

    final details = <String>[];

    if (action.date != null && action.date!.trim().isNotEmpty) {
      details.add(action.date!);
    }

    if (action.time != null && action.time!.trim().isNotEmpty) {
      details.add(action.time!);
    }

    if (action.recurring &&
        action.recurrence != null &&
        action.recurrence!.trim().isNotEmpty) {
      details.add(action.recurrence!);
    }

    final selectedPriority = _aiPriorityOverrides[index] ??
        _normalisePriority(action.priority);

    details.add('${_priorityLabel(selectedPriority)} priority');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: const Color(0xFFE8E1F1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF2ECFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF6D3DF5),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.type.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6D3DF5),
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    details.join(' • '),
                    style: const TextStyle(
                      color: Color(0xFF77747F),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final priority in const [
                      'high',
                      'normal',
                      'low',
                    ])
                      ChoiceChip(
                        label: Text(_priorityLabel(priority)),
                        selected: selectedPriority == priority,
                        onSelected: (_) {
                          setState(() {
                            _aiPriorityOverrides[index] = priority;
                          });
                        },
                      ),
                  ],
                ),
                if (action.reminder != null &&
                    action.reminder!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 16,
                        color: Color(0xFF8E8B95),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          action.reminder!,
                          style: const TextStyle(
                            color: Color(0xFF8E8B95),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (action.notes != null &&
                    action.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    action.notes!,
                    style: const TextStyle(
                      color: Color(0xFF99969F),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalProcessingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF2EFFF),
            Color(0xFFFBFAFF),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0DBFF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D3DF5).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF5427C8)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BRYLOQ is organising this',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _inputSourceLabel ?? 'Analysing your input…',
                      style: const TextStyle(
                        color: Color(0xFF77747F),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 5,
              backgroundColor: Color(0xFFE4DAF2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeComposer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFEAE2F7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.keyboard_alt_outlined,
                color: Color(0xFF6D3DF5),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Type to BRYLOQ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    _showTypeComposer = false;
                  });
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _typeController,
            minLines: 3,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText:
                  'Example: Call Mum tomorrow at 6pm and buy milk after work.',
              filled: true,
              fillColor: const Color(0xFFFAF8FF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isProcessingAi ? null : _submitTypedText,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Organise'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFBF8FF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E1F1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          _quickAction(Icons.keyboard_alt_outlined, 'Type', _toggleTypeComposer),
          _quickAction(Icons.camera_alt_outlined, 'Camera', _takePhoto),
          _quickAction(Icons.image_outlined, 'Image', _pickImage),
          _quickAction(Icons.attach_file_rounded, 'File', _pickFile),
        ],
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: _isProcessingAi ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedOpacity(
          opacity: _isProcessingAi ? 0.45 : 1,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF4EDFF),
                        Color(0xFFE9DEFF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: const Color(0xFF6D3DF5),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF686571),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _taskDate(SayDoTask task) {
    return _parseTaskDateValue(task.date);
  }

  DateTime? _parseTaskDateValue(String? value) {
    final raw = value?.trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    final direct = DateTime.tryParse(raw);
    if (direct != null) {
      return direct;
    }

    final lower = raw.toLowerCase();
    final today = _todayDateOnly();

    if (lower == 'today') {
      return today;
    }

    if (lower == 'tomorrow') {
      return today.add(const Duration(days: 1));
    }

    final numeric = RegExp(
      r'^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$',
    ).firstMatch(raw);

    if (numeric != null) {
      final day = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      final year = int.tryParse(numeric.group(3)!);

      if (day != null && month != null && year != null) {
        final parsed = DateTime(year, month, day);
        if (parsed.year == year &&
            parsed.month == month &&
            parsed.day == day) {
          return parsed;
        }
      }
    }

    const weekdays = <String, int>{
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };

    for (final entry in weekdays.entries) {
      if (lower == entry.key || lower == 'next ${entry.key}') {
        var daysAhead = (entry.value - today.weekday) % 7;

        if (lower.startsWith('next ') || daysAhead == 0) {
          daysAhead = daysAhead == 0 ? 7 : daysAhead;
        }

        return today.add(Duration(days: daysAhead));
      }
    }

    return null;
  }

  int _compareInboxTasks(SayDoTask a, SayDoTask b) {
    final priorityCompare =
        _priorityRank(a.priority).compareTo(_priorityRank(b.priority));

    if (priorityCompare != 0) {
      return priorityCompare;
    }

    final aDate = _taskDate(a);
    final bDate = _taskDate(b);

    if (aDate != null && bDate != null) {
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }

    final timeCompare =
        (a.time ?? '99:99').compareTo(b.time ?? '99:99');
    if (timeCompare != 0) {
      return timeCompare;
    }

    return a.createdAt.compareTo(b.createdAt);
  }

  DateTime _todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isTaskForTodayOrOverdue(SayDoTask task) {
    final date = _taskDate(task);

    if (date == null) {
      return false;
    }

    final dateOnly = DateTime(date.year, date.month, date.day);
    return !dateOnly.isAfter(_todayDateOnly());
  }

  bool _isFutureTask(SayDoTask task) {
    final date = _taskDate(task);

    if (date == null) {
      return false;
    }

    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.isAfter(_todayDateOnly());
  }

  Widget _buildTodayContent() {
    final todayTasks = _savedTasks
        .where(
          (task) =>
              _isTaskForTodayOrOverdue(task) ||
              (task.completed && task.date == _todayKey()),
        )
        .toList();

    final plan = _todayPlan;

    if (plan == null) {
      if (todayTasks.isEmpty) {
        return _buildEmptyToday();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_calendarConnected) ...[
            _buildGoogleCalendarCard(),
            const SizedBox(height: 18),
          ],
          _buildTodayHeader(
            count: todayTasks.where((task) => !task.completed).length,
          ),
          const SizedBox(height: 12),
          _buildTodayProgressCard(todayTasks),
          const SizedBox(height: 15),
          ...todayTasks.map(
            (task) => _savedTaskTile(task),
          ),
        ],
      );
    }

    final plannedTaskIds = plan.items
        .map((item) => item.taskId)
        .whereType<String>()
        .toSet();

    final remainingTasks = todayTasks
        .where(
          (task) =>
              !task.completed &&
              !plannedTaskIds.contains(task.id),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_calendarConnected) ...[
          _buildGoogleCalendarCard(),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            const Expanded(
              child: Text(
                'TODAY\'S PLAN',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _openPlanMyDay,
              icon: const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
              ),
              label: const Text('Fix my day'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTodayProgressCard(todayTasks),
        const SizedBox(height: 12),
        _buildAppliedPlanSummary(plan),
        const SizedBox(height: 14),
        ...plan.items.map(
          (item) => _todayPlanItemTile(item),
        ),
        if (remainingTasks.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'STILL TO PLACE',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                  ),
                ),
              ),
              Text(
                '${remainingTasks.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...remainingTasks.map(
            (task) => _savedTaskTile(task),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyToday() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFEEECEF),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.wb_sunny_outlined,
            size: 42,
            color: Color(0xFF6D3DF5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your day is clear',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Future and unscheduled captures are waiting in Inbox.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8E8B95),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedNavIndex = 1;
              });
            },
            icon: const Icon(Icons.inbox_outlined),
            label: const Text('Open Inbox'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSearchHistory() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final selected = await Navigator.of(context).push<SayDoTask>(
      MaterialPageRoute(
        builder: (context) => SearchHistoryScreen(
          tasks: List<SayDoTask>.from(_savedTasks),
        ),
      ),
    );

    if (selected == null || !mounted) {
      return;
    }

    await _editTask(selected);
  }

  Widget _buildInboxContent() {
    final notes = _savedTasks
        .where(
          (task) =>
              !task.completed &&
              task.type == 'note' &&
              _taskDate(task) == null,
        )
        .toList();

    final unscheduled = _savedTasks
        .where(
          (task) =>
              !task.completed &&
              task.type != 'note' &&
              _taskDate(task) == null,
        )
        .toList()
      ..sort(_compareInboxTasks);

    final upcoming = _savedTasks
        .where(
          (task) =>
              !task.completed &&
              _isFutureTask(task),
        )
        .toList()
      ..sort(_compareInboxTasks);

    final completed = _savedTasks
        .where((task) => task.completed)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final inboxCount =
        unscheduled.length + upcoming.length + notes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(
                Icons.inbox_rounded,
                color: Color(0xFF6D3DF5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Inbox',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    inboxCount == 0
                        ? 'Everything has a place.'
                        : '$inboxCount ${inboxCount == 1 ? 'item needs' : 'items need'} a place.',
                    style: const TextStyle(
                      color: Color(0xFF8E8B95),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openSearchHistory,
            icon: const Icon(Icons.search_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Text('Search all BRYLOQ history'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildInboxOverview(
          unscheduled: unscheduled.length,
          upcoming: upcoming.length,
          notes: notes.length,
        ),
        if (unscheduled.isNotEmpty) ...[
          const SizedBox(height: 30),
          _inboxSectionHeader(
            'UNSCHEDULED',
            unscheduled.length,
            'Tasks captured without a date',
          ),
          const SizedBox(height: 12),
          ...unscheduled.map(
            (task) => _inboxTaskTile(
              task,
              badge: 'Needs a date',
              badgeIcon: Icons.calendar_today_outlined,
            ),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 30),
          _inboxSectionHeader(
            'UPCOMING',
            upcoming.length,
            'Future tasks • High priority first',
          ),
          const SizedBox(height: 12),
          ...upcoming.map(
            (task) => _inboxTaskTile(
              task,
              badge: _friendlyTaskDate(task),
              badgeIcon: Icons.event_outlined,
            ),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 30),
          _inboxSectionHeader(
            'NOTES & IDEAS',
            notes.length,
            'Useful things BRYLOQ is remembering',
          ),
          const SizedBox(height: 12),
          ...notes.map(
            (task) => _inboxTaskTile(
              task,
              badge: 'Note',
              badgeIcon: Icons.lightbulb_outline_rounded,
            ),
          ),
        ],
        if (inboxCount == 0) ...[
          const SizedBox(height: 30),
          _buildEmptyInbox(),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 34),
          _inboxSectionHeader(
            'COMPLETED',
            completed.length,
            'Recently finished',
          ),
          const SizedBox(height: 12),
          ...completed.take(5).map(
            (task) => _inboxTaskTile(
              task,
              badge: 'Done',
              badgeIcon: Icons.check_circle_outline_rounded,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInboxOverview({
    required int unscheduled,
    required int upcoming,
    required int notes,
  }) {
    return Row(
      children: [
        Expanded(
          child: _inboxStat(
            value: unscheduled,
            label: 'Unscheduled',
            icon: Icons.schedule_outlined,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _inboxStat(
            value: upcoming,
            label: 'Upcoming',
            icon: Icons.event_outlined,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _inboxStat(
            value: notes,
            label: 'Notes',
            icon: Icons.lightbulb_outline_rounded,
          ),
        ),
      ],
    );
  }

  Widget _inboxStat({
    required int value,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 15,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEEECEF),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 20,
            color: const Color(0xFF6D3DF5),
          ),
          const SizedBox(height: 7),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8E8B95),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxSectionHeader(
    String title,
    int count,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF99969F),
          ),
        ),
      ],
    );
  }

  Widget _inboxTaskTile(
    SayDoTask task, {
    required String badge,
    required IconData badgeIcon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEEECEF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _toggleTask(task),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 25,
              height: 25,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.completed
                    ? const Color(0xFF6D3DF5)
                    : Colors.transparent,
                border: Border.all(
                  color: task.completed
                      ? const Color(0xFF6D3DF5)
                      : const Color(0xFFB8B5BF),
                  width: 2,
                ),
              ),
              child: task.completed
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration: task.completed
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.completed
                        ? Colors.grey
                        : const Color(0xFF24232A),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _inboxBadge(
                      badge,
                      badgeIcon,
                    ),
                    _inboxBadge(
                      task.type
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                      Icons.sell_outlined,
                    ),
                    _inboxBadge(
                      '${_priorityLabel(task.priority)} priority',
                      task.priority == 'high'
                          ? Icons.priority_high_rounded
                          : Icons.flag_outlined,
                    ),
                  ],
                ),
                if (task.notes != null &&
                    task.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    task.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8E8B95),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'today') {
                await _moveTaskToToday(task);
              } else if (value == 'schedule') {
                await _scheduleTask(task);
              } else if (value == 'edit') {
                await _editTask(task);
              } else if (value == 'calendar') {
                await _addTaskToGoogleCalendar(task);
              } else if (value == 'delete') {
                await _deleteTask(task);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'today',
                child: Row(
                  children: [
                    Icon(Icons.today_outlined),
                    SizedBox(width: 10),
                    Text('Move to Today'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'schedule',
                child: Row(
                  children: [
                    Icon(Icons.event_outlined),
                    SizedBox(width: 10),
                    Text('Schedule'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined),
                    SizedBox(width: 10),
                    Text('Edit'),
                  ],
                ),
              ),
              if (_calendarConnected)
                const PopupMenuItem(
                  value: 'calendar',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_outlined),
                      SizedBox(width: 10),
                      Text('Add to Google Calendar'),
                    ],
                  ),
                ),
              PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 10),
                    Text('Delete'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inboxBadge(
    String label,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: const Color(0xFF6D3DF5),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6D3DF5),
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyTaskDate(SayDoTask task) {
    final date = _taskDate(task);

    if (date == null) {
      return 'No date';
    }

    final today = _todayDateOnly();
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == tomorrow) {
      return 'Tomorrow';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]}';
  }

  Widget _buildEmptyInbox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFEEECEF),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 42,
            color: Color(0xFFB4B0BE),
          ),
          SizedBox(height: 12),
          Text(
            'Inbox zero',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Everything is scheduled or already handled.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8E8B95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppliedPlanSummary(
    DayPlan plan,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7567FF),
            Color(0xFF5548EB),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (plan.focus.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              plan.focus,
              style: const TextStyle(
                color: Color(0xFFE8E5FF),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _todayPlanItemTile(
    DayPlanItem item,
  ) {
    SayDoTask? linkedTask;

    if (item.taskId != null) {
      for (final task in _savedTasks) {
        if (task.id == item.taskId) {
          linkedTask = task;
          break;
        }
      }
    }

    final isBreak = item.kind == 'break' || item.taskId == null;
    final isCompleted = linkedTask?.completed ?? false;

    IconData icon;
    switch (item.kind) {
      case 'fixed':
        icon = Icons.push_pin_outlined;
        break;
      case 'focus':
        icon = Icons.center_focus_strong_rounded;
        break;
      case 'break':
        icon = Icons.coffee_outlined;
        break;
      default:
        icon = Icons.schedule_rounded;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: isCompleted ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(13, 13, 8, 13),
        decoration: BoxDecoration(
          color: isBreak
              ? const Color(0xFFFAF8FF)
              : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isBreak
                ? const Color(0xFFE5E0FA)
                : const Color(0xFFEAE8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.026),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            if (!isBreak)
              GestureDetector(
                onTap: linkedTask == null
                    ? null
                    : () => _toggleTask(linkedTask!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? const Color(0xFF6D3DF5)
                        : const Color(0xFFF7F6FA),
                    border: Border.all(
                      color: isCompleted
                          ? const Color(0xFF6D3DF5)
                          : const Color(0xFFC6C2CE),
                      width: 1.8,
                    ),
                  ),
                  child: isCompleted
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : null,
                ),
              )
            else
              Container(
                width: 27,
                height: 27,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFECE8FF),
                ),
                child: const Icon(
                  Icons.coffee_outlined,
                  size: 15,
                  color: Color(0xFF6D3DF5),
                ),
              ),
            const SizedBox(width: 11),
            Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F2FF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                children: [
                  Text(
                    item.startTime,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6D3DF5),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.endTime,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Color(0xFF99969F),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: const Color(0xFF6D3DF5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      decoration: isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      color: isCompleted
                          ? Colors.grey
                          : const Color(0xFF24232A),
                    ),
                  ),
                  if (item.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8B95),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (linkedTask != null)
              PopupMenuButton<String>(
                tooltip: 'Task options',
                onSelected: (value) async {
                  final task = linkedTask!;
                  if (value == 'edit') {
                    await _editTask(task);
                  } else if (value == 'schedule') {
                    await _scheduleTask(task);
                  } else if (value == 'calendar') {
                    await _addTaskToGoogleCalendar(task);
                  } else if (value == 'delete') {
                    await _deleteTask(task);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 10),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'schedule',
                    child: Row(
                      children: [
                        Icon(Icons.event_outlined),
                        SizedBox(width: 10),
                        Text('Reschedule'),
                      ],
                    ),
                  ),
                  if (_calendarConnected)
                    const PopupMenuItem(
                      value: 'calendar',
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined),
                          SizedBox(width: 10),
                          Text('Add to Google Calendar'),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleCalendarCard() {
    final events = _calendarEventsToday;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF3F0FF),
            Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2DEFA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D3DF5).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF6D3DF5),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D3DF5).withValues(alpha: 0.20),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Calendar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      events.isEmpty
                          ? 'No fixed commitments today'
                          : '${events.length} ${events.length == 1 ? 'commitment' : 'commitments'} today',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF85818D),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sync calendar',
                onPressed: _calendarSyncing ? null : () => _syncGoogleCalendar(),
                icon: _calendarSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
              ),
            ],
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 13),
            Container(
              height: 1,
              color: const Color(0xFFE7E3F4),
            ),
            const SizedBox(height: 11),
            ...events.take(4).map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6D3DF5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 82,
                      child: Text(
                        event.timeLabel,
                        style: const TextStyle(
                          color: Color(0xFF6D3DF5),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (events.length > 4)
              Text(
                '+${events.length - 4} more',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8E8B95),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTodayProgressCard(
    List<SayDoTask> tasks,
  ) {
    final total = tasks.length;
    final completed = tasks.where((task) => task.completed).length;
    final active = total - completed;

    final today = _todayDateOnly();
    final overdue = tasks.where((task) {
      if (task.completed) return false;
      final date = _taskDate(task);
      if (date == null) return false;
      final dateOnly = DateTime(date.year, date.month, date.day);
      return dateOnly.isBefore(today);
    }).length;

    final progress = total == 0 ? 0.0 : completed / total;
    final percent = (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF6F3FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E3F4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor: const Color(0xFFE8E5F0),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF6D3DF5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TODAY AT A GLANCE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8E8B95),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$completed of $total done',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  overdue > 0
                      ? '$active left • $overdue overdue'
                      : '$active ${active == 1 ? 'thing' : 'things'} left today',
                  style: TextStyle(
                    fontSize: 12,
                    color: overdue > 0
                        ? const Color(0xFFE2763E)
                        : const Color(0xFF8E8B95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Color(0xFFB0ACB8),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayHeader({
    required int count,
  }) {
    final activeTasks = count;

    return Row(
      children: [
        const Expanded(
          child: Text(
            'TASKS',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight:
                  FontWeight.w800,
              color: Colors.grey,
            ),
          ),
        ),

        Text(
          '$activeTasks ${activeTasks == 1 ? 'task' : 'tasks'}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _savedTaskTile(
    SayDoTask task,
  ) {
    final displayTime = task.time == null || task.time!.trim().isEmpty
        ? '--:--'
        : task.time!;
    final hasReminder =
        task.reminder != null && task.reminder!.trim().isNotEmpty;

    IconData typeIcon;
    switch (task.type) {
      case 'reminder':
        typeIcon = Icons.notifications_none_rounded;
        break;
      case 'appointment':
      case 'event':
        typeIcon = Icons.event_outlined;
        break;
      case 'shopping':
        typeIcon = Icons.shopping_bag_outlined;
        break;
      case 'routine':
        typeIcon = Icons.repeat_rounded;
        break;
      case 'note':
        typeIcon = Icons.notes_rounded;
        break;
      case 'follow_up':
        typeIcon = Icons.reply_rounded;
        break;
      default:
        typeIcon = Icons.check_circle_outline_rounded;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: task.completed ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(13, 13, 8, 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEAE8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.028),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _toggleTask(task),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.completed
                      ? const Color(0xFF6D3DF5)
                      : const Color(0xFFF7F6FA),
                  border: Border.all(
                    color: task.completed
                        ? const Color(0xFF6D3DF5)
                        : const Color(0xFFC6C2CE),
                    width: 1.8,
                  ),
                ),
                child: task.completed
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1EFFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                typeIcon,
                size: 20,
                color: const Color(0xFF6D3DF5),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            decoration: task.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.completed
                                ? Colors.grey
                                : const Color(0xFF24232A),
                          ),
                        ),
                      ),
                      if (hasReminder)
                        const Padding(
                          padding: EdgeInsets.only(left: 5),
                          child: Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: Color(0xFF6D3DF5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F4FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          displayTime,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6D3DF5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _taskSubtitle(task),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF8E8B95),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Task options',
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editTask(task);
                } else if (value == 'schedule') {
                  await _scheduleTask(task);
                } else if (value == 'calendar') {
                  await _addTaskToGoogleCalendar(task);
                } else if (value == 'delete') {
                  await _deleteTask(task);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'schedule',
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined),
                      SizedBox(width: 10),
                      Text('Reschedule'),
                    ],
                  ),
                ),
                if (_calendarConnected)
                  const PopupMenuItem(
                    value: 'calendar',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_outlined),
                        SizedBox(width: 10),
                        Text('Add to Google Calendar'),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 10),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _taskSubtitle(
    SayDoTask task,
  ) {
    final details =
        <String>[];

    if (task.date != null &&
        task.date!.trim().isNotEmpty) {
      details.add(
        task.date!,
      );
    }

    details.add(
      task.type
          .replaceAll(
        '_',
        ' ',
      )
          .toUpperCase(),
    );

    if (task.recurring) {
      if (task.recurrence != null &&
          task.recurrence!
              .trim()
              .isNotEmpty) {
        details.add(
          task.recurrence!,
        );
      } else {
        details.add(
          'Recurring',
        );
      }
    }

    details.add(
      '${_priorityLabel(task.priority)} priority',
    );

    return details.join(
      ' • ',
    );
  }
}
class TaskEditSheet extends StatefulWidget {
  final SayDoTask task;

  const TaskEditSheet({
    super.key,
    required this.task,
  });

  @override
  State<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<TaskEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  DateTime? _date;
  TimeOfDay? _time;
  late String _priority;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.task.title,
    );

    _notesController = TextEditingController(
      text: widget.task.notes ?? '',
    );

    _priority = widget.task.priority == 'medium'
        ? 'normal'
        : widget.task.priority;

    if (widget.task.date != null &&
        widget.task.date!.trim().isNotEmpty) {
      _date = DateTime.tryParse(widget.task.date!);
    }

    if (widget.task.time != null && widget.task.time!.contains(':')) {
      final parts = widget.task.time!.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          _time = TimeOfDay(
            hour: hour,
            minute: minute,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _dateLabel() {
    final date = _date;
    if (date == null) {
      return 'No date';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _timeLabel() {
    final time = _time;
    if (time == null) {
      return 'No time';
    }

    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(
        const Duration(days: 3650),
      ),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
    );

    if (chosen != null && mounted) {
      setState(() {
        _date = chosen;
      });
    }
  }

  Future<void> _chooseTime() async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );

    if (chosen != null && mounted) {
      setState(() {
        _time = chosen;
      });
    }
  }

  void _save() {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task title cannot be empty.'),
        ),
      );
      return;
    }

    final formattedDate = _date == null
        ? null
        : '${_date!.year.toString().padLeft(4, '0')}-'
            '${_date!.month.toString().padLeft(2, '0')}-'
            '${_date!.day.toString().padLeft(2, '0')}';

    final formattedTime = _time == null
        ? null
        : '${_time!.hour.toString().padLeft(2, '0')}:'
            '${_time!.minute.toString().padLeft(2, '0')}';

    Navigator.pop(
      context,
      SayDoTask(
        id: widget.task.id,
        title: title,
        type: widget.task.type,
        date: formattedDate,
        time: formattedTime,
        priority: _priority,
        recurring: widget.task.recurring,
        recurrence: widget.task.recurrence,
        recurrenceType: widget.task.recurrenceType,
        recurrenceInterval: widget.task.recurrenceInterval,
        recurrenceWeekdays: widget.task.recurrenceWeekdays,
        recurrenceDayOfMonth: widget.task.recurrenceDayOfMonth,
        reminder: widget.task.reminder,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        completed: widget.task.completed,
        createdAt: widget.task.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8FC),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        16,
        22,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D3DE),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Edit task',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_dateLabel()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chooseTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(_timeLabel()),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _date = null;
                    });
                  },
                  child: const Text('Clear date'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _time = null;
                    });
                  },
                  child: const Text('Clear time'),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'low',
                  child: Text('Low'),
                ),
                DropdownMenuItem(
                  value: 'normal',
                  child: Text('Medium'),
                ),
                DropdownMenuItem(
                  value: 'high',
                  child: Text('High'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _priority = value;
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Save changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DayPlanSheet extends StatefulWidget {
  final List<SayDoTask> tasks;
  final List<GoogleCalendarEvent> calendarEvents;
  final AiService aiService;
  final Future<int> Function(DayPlan plan) onApplyPlan;

  const DayPlanSheet({
    super.key,
    required this.tasks,
    required this.calendarEvents,
    required this.aiService,
    required this.onApplyPlan,
  });

  @override
  State<DayPlanSheet> createState() =>
      _DayPlanSheetState();
}

class _DayPlanSheetState extends State<DayPlanSheet> {
  bool _loading = true;
  bool _applying = false;
  DayPlan? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePlan();
  }

  Future<void> _generatePlan() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final plan = await widget.aiService.planDay(
        widget.tasks,
        calendarEvents: widget.calendarEvents,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _plan = plan;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _applyPlan() async {
    final plan = _plan;

    if (plan == null || _applying) {
      return;
    }

    setState(() {
      _applying = true;
      _error = null;
    });

    try {
      final appliedCount = await widget.onApplyPlan(
        plan,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        appliedCount,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Could not apply the plan: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8FC),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD5D2DC),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              22,
              18,
              14,
              12,
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEAFE),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF6D3DF5),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan my day',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'BRYLOQ builds a realistic schedule from your tasks.',
                        style: TextStyle(
                          color: Color(0xFF8E8B95),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                'Building your day...',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Checking deadlines, fixed times and priorities.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E8B95),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 42,
                  color: Color(0xFFFF5A6F),
                ),
                const SizedBox(height: 12),
                const Text(
                  'BRYLOQ could not build the plan',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF77747F),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _generatePlan,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final plan = _plan;

    if (plan == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7567FF),
                Color(0xFF5548EB),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (plan.focus.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  plan.focus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (plan.summary.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  plan.summary,
                  style: const TextStyle(
                    color: Color(0xFFE8E5FF),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'TODAY\'S FLOW',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF77747F),
                ),
              ),
            ),
            Text(
              '${plan.items.length} blocks',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8E8B95),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (plan.items.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Nothing needs scheduling right now.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ...plan.items.map(_planItemCard),
        if (plan.carryOver.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'MOVE FORWARD',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w800,
              color: Color(0xFF77747F),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFEAE8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: plan.carryOver
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Color(0xFF6D3DF5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _applying ? null : _applyPlan,
            icon: _applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                _applying
                    ? 'Applying plan...'
                    : 'Apply this plan',
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _applying ? null : _generatePlan,
            icon: const Icon(Icons.refresh_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Text('Regenerate plan'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Apply writes the suggested start times to your saved tasks and keeps the full plan, including breaks, on Today.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF99969F),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        SizedBox(
          height: MediaQuery.viewPaddingOf(context).bottom + 24,
        ),
      ],
    );
  }

  Widget _planItemCard(DayPlanItem item) {
    IconData icon;

    switch (item.kind) {
      case 'fixed':
        icon = Icons.push_pin_outlined;
        break;
      case 'focus':
        icon = Icons.center_focus_strong_rounded;
        break;
      case 'break':
        icon = Icons.coffee_outlined;
        break;
      default:
        icon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEAE8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.startTime,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.endTime,
                  style: const TextStyle(
                    color: Color(0xFF99969F),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EEFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 19,
              color: const Color(0xFF6D3DF5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.reason,
                    style: const TextStyle(
                      color: Color(0xFF77747F),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

