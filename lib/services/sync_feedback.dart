/// Human-readable feedback for Moodle synchronization failures.
/// The task cache and the last successful iCalendar sync are independent.
class SyncFeedback {
  const SyncFeedback._();

  static String errorMessage(String raw, {required bool arabic}) {
    if (!arabic) return raw;
    if (raw.startsWith('Moodle returned an HTML page instead of')) {
      return 'أرجع Moodle صفحة ويب بدل ملف التقويم. '
          'استخدم رابط الاشتراك الخاص بالتقويم وليس صفحة الدخول أو التصدير.';
    }
    return switch (raw.trim()) {
      'Could not sync Moodle. Check your connection and calendar URL.' =>
        'تعذّرت مزامنة Moodle. تحقّق من اتصال الإنترنت ورابط التقويم.',
      'Could not sync Moodle API. Check your connection.' =>
        'تعذّرت مزامنة Moodle API. تحقّق من الاتصال وبيانات الدخول.',
      'Add your Moodle calendar URL first.' => 'أضف رابط تقويم Moodle أولاً.',
      'The URL did not return a valid iCalendar feed.' =>
        'الرابط لم يُرجع ملف تقويم iCalendar صالحًا.',
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
