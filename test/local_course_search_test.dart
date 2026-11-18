import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/local_course_library.dart';
import 'package:moodle_reminder/services/local_course_search.dart';

void main() {
  final notes = CourseMaterial(
    id: 'file',
    title: 'Lecture Notes',
    value: '/data/notes.pdf',
    isLink: false,
  );
  final web = CourseMaterial(
    id: 'url',
    title: 'Reference Link',
    value: 'https://example.com',
    isLink: true,
  );
  final science = LocalCourse(
    id: 'course-1',
    name: 'Physics',
    chapters: [
      CourseChapter(id: 'chapter-1', name: 'Motion', materials: [notes, web]),
    ],
  );
  final math = LocalCourse(id: 'course-2', name: 'Math');

  test('search matches course names without changing order or objects', () {
    final courses = [math, science];
    final result = searchLocalCourses(courses, '  PHYS ');
    expect(result.map((course) => course.id).toList(), ['course-1']);
    expect(courses.map((course) => course.id).toList(), [
      'course-2',
      'course-1',
    ]);
    expect(identical(result.single, science), isTrue);
  });

  test('search finds chapters and materials without hiding their siblings', () {
    for (final query in ['motion', 'lecture', 'reference']) {
      final result = searchLocalCourses([math, science], query);
      expect(result.map((course) => course.id).toList(), ['course-1']);
      expect(result.single.chapters.single.materials.length, 2);
    }
  });

  test('empty search keeps all courses and matches no hidden values', () {
    expect(searchLocalCourses([math, science], '  ').length, 2);
    expect(searchLocalCourses([math, science], 'not-found'), isEmpty);
    expect(searchLocalCourses([], 'physics'), isEmpty);
    expect(localCourseMaterialCount(science), 2);
    expect(localCourseMaterialCount(math), 0);
  });
}
