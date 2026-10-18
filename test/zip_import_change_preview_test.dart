import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/local_course_library.dart';
import 'package:moodle_reminder/services/zip_import_change_preview.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zip-diff-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('previews duplicates and new versions without copying files', () async {
    final original = File('${dir.path}/old.pdf');
    await original.writeAsString('first');
    final current = LocalCourse(
      id: 'course',
      name: 'Physics',
      chapters: [
        CourseChapter(
          id: 'chapter',
          name: 'Motion',
          materials: [
            CourseMaterial(
              id: 'file',
              title: 'Lecture.pdf',
              value: original.path,
              isLink: false,
            ),
            const CourseMaterial(
              id: 'url',
              title: 'Video',
              value: 'https://example.org/a',
              isLink: true,
            ),
          ],
        ),
      ],
    );
    final data = jsonEncode({
      'v': 1,
      'name': 'Physics',
      'chapters': [
        {
          'name': 'Motion',
          'resources': [
            {'title': 'Copy.pdf', 'file': 'files/1'},
            {'title': 'Lecture.pdf', 'file': 'files/2'},
            {'title': 'Video', 'url': 'https://example.org/a'},
            {'title': 'New', 'url': 'https://example.org/b'},
          ],
        },
        {'name': 'Extra', 'resources': <Object>[]},
      ],
    });
    final archive = Archive()
      ..addFile(
        ArchiveFile('course.json', utf8.encode(data).length, utf8.encode(data)),
      )
      ..addFile(ArchiveFile('files/1', 5, utf8.encode('first')))
      ..addFile(ArchiveFile('files/2', 6, utf8.encode('second')));
    final zip = File('${dir.path}/bundle.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final preview = await ZipImportChangePreview.inspect(zip, current);
    expect(preview.newChapters, 1);
    expect(preview.duplicateFiles, 1);
    expect(preview.changedFiles, 1);
    expect(preview.newFiles, 0);
    expect(preview.newLinks, 1);
    expect(await original.readAsString(), 'first');
  });
}
