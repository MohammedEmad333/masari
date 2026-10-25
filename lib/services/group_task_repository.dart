import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/group_task.dart';

/// Local-only group planning. This does not invite or sync other users.
class GroupTaskRepository {
  const GroupTaskRepository();

  static const storageKey = 'group_tasks_v1';

  Future<List<GroupTask>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .map(
            (value) =>
                GroupTask.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .where((group) => group.assignmentsValid)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(GroupTask group) async {
    if (!group.assignmentsValid ||
        group.id.isEmpty ||
        group.deadlineId.isEmpty) {
      throw ArgumentError('Invalid group assignments or identifiers');
    }
    final groups = await loadAll();
    final index = groups.indexWhere((value) => value.id == group.id);
    if (index < 0) {
      groups.add(group);
    } else {
      groups[index] = group;
    }
    await _write(groups);
  }

  Future<void> remove(String groupId) async {
    final groups = await loadAll();
    groups.removeWhere((value) => value.id == groupId);
    await _write(groups);
  }

  Future<void> _write(List<GroupTask> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      storageKey,
      jsonEncode(groups.map((group) => group.toJson()).toList()),
    );
    if (!saved) throw StateError('Unable to save group tasks');
  }
}
