import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/course_import_merger.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  test('finds existing courses without case sensitivity', () {
    const old = LocalCourse(id: '1', name: 'Physics');
    const incoming = LocalCourse(id: '2', name: ' physics ');
    expect(CourseImportMerger.matching([old], incoming)?.id, '1');
  });

  test('merges links without duplicates and retains copied files', () {
    const file = CourseMaterial(
      id: 'f',
      title: 'Local PDF',
      value: '/private.pdf',
      isLink: false,
    );
    const oldLink = CourseMaterial(
      id: 'a',
      title: 'Old',
      value: 'https://example.org/1',
      isLink: true,
    );
    const repeated = CourseMaterial(
      id: 'b',
      title: 'Repeated',
      value: 'https://example.org/1',
      isLink: true,
    );
    const added = CourseMaterial(
      id: 'c',
      title: 'New',
      value: 'https://example.org/2',
      isLink: true,
    );
    const old = LocalCourse(
      id: '1',
      name: 'Physics',
      chapters: [
        CourseChapter(
          id: 'chapter1',
          name: 'Motion',
          materials: [file, oldLink],
        ),
      ],
    );
    const incoming = LocalCourse(
      id: '2',
      name: 'Physics',
      chapters: [
        CourseChapter(
          id: 'chapter2',
          name: 'motion',
          materials: [repeated, added],
        ),
        CourseChapter(id: 'chapter3', name: 'Waves'),
      ],
    );
    final merged = CourseImportMerger.merge(old, incoming);
    expect(merged.id, '1');
    expect(merged.chapters, hasLength(2));
    expect(merged.chapters.first.id, 'chapter1');
    expect(merged.chapters.first.materials.map((m) => m.id), ['f', 'a', 'c']);
    expect(merged.chapters.last.name, 'Waves');
  });
}
