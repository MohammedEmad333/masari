import 'moodle_browser_login.dart';

/// Accepts only Moodle's subscription URL for the *same* university origin.
/// The token stays on-device and is never sent to any third-party service.
class MoodleCalendarLink {
  const MoodleCalendarLink._();

  /// Prefer Moodle's wider custom export window without modifying its token.
  /// Other calendar providers and ordinary ICS URLs remain unchanged.
  static String preferCustomPeriod(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !uri.path.endsWith('/calendar/export_execute.php') ||
        !uri.queryParameters.containsKey('authtoken')) {
      return value;
    }
    if (uri.queryParameters['preset_time'] == 'custom') return value;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'preset_time': 'custom',
    }).toString();
  }

  static Uri? exportPage(String moodleServer) {
    final login = MoodleBrowserLogin.universityLoginUrl(moodleServer);
    return login?.resolve('../calendar/export.php');
  }

  static String? fromBrowser(String? value, String moodleServer) {
    final exportPageUri = exportPage(moodleServer);
    final candidate = Uri.tryParse(value?.trim() ?? '');
    if (exportPageUri == null ||
        candidate == null ||
        candidate.scheme != 'https' ||
        candidate.host != exportPageUri.host ||
        candidate.port != exportPageUri.port ||
        candidate.userInfo.isNotEmpty ||
        candidate.hasFragment ||
        candidate.path != exportPageUri.resolve('export_execute.php').path ||
        (candidate.queryParameters['authtoken']?.isEmpty ?? true)) {
      return null;
    }
    return candidate.toString();
  }
}
