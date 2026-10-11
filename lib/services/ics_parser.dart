import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/deadline.dart';

class IcsParser {
  IcsParser._();

  static bool _timeZonesInitialized = false;

  static List<Deadline> parse(String raw) {
    _ensureTimeZones();

    final lines = _unfold(raw).split(RegExp(r'\r?\n'));
    final parsed = <Deadline>[];

    var inEvent = false;
    final values = <String, String>{};
    final keyParts = <String, String>{};

    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        values.clear();
        keyParts.clear();
        continue;
      }

      if (line == 'END:VEVENT') {
        if (inEvent) {
          final deadline = _buildDeadline(values, keyParts);
          if (deadline != null) parsed.add(deadline);
        }
        inEvent = false;
        continue;
      }

      if (!inEvent) continue;

      final separator = line.indexOf(':');
      if (separator < 0) continue;

      final keyPart = line.substring(0, separator);
      final value = line.substring(separator + 1);
      final key = keyPart.split(';').first.toUpperCase();

      // Keep the first occurrence for the core fields Moodle exports.
      values.putIfAbsent(key, () => value);
      keyParts.putIfAbsent(key, () => keyPart);
    }

    // Moodle UIDs are stable across calendar refreshes. If a feed contains
    // multiple revisions of the same VEVENT, keep only the newest revision.
    final byStableKey = <String, Deadline>{};
    for (final deadline in parsed) {
      final key = deadline.stableKey;
      final existing = byStableKey[key];
      if (existing == null || _isNewerRevision(deadline, existing)) {
        byStableKey[key] = deadline;
      }
    }

    // A cancelled VEVENT is a tombstone. Apply revision selection first so
    // older active revisions never reappear after a newer cancellation.
    final deadlines = byStableKey.values
        .where((deadline) => deadline.status.toUpperCase() != 'CANCELLED')
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return deadlines;
  }

  static Deadline? _buildDeadline(
    Map<String, String> values,
    Map<String, String> keyParts,
  ) {
    final title = _clean(values['SUMMARY'] ?? '');
    final due =
        _parseDate(values['DTSTART'], keyParts['DTSTART']) ??
        _parseDate(values['DTEND'], keyParts['DTEND']);

    if (title.isEmpty || due == null) return null;

    return Deadline(
      uid: _clean(values['UID'] ?? ''),
      title: title,
      due: due,
      description: _clean(values['DESCRIPTION'] ?? ''),
      course: _normalizeCourse(_clean(values['CATEGORIES'] ?? '')),
      url: _clean(values['URL'] ?? ''),
      location: _clean(values['LOCATION'] ?? ''),
      status: _clean(values['STATUS'] ?? ''),
      sequence: int.tryParse((values['SEQUENCE'] ?? '').trim()) ?? 0,
      lastModified: _parseDate(
        values['LAST-MODIFIED'],
        keyParts['LAST-MODIFIED'],
      ),
    );
  }

  static bool _isNewerRevision(Deadline candidate, Deadline current) {
    if (candidate.sequence != current.sequence) {
      return candidate.sequence > current.sequence;
    }

    final candidateModified = candidate.lastModified;
    final currentModified = current.lastModified;
    if (candidateModified != null && currentModified != null) {
      return candidateModified.isAfter(currentModified);
    }
    if (candidateModified != null && currentModified == null) return true;
    if (candidateModified == null && currentModified != null) return false;

    // Some Moodle feeds don't include SEQUENCE/LAST-MODIFIED. In that case,
    // prefer the later occurrence because it is normally the latest export.
    return true;
  }

  static String _normalizeCourse(String raw) {
    if (raw.isEmpty) return '';
    final first = raw.split(',').first.trim();

    // Al-Aqsa/Moodle exports may append an internal numeric suffix such as
    // "تصميم منطق الحاسوب_176". Keep the human-readable course name only.
    return first.replaceFirst(RegExp(r'_\d+$'), '').trim();
  }

  static void _ensureTimeZones() {
    if (_timeZonesInitialized) return;
    tzdata.initializeTimeZones();
    _timeZonesInitialized = true;
  }

  static String _unfold(String raw) {
    return raw.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  }

  static String _clean(String value) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', '\\')
        .trim();
  }

  static DateTime? _parseDate(String? value, String? keyPart) {
    if (value == null || value.trim().isEmpty) return null;

    try {
      final v = value.trim();
      final params = keyPart ?? '';

      if (params.toUpperCase().contains('VALUE=DATE') ||
          (v.length == 8 && !v.contains('T'))) {
        return DateTime(
          int.parse(v.substring(0, 4)),
          int.parse(v.substring(4, 6)),
          int.parse(v.substring(6, 8)),
          23,
          59,
        );
      }

      final isUtc = v.endsWith('Z');
      final core = isUtc ? v.substring(0, v.length - 1) : v;

      final year = int.parse(core.substring(0, 4));
      final month = int.parse(core.substring(4, 6));
      final day = int.parse(core.substring(6, 8));
      final hour = int.parse(core.substring(9, 11));
      final minute = int.parse(core.substring(11, 13));
      final second = core.length >= 15 ? int.parse(core.substring(13, 15)) : 0;

      if (isUtc) {
        return DateTime.utc(year, month, day, hour, minute, second).toLocal();
      }

      final tzidMatch = RegExp(
        r'TZID=(?:"([^"]+)"|([^;:]+))',
        caseSensitive: false,
      ).firstMatch(params);
      final tzid = tzidMatch?.group(1) ?? tzidMatch?.group(2);
      if (tzid != null && tzid.isNotEmpty) {
        try {
          return tz.TZDateTime(
            tz.getLocation(tzid),
            year,
            month,
            day,
            hour,
            minute,
            second,
          ).toLocal();
        } catch (_) {
          // Fall back to the device's local timezone if the feed contains an
          // unknown/custom Moodle timezone identifier.
        }
      }

      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

String formatDue(DateTime value) =>
    DateFormat('EEE, MMM d • h:mm a').format(value);
