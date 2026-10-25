import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/deadline.dart';
import '../models/task_step.dart';
import 'task_plan_repository.dart';

/// Only a user-initiated backup of non-secret fields. Not Moodle ICS or API data.
class OptionalCloudBackup {
  const OptionalCloudBackup(this.firestore);

  final FirebaseFirestore firestore;

  DocumentReference<Map<String, dynamic>> _document(User user) =>
      firestore.collection('users').doc(user.uid).collection('backups').doc('personal-v1');

  static bool _safeId(String value) =>
      value.isNotEmpty &&
      !RegExp(r'https?[:/]|authtoken|access_token|password|[?&]token=', caseSensitive: false)
          .hasMatch(value);

  static Map<String, dynamic> _task(Deadline task) => {
    'uid': task.uid,
    'title': task.title,
    'due': task.due.toIso8601String(),
    'description': task.description,
    'course': task.course,
    'priority': task.priority,
    'reminderMinutesBefore': task.reminderMinutesBefore,
    'lastModified': task.lastModified?.toIso8601String(),
  };

  /// Export only manual tasks and safe plan IDs; no calendar feed or credentials.
  static Map<String, dynamic> prepare({
    required List<Deadline> manualTasks,
    required Map<String, TaskPlan> plans,
  }) => {
    'schema': 1,
    'manualTasks': manualTasks.where((task) => _safeId(task.uid))
        .map(_task).toList(),
    'plans': plans.entries.where((entry) => _safeId(entry.key))
        .map((entry) => entry.value.toJson()).toList(),
  };

  Future<void> upload({
    required User user,
    required List<Deadline> manualTasks,
    required Map<String, TaskPlan> plans,
  }) async {
    final payload = prepare(manualTasks: manualTasks, plans: plans);
    await _document(user).set({
      ...payload,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<({List<Deadline> tasks, Map<String, TaskPlan> plans})> download(
    User user,
  ) async {
    final data = (await _document(user).get()).data();
    if (data == null || data['schema'] != 1) {
      return (tasks: <Deadline>[], plans: <String, TaskPlan>{});
    }
    final tasks = <Deadline>[];
    for (final value in (data['manualTasks'] as List<dynamic>? ?? [])) {
      try {
        final item = Map<String, dynamic>.from(value as Map);
        // Never accept a URL or OAuth/Moodle secrets from a remote document.
        if (!_safeId(item['uid'] as String? ?? '')) continue;
        tasks.add(Deadline.fromJson({
          'uid': item['uid'],
          'title': item['title'],
          'due': item['due'],
          'description': item['description'],
          'course': item['course'],
          'priority': item['priority'],
          'reminderMinutesBefore': item['reminderMinutesBefore'],
          'lastModified': item['lastModified'],
        }));
      } catch (_) {
        // Skip invalid remote entries without losing the other tasks.
      }
    }
    final plans = <String, TaskPlan>{};
    for (final value in (data['plans'] as List<dynamic>? ?? [])) {
      try {
        final plan = TaskPlan.fromJson(Map<String, dynamic>.from(value as Map));
        if (_safeId(plan.deadlineId)) plans[plan.deadlineId] = plan;
      } catch (_) {
        // Skip malformed plans.
      }
    }
    return (tasks: tasks, plans: plans);
  }
}
