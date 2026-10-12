import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/deadline.dart';

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
    final data = await _request('core_webservice_get_site_info');
    return data;
  }

  /// Retrieves courses available to the authenticated user.
  Future<List<Map<String, dynamic>>> courses(int userId) async {
    final data = await _request('core_enrol_get_users_courses', {
      'userid': '$userId',
    });
    if (data is! List) {
      throw const MoodleApiException('Unexpected Moodle course response');
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Retrieves available assignment deadlines for enrolled courses.
  Future<List<Deadline>> assignments(List<int> courseIds) async {
    if (courseIds.isEmpty) return const [];
    final data = await _request('mod_assign_get_assignments', {
      for (var index = 0; index < courseIds.length; index++)
        'courseids[$index]': '${courseIds[index]}',
    });
    if (data is! Map || data['courses'] is! List) {
      throw const MoodleApiException('Unexpected Moodle assignments response');
    }
    final deadlines = <Deadline>[];
    for (final rawCourse in data['courses'] as List) {
      if (rawCourse is! Map) continue;
      final course = Map<String, dynamic>.from(rawCourse);
      final courseId = (course['id'] as num?)?.toInt();
      final courseName = course['fullname'] as String? ?? '';
      final tasks = course['assignments'];
      if (courseId == null || tasks is! List) continue;
      for (final raw in tasks) {
        if (raw is! Map) continue;
        final assignment = Map<String, dynamic>.from(raw);
        final id = (assignment['id'] as num?)?.toInt();
        final due = (assignment['duedate'] as num?)?.toInt() ?? 0;
        if (id == null || due <= 0) continue;
        deadlines.add(
          Deadline(
            uid: 'moodle-api:$courseId:$id',
            title: assignment['name'] as String? ?? '',
            course: courseName,
            due: DateTime.fromMillisecondsSinceEpoch(due * 1000),
            url: baseUrl
                .resolve('mod/assign/view.php?id=${assignment['cmid'] ?? ''}')
                .toString(),
          ),
        );
      }
    }
    return deadlines..sort((a, b) => a.due.compareTo(b.due));
  }

  Future<dynamic> _request(
    String function, [
    Map<String, String> arguments = const {},
  ]) async {
    final root = baseUrl.toString().endsWith('/')
        ? baseUrl
        : Uri.parse('${baseUrl.toString()}/');
    final endpoint = root.resolve('webservice/rest/server.php');
    final response = await _client
        .post(
          endpoint,
          body: {
            'wstoken': token,
            'wsfunction': function,
            ...arguments,
            'moodlewsrestformat': 'json',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const MoodleApiException('Moodle API request failed');
    }
    final result = jsonDecode(response.body);
    if (result is! Map && result is! List) {
      throw const MoodleApiException('Unexpected Moodle API response');
    }
    final data = result is Map ? Map<String, dynamic>.from(result) : result;
    if (data is Map &&
        (data.containsKey('exception') || data.containsKey('errorcode'))) {
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
