import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  late Directory sandbox;
  late LocalCourseLibrary library;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('moodle-course-test-');
    library = LocalCourseLibrary(sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('persists courses, chapters and links', () async {
    final link = library.createLink('Lecture', 'https://example.edu/video');
    final chapters = [
      CourseChapter(id: library.newId(), name: 'Chapter 1', materials: [link]),
    ];
    await library.save([
      LocalCourse(id: library.newId(), name: 'Math', chapters: chapters),
    ]);
    final loaded = await library.load();
    expect(loaded.single.name, 'Math');
    expect(loaded.single.chapters.single.materials.single.title, 'Lecture');
    expect(loaded.single.chapters.single.materials.single.isLink, isTrue);
  });

  test('copies imported files into app-owned storage independently', () async {
    final original = File('${sandbox.path}/original.pdf');
    await original.writeAsString('first');
    final material = await library.importFile(original.path, 'lecture.pdf');
    await original.delete();
    expect(await File(material.value).readAsString(), 'first');
    await library.deleteMaterial(material);
    expect(await File(material.value).exists(), isFalse);
  });

  test('rejects non-http links and embedded credentials', () {
    expect(
      () => library.createLink('Bad', 'javascript:alert(1)'),
      throwsFormatException,
    );
    expect(
      () => library.createLink('Bad', 'https://user:pass@example.edu/'),
      throwsFormatException,
    );
  });

  test('cannot delete unrelated files from outside library', () async {
    final other = File('${sandbox.path}/keep.txt');
    await other.writeAsString('important');
    await library.deleteMaterial(
      CourseMaterial(id: 'external', title: 'external', value: other.path, isLink: false),
    );
    expect(await other.exists(), isTrue);
  });
}
