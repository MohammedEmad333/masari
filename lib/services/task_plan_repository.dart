import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_step.dart';

/// Stores plans separately from Moodle events so ICS synchronization cannot
/// accidentally erase a student's personal progress.
class TaskPlanRepository {
  const TaskPlanRepository();

  static const storageKey = 'task_plans_v1';

  Future<Map<String, TaskPlan>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(storageKey);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return {};
      final result = <String, TaskPlan>{};
      for (final entry in decoded.entries) {
        try {
          final plan = TaskPlan.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          result[entry.key.toString()] = plan;
        } catch (_) {
          // Preserve other valid plans when one stored entry is corrupted.
        }
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<TaskPlan?> load(String deadlineId) async =>
      (await loadAll())[deadlineId];

  Future<void> save(TaskPlan plan) async {
    if (plan.deadlineId.trim().isEmpty) {
      throw ArgumentError.value(
        plan.deadlineId,
        'deadlineId',
        'Cannot be empty',
      );
    }
    final all = await loadAll();
    all[plan.deadlineId] = plan;
    await _write(all);
  }

  Future<void> remove(String deadlineId) async {
    final all = await loadAll();
    all.remove(deadlineId);
    await _write(all);
  }

  Future<void> _write(Map<String, TaskPlan> all) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = all.map((key, value) => MapEntry(key, value.toJson()));
    if (!await prefs.setString(storageKey, jsonEncode(serialized))) {
      throw StateError('Could not save task plans locally');
    }
  }
}
