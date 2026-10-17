import 'dart:convert';

import 'local_course_library.dart';

/// Portable course link: course name, chapter names and web links only.
/// Local file paths and user credentials must never be serialized.
class CourseShareCodec {
  const CourseShareCodec._();

  static const scheme = 'moodlereminder';
  static const maxLinkLength = 32000;
  static const maxChapters = 100;
  static const maxMaterials = 500;

  static String encode(LocalCourse course) {
    final payload = <String, Object>{
      'v': 1,
      'name': course.name,
      'chapters': [
        for (final chapter in course.chapters)
          {
            'name': chapter.name,
            'links': [
              for (final item in chapter.materials)
                if (item.isLink) {'title': item.title, 'url': item.value},
            ],
          },
      ],
    };
    final data = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    final uri = Uri(
      scheme: scheme,
      host: 'course',
      queryParameters: {'data': data},
    );
    if (uri.toString().length > maxLinkLength) {
      throw const FormatException(
        'Course has too many links to share in one URL',
      );
    }
    return uri.toString();
  }

  static LocalCourse decode(String raw, LocalCourseLibrary library) {
    if (raw.length > maxLinkLength)
      throw const FormatException('Share link is too long');
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != scheme ||
        uri.host != 'course' ||
        uri.path.isNotEmpty ||
        uri.queryParameters.length != 1 ||
        !uri.queryParameters.containsKey('data')) {
      throw const FormatException('Not a Moodle Reminder course link');
    }
    final token = uri.queryParameters['data']!;
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token))),
    );
    if (decoded is! Map || decoded['v'] != 1)
      throw const FormatException('Unsupported course link');
    final name = _text(decoded['name']);
    final chapters = decoded['chapters'];
    if (chapters is! List || chapters.length > maxChapters)
      throw const FormatException('Invalid chapters');
    var count = 0;
    return LocalCourse(
      id: library.newId(),
      name: name,
      chapters: [
        for (final rawChapter in chapters)
          if (rawChapter is Map && rawChapter['links'] is List)
            CourseChapter(
              id: library.newId(),
              name: _text(rawChapter['name']),
              materials: [
                for (final rawLink in rawChapter['links'] as List)
                  if (rawLink is Map) _material(rawLink, library, ++count),
              ],
            )
          else
            throw const FormatException('Invalid chapter'),
      ],
    );
  }

  static CourseMaterial _material(
    Map<dynamic, dynamic> value,
    LocalCourseLibrary library,
    int number,
  ) {
    if (number > maxMaterials) throw const FormatException('Too many links');
    return library.createLink(_text(value['title']), _text(value['url']));
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 250) {
      throw const FormatException('Invalid name or link');
    }
    return value.trim();
  }
}
