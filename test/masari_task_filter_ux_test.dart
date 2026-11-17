import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/screens/masari_task_filter_summary.dart';
import 'package:moodle_reminder/services/deadline_filters.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  test('task filters apply to active and completed tasks equally', () {
    final tasks = [
      Deadline(uid: 'a', title: 'Read book', course: 'Math', due: DateTime(2030)),
      Deadline(uid: 'b', title: 'Write essay', course: 'English', due: DateTime(2030)),
    ];
    final completed = [
      Deadline(uid: 'c', title: 'Read chapter', course: 'Math', due: DateTime(2030)),
      Deadline(uid: 'd', title: 'Read poem', course: 'English', due: DateTime(2030)),
    ];

    expect(filterDeadlines(tasks, query: 'read', course: 'Math').map((e) => e.uid), ['a']);
    expect(filterDeadlines(completed, query: 'read', course: 'Math').map((e) => e.uid), ['c']);
    expect(filterDeadlines(tasks, query: 'no match'), isEmpty);
  });

  for (final arabic in [false, true]) {
    testWidgets('filter summary shows count and resets in ${arabic ? 'RTL' : 'LTR'}', (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.light,
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: MasariTaskFilterSummary(
                arabic: arabic,
                results: 2,
                onReset: () => resetCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.text(arabic ? '2 نتائج مطابقة' : '2 matching tasks'), findsOneWidget);
      await tester.tap(find.text(arabic ? 'مسح التصفية' : 'Clear filters'));
      await tester.pump();
      expect(resetCount, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
