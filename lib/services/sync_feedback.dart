/// Human-readable feedback for Moodle synchronization failures.
/// The task cache and the last successful iCalendar sync are independent.
class SyncFeedback {
  const SyncFeedback._();

  static String errorMessage(String raw, {required bool arabic}) {
    if (!arabic) return raw;
    return switch (raw.trim()) {
      'Could not sync Moodle. Check your connection and calendar URL.' =>
        'تعذّرت مزامنة Moodle. تحقّق من اتصال الإنترنت ورابط التقويم.',
      'Could not sync Moodle API. Check your connection.' =>
        'تعذّرت مزامنة Moodle API. تحقّق من الاتصال وبيانات الدخول.',
      'Add your Moodle calendar URL first.' =>
        'أضف رابط تقويم Moodle أولاً.',
      'Could not connect the first Moodle calendar.' =>
        'تعذّر الاتصال بأول تقويم Moodle. تحقّق من الرابط.',
      _ => raw,
    };
  }

  static String offlineHint({
    required bool hasSavedDeadlines,
    required bool arabic,
  }) {
    if (hasSavedDeadlines) {
      return arabic
          ? 'تبقى المواعيد المحفوظة متاحة دون إنترنت.'
          : 'Saved deadlines remain available offline.';
    }
    return arabic
        ? 'لا توجد مواعيد محفوظة على الجهاز بعد.'
        : 'There are no deadlines saved on this device yet.';
  }
}
