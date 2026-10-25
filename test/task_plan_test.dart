import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/task_step.dart';
import 'package:moodle_reminder/services/task_plan_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('progress and grouped daily steps survive serialization', () {
    final plan = TaskPlan(deadlineId: 'moodle-123', steps: [
      TaskStep(id: '1', title: 'Research', scheduledFor: DateTime(2026, 10, 27), status: TaskStepStatus.completed),
      TaskStep(id: '2', title: 'Draft', scheduledFor: DateTime(2026, 10, 27), status: TaskStepStatus.inProgress),
      TaskStep(id: '3', title: 'Review', scheduledFor: DateTime(2026, 10, 28)),
    ]);
    expect(plan.progress, closeTo(1 / 3, 0.001));
    expect(plan.byDay.length, 2);
    final restored = TaskPlan.fromJson(plan.toJson());
    expect(restored.steps[1].status, TaskStepStatus.inProgress);
    expect(restored.progress, plan.progress);
  });

  test('plans for different Moodle tasks are stored independently', () async {
    const repository = TaskPlanRepository();
    await repository.save(TaskPlan(deadlineId: 'course:a', steps: [
      TaskStep(id: 's1', title: 'Read', scheduledFor: DateTime(2026, 10, 27)),
    ]));
    await repository.save(TaskPlan(deadlineId: 'course:b', steps: const []));
    expect((await repository.load('course:a'))?.steps.single.title, 'Read');
    await repository.remove('course:b');
    expect(await repository.load('course:b'), isNull);
    expect(await repository.load('course:a'), isNotNull);
  });

  test('bad plan entries do not discard valid ones', () async {
    SharedPreferences.setMockInitialValues({
      TaskPlanRepository.storageKey:
        '{"valid":{"deadlineId":"valid","steps":[]},"bad":{"steps":"oops"}}',
    });
    const repository = TaskPlanRepository();
    expect((await repository.loadAll()).keys, contains('valid'));
    expect((await repository.loadAll()).keys, isNot(contains('bad')));
  });
}
