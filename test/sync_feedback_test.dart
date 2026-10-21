import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/sync_feedback.dart';

void main() {
  test('Moodle calendar failure is translated for Arabic users', () {
    const error = 'Could not sync Moodle. Check your connection and calendar URL.';

    expect(
      SyncFeedback.errorMessage(error, arabic: true),
      'تعذّرت مزامنة Moodle. تحقّق من اتصال الإنترنت ورابط التقويم.',
    );
    expect(SyncFeedback.errorMessage(error, arabic: false), error);
  });

  test('Moodle API failure is translated separately', () {
    expect(
      SyncFeedback.errorMessage(
        'Could not sync Moodle API. Check your connection.',
        arabic: true,
      ),
      contains('بيانات الدخول'),
    );
  });

  test('unexpected server errors remain intact for troubleshooting', () {
    expect(
      SyncFeedback.errorMessage('HTTP 403', arabic: true),
      'HTTP 403',
    );
  });

  test('offline hint checks cached deadlines, not last sync timestamp', () {
    expect(
      SyncFeedback.offlineHint(hasSavedDeadlines: true, arabic: true),
      'تبقى المواعيد المحفوظة متاحة دون إنترنت.',
    );
    expect(
      SyncFeedback.offlineHint(hasSavedDeadlines: false, arabic: true),
      'لا توجد مواعيد محفوظة على الجهاز بعد.',
    );
  });
}
