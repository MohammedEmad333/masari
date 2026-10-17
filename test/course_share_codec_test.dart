import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/course_share_codec.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  late Directory temp;
  late LocalCourseLibrary library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('course-share-');
    library = LocalCourseLibrary(temp);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('round-trip course chapters and URLs but never local file paths', () {
    final course = LocalCourse(
      id: 'old',
      name: 'Physics',
      chapters: [
        CourseChapter(
          id: 'chapter-old',
          name: 'Motion',
          materials: [
            const CourseMaterial(
              id: 'file',
              title: 'private.pdf',
              value: '/storage/private/user-document.pdf',
              isLink: false,
            ),
            const CourseMaterial(
              id: 'link',
              title: 'Lecture',
              value: 'https://example.edu/lecture',
              isLink: true,
            ),
          ],
        ),
      ],
    );
    final uri = CourseShareCodec.encode(course);
    expect(uri, startsWith('moodlereminder://course?'));
    expect(uri, isNot(contains('/storage/private')));
    final imported = CourseShareCodec.decode(uri, library);
    expect(imported.id, isNot(course.id));
    expect(imported.name, course.name);
    expect(imported.chapters.single.name, 'Motion');
    expect(imported.chapters.single.materials.single.title, 'Lecture');
    expect(
      imported.chapters.single.materials.single.value,
      'https://example.edu/lecture',
    );
  });

  test('rejects invalid and oversized links', () {
    expect(
      () => CourseShareCodec.decode('https://example.org', library),
      throwsFormatException,
    );
    expect(
      () => CourseShareCodec.decode('x' * 32001, library),
      throwsFormatException,
    );
  });
}
