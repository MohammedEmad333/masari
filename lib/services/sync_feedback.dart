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
    if (raw.startsWith('Moodle rejected the private calendar authorization.')) {
      return 'رفض Moodle صلاحية رابط التقويم الخاص. أنشئ رابط اشتراك جديدًا من صفحة تصدير التقويم.';
    }
    if (raw.startsWith('Moodle returned a web page instead of iCalendar')) {
      return 'أرجع Moodle صفحة ويب بدل ملف التقويم. قد يتطلب الخادم تسجيل الدخول أو يمنع تنزيلات التطبيق.';
    }
    if (raw.startsWith('Moodle returned HTTP 200 but no iCalendar data.')) {
      return 'استجاب Moodle بنجاح لكنه لم يُرجع بيانات تقويم ICS. افحص رابط الاشتراك وإعدادات خادم الجامعة.';
    }
    if (raw.startsWith('Moodle calendar export is disabled')) {
      return 'تصدير التقويم معطّل من خادم الجامعة.';
    }
    if (raw.startsWith('Moodle returned an empty calendar response')) {
      return 'أرجع خادم Moodle استجابة فارغة بدلاً من بيانات التقويم.';
    }
    if (raw.startsWith('Moodle calendar download timed out.')) {
      return 'انتهت مهلة تنزيل تقويم Moodle. حاول مجددًا.';
    }
    if (raw.startsWith('Could not reach the Moodle server.')) {
      return 'تعذّر الوصول إلى خادم Moodle. تحقّق من الإنترنت أو عنوان الخادم.';
    }
    if (raw.startsWith('Could not download the Moodle calendar.')) {
      return 'تعذّر تنزيل تقويم Moodle. تحقّق من الاتصال بالإنترنت.';
    }
    if (raw.startsWith('Moodle returned HTTP ')) {
      final status = RegExp(r'HTTP (\d{3})').firstMatch(raw)?.group(1);
      return status == null
          ? 'أرجع خادم Moodle خطأً أثناء تنزيل التقويم.'
          : 'أرجع خادم Moodle رمز الخطأ HTTP $status. تحقّق من رابط التقويم.';
    }
    return switch (raw.trim()) {
      'Could not sync Moodle. Check your connection and calendar URL.' =>
        'تعذّرت مزامنة Moodle. تحقّق من اتصال الإنترنت ورابط التقويم.',
      'Could not sync Moodle API. Check your connection.' =>
        'تعذّرت مزامنة Moodle API. تحقّق من الاتصال وبيانات الدخول.',
      'Add your Moodle calendar URL first.' => 'أضف رابط تقويم Moodle أولاً.',
      'Enter a valid Moodle calendar URL.' =>
        'أدخل رابط تقويم Moodle صحيحًا يبدأ بـ https://.',
      'The URL did not return a valid iCalendar feed.' =>
        'الرابط لم يُرجع ملف تقويم iCalendar صالحًا.',
      'Could not connect the first Moodle calendar.' =>
        'تعذّر الاتصال بأول تقويم Moodle. تحقّق من الرابط.',
      _ => RegExp(r'^HTTP \d{3}
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
).hasMatch(raw.trim())
          ? raw.trim()
          : 'تعذّر إكمال العملية. تحقّق من الاتصال ثم حاول مجددًا.',
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
