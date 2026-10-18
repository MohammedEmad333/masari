import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/course_file_hash_merger.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('course-content-dedup-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('same content with different names is deduplicated', () async {
    final oldFile = File('${dir.path}/existing.pdf');
    final newFile = File('${dir.path}/renamed.pdf');
    await oldFile.writeAsString('identical bytes');
    await newFile.writeAsString('identical bytes');
    final existing = LocalCourse(id: 'existing', name: 'Math', chapters: [
      CourseChapter(id: 'chapter', name: 'Chapter 1', materials: [
        CourseMaterial(id: 'old', title: 'Original.pdf', value: oldFile.path, isLink: false),
      ]),
    ]);
    final incoming = LocalCourse(id: 'import', name: 'Math', chapters: [
      CourseChapter(id: 'incoming', name: 'chapter 1', materials: [
        CourseMaterial(id: 'new', title: 'Renamed.pdf', value: newFile.path, isLink: false),
      ]),
    ]);
    final merged = await CourseFileHashMerger.merge(existing, incoming);
    expect(merged.id, 'existing');
    expect(merged.chapters.single.id, 'chapter');
    expect(merged.chapters.single.materials.map((m) => m.id), ['old']);
  });

  test('different content with same name keeps both revisions', () async {
    final oldFile = File('${dir.path}/old.pdf');
    final newFile = File('${dir.path}/new.pdf');
    await oldFile.writeAsString('first version');
    await newFile.writeAsString('second version');
    final existing = LocalCourse(id: 'c', name: 'Math', chapters: [
      CourseChapter(id: 'ch', name: 'One', materials: [
        CourseMaterial(id: 'a', title: 'Lecture.pdf', value: oldFile.path, isLink: false),
      ]),
    ]);
    final incoming = LocalCourse(id: 'other', name: 'Math', chapters: [
      CourseChapter(id: 'ch2', name: 'One', materials: [
        CourseMaterial(id: 'b', title: 'Lecture.pdf', value: newFile.path, isLink: false),
      ]),
    ]);
    final merged = await CourseFileHashMerger.merge(existing, incoming);
    expect(merged.chapters.single.materials.map((m) => m.id), ['a', 'b']);
  });
}
