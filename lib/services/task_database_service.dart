import 'package:hive_ce/hive.dart';

import '../models/saydo_task.dart';

class TaskDatabaseService {
  static const String _boxName = 'saydo_tasks';

  Box<dynamic>? _box;

  Future<void> initialise() async {
    _box = await Hive.openBox<dynamic>(
      _boxName,
    );
  }

  Future<List<SayDoTask>> getTasks() async {
    final box = _box;

    if (box == null) {
      throw Exception(
        'Task database has not been initialised.',
      );
    }

    return box.values
        .whereType<Map>()
        .map(
          (item) => SayDoTask.fromMap(
            Map<dynamic, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<void> saveTask(
    SayDoTask task,
  ) async {
    final box = _box;

    if (box == null) {
      throw Exception(
        'Task database has not been initialised.',
      );
    }

    await box.put(
      task.id,
      task.toMap(),
    );
  }

  Future<void> deleteTask(
    String id,
  ) async {
    final box = _box;

    if (box == null) {
      return;
    }

    await box.delete(id);
  }

  Future<void> toggleComplete(
    SayDoTask task,
  ) async {
    final updated = SayDoTask(
      id: task.id,
      title: task.title,
      type: task.type,
      date: task.date,
      time: task.time,
      priority: task.priority,
      recurring: task.recurring,
      recurrence: task.recurrence,
      reminder: task.reminder,
      notes: task.notes,
      completed: !task.completed,
      createdAt: task.createdAt,
    );

    await saveTask(updated);
  }
}