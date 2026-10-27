import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/assistant_preview_service.dart';

void main() {
  group('safe assistant intent interpretation', () {
    test('understands overdue, today and next-seven-day queries', () {
      expect(
        AssistantPreviewService.interpret('اعرض مهامي المتأخرة').intent,
        AssistantIntent.overdue,
      );
      expect(
        AssistantPreviewService.interpret('مهامي اليوم').intent,
        AssistantIntent.today,
      );
      expect(
        AssistantPreviewService.interpret('Upcoming tasks this week').intent,
        AssistantIntent.nextSevenDays,
      );
    });

    test('recognizes Arabic-Indic digits but never schedules anything', () {
      final result = AssistantPreviewService.interpret('ذكّرني قبل ١٠ دقائق');
      expect(result.intent, AssistantIntent.reminderPreview);
      expect(result.reminderMinutes, 10);
      expect(
        AssistantPreviewService.interpret('Remind 2 hours before')
            .reminderMinutes,
        120,
      );
      expect(
        AssistantPreviewService.interpret('ذكرني قبل 9999 دقيقة')
            .reminderMinutes,
        isNull,
      );
      expect(
        AssistantPreviewService.interpret('ذكرني قبل عشر دقائق')
            .reminderMinutes,
        isNull,
      );
    });

    test('ambiguous and mutation commands cannot modify deadlines', () {
      expect(
        AssistantPreviewService.interpret('احذف واجب الفيزياء').intent,
        AssistantIntent.unsupported,
      );
      expect(
        AssistantPreviewService.interpret('غير موعد الاختبار').intent,
        AssistantIntent.unsupported,
      );
      expect(
        AssistantPreviewService.interpret('متى موعد الفيزياء؟').intent,
        AssistantIntent.unsupported,
      );
      expect(
        AssistantPreviewService.interpret('  ').intent,
        AssistantIntent.unsupported,
      );
    });

    test('filters cancelled events and uses local calendar days', () {
      final now = DateTime(2030, 3, 10, 12);
      final entries = [
        Deadline(
          uid: 'old',
          title: 'Overdue',
          due: now.subtract(const Duration(days: 1)),
        ),
        Deadline(
          uid: 'today',
          title: 'Today',
          due: now.add(const Duration(hours: 1)),
        ),
        Deadline(
          uid: 'cancelled',
          title: 'Cancelled',
          due: now.add(const Duration(hours: 2)),
          status: 'CANCELLED',
        ),
        Deadline(
          uid: 'week',
          title: 'Later',
          due: now.add(const Duration(days: 6)),
        ),
        Deadline(
          uid: 'later',
          title: 'Outside window',
          due: now.add(const Duration(days: 8)),
        ),
      ];
      expect(
        AssistantPreviewService.matchingDeadlines(
          entries,
          AssistantIntent.overdue,
          now: now,
        ).map((e) => e.uid),
        ['old'],
      );
      expect(
        AssistantPreviewService.matchingDeadlines(
          entries,
          AssistantIntent.today,
          now: now,
        ).map((e) => e.uid),
        ['today'],
      );
      expect(
        AssistantPreviewService.matchingDeadlines(
          entries,
          AssistantIntent.nextSevenDays,
          now: now,
        ).map((e) => e.uid),
        ['today', 'week'],
      );
    });

    test('never returns deadlines for unknown or reminder intents', () {
      final tasks = [
        Deadline(uid: 'x', title: 'Task', due: DateTime(2030, 1, 1)),
      ];
      for (final intent in [
        AssistantIntent.unsupported,
        AssistantIntent.reminderPreview,
      ]) {
        expect(
          AssistantPreviewService.matchingDeadlines(
            tasks,
            intent,
            now: DateTime(2030, 1, 1),
          ),
          isEmpty,
        );
      }
    });
  });
}
