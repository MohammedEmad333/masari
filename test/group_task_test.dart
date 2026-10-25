import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/group_task.dart';
import 'package:moodle_reminder/services/group_task_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('group progress and assignments round trip', () {
    final group = GroupTask(
      id: 'g1', deadlineId: 'moodle-1', name: 'Research',
      members: [const GroupTaskMember(id: 'student-1', name: 'A')],
      parts: [const GroupTaskPart(id: 'part-1', title: 'Outline',
          assigneeId: 'student-1', status: GroupTaskStatus.completed)],
    );
    expect(group.assignmentsValid, isTrue);
    expect(group.progress, 1.0);
    expect(GroupTask.fromJson(group.toJson()).parts.single.assigneeId, 'student-1');
  });

  test('unrecognized assignee is rejected', () async {
    const repository = GroupTaskRepository();
    final group = GroupTask(id: 'g1', deadlineId: 'moodle-1',
      name: 'Research', members: [],
      parts: [const GroupTaskPart(id: 'p1', title: 'Outline', assigneeId: 'unknown')]);
    expect(group.assignmentsValid, isFalse);
    await expectLater(repository.save(group), throwsArgumentError);
  });

  test('saving a group updates it without duplication', () async {
    const repository = GroupTaskRepository();
    final first = GroupTask(id: 'g1', deadlineId: 'task-1',
        name: 'Original', members: [], parts: []);
    await repository.save(first);
    await repository.save(GroupTask(id: 'g1', deadlineId: 'task-1',
        name: 'Changed', members: [], parts: []));
    expect((await repository.loadAll()).length, 1);
    expect((await repository.loadAll()).single.name, 'Changed');
    await repository.remove('g1');
    expect(await repository.loadAll(), isEmpty);
  });
}
