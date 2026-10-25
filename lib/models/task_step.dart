enum TaskStepStatus { notStarted, inProgress, completed }

class TaskStep {
  const TaskStep({
    required this.id,
    required this.title,
    required this.scheduledFor,
    this.status = TaskStepStatus.notStarted,
  });

  final String id;
  final String title;
  final DateTime scheduledFor;
  final TaskStepStatus status;

  TaskStep copyWith({String? title, DateTime? scheduledFor, TaskStepStatus? status}) =>
      TaskStep(
        id: id,
        title: title ?? this.title,
        scheduledFor: scheduledFor ?? this.scheduledFor,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'scheduledFor': scheduledFor.toIso8601String(),
        'status': status.name,
      };

  factory TaskStep.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    return TaskStep(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledFor: DateTime.parse(json['scheduledFor'] as String),
      status: TaskStepStatus.values.firstWhere(
        (status) => status.name == rawStatus,
        orElse: () => TaskStepStatus.notStarted,
      ),
    );
  }
}

class TaskPlan {
  const TaskPlan({required this.deadlineId, required this.steps});
  final String deadlineId;
  final List<TaskStep> steps;

  int get completedCount => steps.where((s) => s.status == TaskStepStatus.completed).length;
  double get progress => steps.isEmpty ? 0 : completedCount / steps.length;

  Map<DateTime, List<TaskStep>> get byDay {
    final result = <DateTime, List<TaskStep>>{};
    for (final step in steps) {
      final date = DateTime(step.scheduledFor.year, step.scheduledFor.month, step.scheduledFor.day);
      result.putIfAbsent(date, () => []).add(step);
    }
    return result;
  }

  TaskPlan copyWith({List<TaskStep>? steps}) =>
      TaskPlan(deadlineId: deadlineId, steps: List.unmodifiable(steps ?? this.steps));

  Map<String, dynamic> toJson() => {
        'deadlineId': deadlineId,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory TaskPlan.fromJson(Map<String, dynamic> json) => TaskPlan(
        deadlineId: json['deadlineId'] as String,
        steps: List.unmodifiable(
          (json['steps'] as List<dynamic>)
              .map((item) => TaskStep.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList(),
        ),
      );
}
