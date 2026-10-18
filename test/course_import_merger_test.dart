import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/course_import_merger.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  const localFile = CourseMaterial(
    id: 'f',
    title: 'Notes',
    value: '/private/notes.pdf',
    isLink: false,
  );
  const oldLink = CourseMaterial(
    id: 'l1',
    title: 'Old',
    value: 'https://example.org/one',
    isLink: true,
  );
  const newLink = CourseMaterial(
    id: 'l2',
    title: 'New',
    value: 'https://example.org/two',
    isLink: true,
  );
  final existing = LocalCourse(
    id: 'original',
    name: 'Physics',
    chapters: [
      CourseChapter(
        id: 'old-chapter',
        name: 'Chapter 1',
        materials: [localFile, oldLink],
      ),
    ],
  );
  final incoming = LocalCourse(
    id: 'shared',
    name: ' PHYSICS ',
    chapters: [
      CourseChapter(
        id: 'new-chapter',
        name: ' chapter 1 ',
        materials: [oldLink, newLink],
      ),
      const CourseChapter(id: 'chapter-2', name: 'Chapter 2'),
    ],
  );

  test('ZIP merge keeps existing file and appends only new attachments', () {
    const updatedFile = CourseMaterial(
      id: 'imported-file',
      title: ' Notes ',
      value: '/tmp/duplicate.pdf',
      isLink: false,
    );
    const extraFile = CourseMaterial(
      id: 'extra-file',
      title: 'Slides',
      value: '/tmp/slides.pdf',
      isLink: false,
    );
    final zip = LocalCourse(
      id: 'zip',
      name: 'Physics',
      chapters: [
        const CourseChapter(
          id: 'zip-chapter',
          name: 'Chapter 1',
          materials: [updatedFile, extraFile, newLink],
        ),
      ],
    );
    final merged = CourseImportMerger.mergeZip(existing, zip);
    expect(merged.id, 'original');
    expect(merged.chapters.single.id, 'old-chapter');
    expect(merged.chapters.single.materials.map((item) => item.id), [
      'f',
      'l1',
      'extra-file',
      'l2',
    ]);
    expect(
      CourseImportMerger.mergeZip(merged, zip).chapters.single.materials,
      hasLength(4),
    );
  });

  test('finds a case-insensitive existing course', () {
    expect(CourseImportMerger.findMatch([existing], incoming)?.id, 'original');
  });

  test(
    'merges missing links and chapters, preserving local copies and IDs',
    () {
      final updated = CourseImportMerger.merge(existing, incoming);
      expect(updated.id, 'original');
      expect(updated.chapters, hasLength(2));
      expect(updated.chapters.first.id, 'old-chapter');
      expect(updated.chapters.first.materials.map((m) => m.id), [
        'f',
        'l1',
        'l2',
      ]);
      expect(updated.chapters.last.name, 'Chapter 2');
      expect(
        CourseImportMerger.merge(updated, incoming).chapters.first.materials,
        hasLength(3),
      );
    },
  );
}
