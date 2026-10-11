import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/study_insights.dart';

void main() {
  final monday = DateTime(2030, 1, 7);
  final a = Deadline(uid: 'a', title: 'Math', due: DateTime(2030, 1, 8, 9));
  final b = Deadline(uid: 'b', title: 'Physics', due: DateTime(2030, 1, 8, 9));
  final c = Deadline(uid: 'c', title: 'Essay', due: DateTime(2030, 1, 9));

  test('weekly overview starts Monday and includes seven days', () {
    final week = StudyInsights.week([a, b, c], monday);
    expect(week.length, 7);
    expect(week.keys.first, monday);
    expect(week[DateTime(2030, 1, 8)], [a, b]);
    expect(week[DateTime(2030, 1, 9)], [c]);
  });

  test('conflicts require identical due instants', () {
    expect(StudyInsights.conflicts([a, b, c]), [
      [a, b],
    ]);
    expect(StudyInsights.conflicts([a, c]), isEmpty);
  });

  test('completion rate handles empty and partial lists', () {
    expect(StudyInsights.completionRate(0, 0), 0);
    expect(StudyInsights.completionRate(2, 4), 0.5);
    expect(StudyInsights.completionRate(4, 4), 1);
  });
}
