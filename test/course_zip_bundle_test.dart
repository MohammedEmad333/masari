import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/course_zip_bundle.dart';
import 'package:moodle_reminder/services/local_course_library.dart';

void main() {
  late Directory sandbox;
  late LocalCourseLibrary library;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('course-zip-test-');
    library = LocalCourseLibrary(sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('imports chapters, links and files into app-owned storage', () async {
    final manifest = jsonEncode({
      'v': 1,
      'name': 'Physics',
      'chapters': [
        {
          'name': 'Motion',
          'resources': [
            {'title': 'Lecture.pdf', 'file': 'files/1'},
            {'title': 'Video', 'url': 'https://example.edu/video'},
          ],
        },
      ],
    });
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'course.json',
          utf8.encode(manifest).length,
          utf8.encode(manifest),
        ),
      )
      ..addFile(ArchiveFile('files/1', 4, utf8.encode('test')));
    final zip = File('${sandbox.path}/course.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final result = await CourseZipBundle.importCourse(zip, library);
    expect(result.name, 'Physics');
    expect(result.chapters.single.materials, hasLength(2));
    final file = result.chapters.single.materials.first;
    expect(file.isLink, isFalse);
    expect(await File(file.value).readAsString(), 'test');
    expect(
      result.chapters.single.materials.last.value,
      'https://example.edu/video',
    );
  });

  test('rejects invalid ZIP paths before touching storage', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('../outside', 3, utf8.encode('bad')));
    final zip = File('${sandbox.path}/bad.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    expect(
      () => CourseZipBundle.importCourse(zip, library),
      throwsFormatException,
    );
  });
}
