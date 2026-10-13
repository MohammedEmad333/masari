import 'package:http/http.dart' as http;

import 'moodle_browser_login.dart';

/// Anonymous checks cannot establish token issuance or course permissions.
class MoodleCompatibilityResult {
  const MoodleCompatibilityResult({
    required this.loginReachable,
    required this.apiEndpointReachable,
  });

  final bool loginReachable;
  final bool apiEndpointReachable;
}

class MoodleCompatibilityChecker {
  MoodleCompatibilityChecker({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<MoodleCompatibilityResult> check(String url) async {
    final login = MoodleBrowserLogin.universityLoginUrl(url);
    if (login == null) {
      throw const FormatException('Enter a valid Moodle HTTPS server URL.');
    }
    final root = login.resolve('../');
    final loginReachable = await _probe(login);
    final apiEndpointReachable = await _probe(
      root.resolve('webservice/rest/server.php'),
    );
    return MoodleCompatibilityResult(
      loginReachable: loginReachable,
      apiEndpointReachable: apiEndpointReachable,
    );
  }

  Future<bool> _probe(Uri url) async {
    try {
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 10));
      // 401/403 may be access restrictions; 404 indicates not found.
      return response.statusCode != 404 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
