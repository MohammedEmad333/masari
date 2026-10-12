import 'dart:convert';

import 'package:http/http.dart' as http;

/// Optional read-only Moodle Web Services client.
///
/// Requires a token provisioned by the Moodle administrator/user.
/// iCalendar sync remains fully independent of this client.
class MoodleApiClient {
  MoodleApiClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (baseUrl.scheme != 'https' || !baseUrl.hasAuthority) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Moodle API requires HTTPS',
      );
    }
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token is required');
    }
  }

  final Uri baseUrl;
  final String token;
  final http.Client _client;

  Future<Map<String, dynamic>> siteInfo() async {
    final endpoint = baseUrl.resolve('webservice/rest/server.php');
    final response = await _client
        .post(
          endpoint,
          body: {
            'wstoken': token,
            'wsfunction': 'core_webservice_get_site_info',
            'moodlewsrestformat': 'json',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const MoodleApiException('Moodle API request failed');
    }
    final result = jsonDecode(response.body);
    if (result is! Map) {
      throw const MoodleApiException('Unexpected Moodle API response');
    }
    final data = Map<String, dynamic>.from(result);
    if (data.containsKey('exception') || data.containsKey('errorcode')) {
      throw const MoodleApiException('Moodle rejected the API credentials');
    }
    return data;
  }

  void close() => _client.close();
}

class MoodleApiException implements Exception {
  const MoodleApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
