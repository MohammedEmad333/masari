import 'moodle_browser_login.dart';

/// Accepts only Moodle's subscription URL for the *same* university origin.
/// The token stays on-device and is never sent to any third-party service.
class MoodleCalendarLink {
  const MoodleCalendarLink._();

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
