import '../models/deadline.dart';
import '../models/task_step.dart';

/// Owner-scoped Oracle backup payloads. Never include Moodle credentials
/// or calendar URLs in personal (non-encrypted) backup documents.
class OraclePersonalBackupCodec {
  const OraclePersonalBackupCodec._();

  static bool _safeId(String value) =>
      value.isNotEmpty &&
      !RegExp(
        r'https?[:/]|authtoken|access_token|password|[?&]token=',
        caseSensitive: false,
      ).hasMatch(value);

  static Map<String, dynamic> prepare({
    required List<Deadline> manualTasks,
    required Map<String, TaskPlan> plans,
  }) => {
    'schema': 1,
    'manualTasks': manualTasks
        .where((task) => _safeId(task.uid))
        .map(
          (task) => {
            'uid': task.uid,
            'title': task.title,
            'due': task.due.toIso8601String(),
            'description': task.description,
            'course': task.course,
            'priority': task.priority,
            'reminderMinutesBefore': task.reminderMinutesBefore,
            'lastModified': task.lastModified?.toIso8601String(),
          },
        )
        .toList(),
    'plans': plans.entries
        .where((entry) => _safeId(entry.key))
        .map((entry) => entry.value.toJson())
        .toList(),
  };

  static ({List<Deadline> tasks, Map<String, TaskPlan> plans}) decode(
    Map<String, dynamic>? data,
  ) {
    if (data == null || data['schema'] != 1) {
      return (tasks: <Deadline>[], plans: <String, TaskPlan>{});
    }
    final tasks = <Deadline>[];
    for (final value in (data['manualTasks'] as List<dynamic>? ?? [])) {
      try {
        final item = Map<String, dynamic>.from(value as Map);
        if (!_safeId(item['uid'] as String? ?? '')) continue;
        tasks.add(Deadline.fromJson(item));
      } catch (_) {
        // A damaged entry cannot overwrite good local data.
      }
    }
    final plans = <String, TaskPlan>{};
    for (final value in (data['plans'] as List<dynamic>? ?? [])) {
      try {
        final plan = TaskPlan.fromJson(Map<String, dynamic>.from(value as Map));
        if (_safeId(plan.deadlineId)) plans[plan.deadlineId] = plan;
      } catch (_) {
        // Ignore malformed records without failing the whole restore.
      }
    }
    return (tasks: tasks, plans: plans);
  }
}
