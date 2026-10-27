import '../models/deadline.dart';

/// A deliberately local, read-only assistant prototype.
///
/// No model credentials, Moodle calendar tokens, or task data leave the device.
enum AssistantIntent {
  today,
  overdue,
  nextSevenDays,
  reminderPreview,
  unsupported,
}

class AssistantInterpretation {
  const AssistantInterpretation(this.intent, {this.reminderMinutes});

  final AssistantIntent intent;
  final int? reminderMinutes;
}

class AssistantPreviewService {
  const AssistantPreviewService._();

  static AssistantInterpretation interpret(String input) {
    final text = _normalize(input);
    if (text.isEmpty) {
      return const AssistantInterpretation(AssistantIntent.unsupported);
    }

    if (_containsAny(text, [
      'ذكرني',
      'ذكريني',
      'تذكير',
      'تنبيه',
      'remind',
      'reminder',
    ])) {
      return AssistantInterpretation(
        AssistantIntent.reminderPreview,
        reminderMinutes: _extractMinutes(text),
      );
    }

    // Never reinterpret deletion or rescheduling as a read-only query.
    if (_containsAny(text, [
      'احذف',
      'الغ',
      'امسح',
      'غير موعد',
      'عدل موعد',
      'delete',
      'cancel',
      'reschedule',
      'edit',
    ])) {
      return const AssistantInterpretation(AssistantIntent.unsupported);
    }

    if (_containsAny(text, ['متاخر', 'فاتت', 'overdue', 'late tasks'])) {
      return const AssistantInterpretation(AssistantIntent.overdue);
    }
    if (_containsAny(text, ['اليوم', 'today'])) {
      return const AssistantInterpretation(AssistantIntent.today);
    }
    if (_containsAny(text, [
      'القادم',
      'القادمه',
      'الاسبوع',
      'next',
      'upcoming',
      'week',
    ])) {
      return const AssistantInterpretation(AssistantIntent.nextSevenDays);
    }
    return const AssistantInterpretation(AssistantIntent.unsupported);
  }

  static List<Deadline> matchingDeadlines(
    List<Deadline> deadlines,
    AssistantIntent intent, {
    required DateTime now,
  }) {
    if (intent != AssistantIntent.today &&
        intent != AssistantIntent.overdue &&
        intent != AssistantIntent.nextSevenDays) {
      return const [];
    }
    final localNow = now.toLocal();
    final cutoff = now.add(const Duration(days: 7));
    final matching = deadlines.where((deadline) {
      if (_cancelled(deadline.status)) return false;
      final due = deadline.due;
      switch (intent) {
        case AssistantIntent.today:
          final local = due.toLocal();
          return local.year == localNow.year &&
              local.month == localNow.month &&
              local.day == localNow.day;
        case AssistantIntent.overdue:
          return due.isBefore(now);
        case AssistantIntent.nextSevenDays:
          return !due.isBefore(now) && due.isBefore(cutoff);
        case AssistantIntent.reminderPreview:
        case AssistantIntent.unsupported:
          return false;
      }
    }).toList()..sort((a, b) => a.due.compareTo(b.due));
    return List.unmodifiable(matching);
  }

  static bool _cancelled(String status) {
    final value = _normalize(status);
    return value.contains('cancelled') ||
        value.contains('canceled') ||
        value.contains('ملغي') ||
        value.contains('ملغاه');
  }

  static int? _extractMinutes(String text) {
    final match = RegExp(
      r'(?:قبل|before)\s+(\d{1,4})\s*(دقيق\S*|minute\S*|min\b|ساع\S*|hour\S*)',
    ).firstMatch(text);
    if (match == null) return null;
    final count = int.tryParse(match.group(1)!);
    if (count == null) return null;
    final unit = match.group(2)!;
    final minutes = (unit.startsWith('ساع') || unit.startsWith('hour'))
        ? count * 60
        : count;
    if (minutes < 1 || minutes > 1440) return null;
    return minutes;
  }

  static bool _containsAny(String text, List<String> options) {
    return options.any(text.contains);
  }

  static String _normalize(String text) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    final output = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      final arabic = arabicDigits.indexOf(character);
      final persian = persianDigits.indexOf(character);
      if (arabic >= 0) {
        output.write(arabic);
      } else if (persian >= 0) {
        output.write(persian);
      } else if (RegExp(r'[\u064b-\u065f\u0670]').hasMatch(character)) {
        continue;
      } else {
        output.write(character
            .replaceAll('أ', 'ا')
            .replaceAll('إ', 'ا')
            .replaceAll('آ', 'ا')
            .replaceAll('ة', 'ه')
            .replaceAll('ى', 'ي'));
      }
    }
    return output.toString().trim();
  }
}
