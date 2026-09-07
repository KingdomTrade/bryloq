import 'package:hive_ce/hive.dart';

import '../models/day_plan.dart';

class DayPlanDatabaseService {
  static const String _boxName = 'saydo_day_plans';

  Box<dynamic>? _box;

  Future<void> initialise() async {
    if (_box?.isOpen == true) {
      return;
    }

    _box = await Hive.openBox<dynamic>(
      _boxName,
    );
  }

  DayPlan? getPlan(
    String date,
  ) {
    final raw = _box?.get(date);

    if (raw is Map) {
      return DayPlan.fromMap(raw);
    }

    return null;
  }

  Future<void> savePlan(
    String date,
    DayPlan plan,
  ) async {
    await initialise();

    await _box!.put(
      date,
      plan.toMap(),
    );
  }

  Future<void> deletePlan(
    String date,
  ) async {
    await initialise();
    await _box!.delete(date);
  }
}
