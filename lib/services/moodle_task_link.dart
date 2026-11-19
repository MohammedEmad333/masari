import '../models/deadline.dart';

/// Safe Moodle activity and event URLs only. Never expose private calendar
/// subscription links or credential-bearing links from task metadata.
class MoodleTaskLink {
  const MoodleTaskLink._();

  static Uri? resolve(Deadline deadline) {
    final direct = _safeTaskPage(deadline.url);
    if (direct != null) return direct;

    // Some ICS feeds omit URL but include direct links in DESCRIPTION.
    final matches = RegExp(
      r'https?://[^\s<>"]+',
      caseSensitive: false,
    ).allMatches(deadline.description);
    for (final match in matches) {
      final value = match.group(0);
      if (value == null) continue;
      final candidate = value.replaceAll(RegExp(r"[.,;)']+$"), '');
      final uri = _safeTaskPage(candidate);
      if (uri != null) return uri;
    }
    return null;
  }

  static Uri? _safeTaskPage(String value) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }

    final path = uri.path.toLowerCase();
    final isActivity = RegExp(r'/mod/[a-z0-9_]+/view\.php$').hasMatch(path);
    final isCourse = path.endsWith('/course/view.php');
    final isCalendar =
        path.endsWith('/calendar/view.php') ||
        path.endsWith('/calendar/event.php');
    if (!isActivity && !isCourse && !isCalendar) return null;

    final hasId =
        (uri.queryParameters['id']?.trim().isNotEmpty ?? false) ||
        (isCalendar &&
            (uri.queryParameters['eventid']?.trim().isNotEmpty ?? false));
    if (!hasId) return null;

    const blocked = {
      'token',
      'authtoken',
      'wstoken',
      'sesskey',
      'access_token',
      'password',
      'key',
    };
    if (uri.queryParameters.keys.any(
      (key) => blocked.contains(key.toLowerCase()),
    )) {
      return null;
    }
    return uri;
  }
}
