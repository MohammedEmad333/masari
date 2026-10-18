import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'local_course_library.dart';

/// Portable ZIP containing a JSON manifest and copies of local resources.
class CourseZipBundle {
  const CourseZipBundle._();

  static Future<File> exportCourse(LocalCourse course) async {
    final cache = await getTemporaryDirectory();
    final file = File(
      '${cache.path}/moodle-course-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(file.path);
    try {
      final chapters = <Map<String, Object>>[];
      var serial = 0;
      for (final chapter in course.chapters) {
        final resources = <Map<String, Object>>[];
        for (final item in chapter.materials) {
          if (item.isLink) {
            resources.add({'title': item.title, 'url': item.value});
          } else {
            final original = File(item.value);
            if (!await original.exists()) continue;
            final archiveName = 'files/${serial++}';
            await encoder.addFile(original, archiveName);
            resources.add({'title': item.title, 'file': archiveName});
          }
        }
        chapters.add({'name': chapter.name, 'resources': resources});
      }
      final manifest = File(
        '${cache.path}/course-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await manifest.writeAsString(
        jsonEncode({'v': 1, 'name': course.name, 'chapters': chapters}),
      );
      try {
        await encoder.addFile(manifest, 'course.json');
      } finally {
        await manifest.delete();
      }
    } finally {
      encoder.close();
    }
    return file;
  }

  static Future<LocalCourse> importCourse(
    File zip,
    LocalCourseLibrary library,
  ) async {
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifestFiles = archive.files
        .where((entry) => entry.name == 'course.json' && entry.isFile)
        .toList();
    if (manifestFiles.length != 1)
      throw const FormatException('Missing course manifest');
    final raw = utf8.decode(manifestFiles.single.content as List<int>);
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['v'] != 1 ||
        data['name'] is! String ||
        data['chapters'] is! List) {
      throw const FormatException('Invalid course manifest');
    }
    final chapters = <CourseChapter>[];
    final files = {
      for (final entry in archive.files)
        if (entry.isFile) entry.name: entry,
    };
    final imported = <CourseMaterial>[];
    try {
      for (final chapter in data['chapters'] as List) {
        if (chapter is! Map ||
            chapter['name'] is! String ||
            chapter['resources'] is! List) {
          throw const FormatException('Invalid chapter');
        }
        final resources = <CourseMaterial>[];
        for (final item in chapter['resources'] as List) {
          if (item is! Map || item['title'] is! String)
            throw const FormatException('Invalid resource');
          if (item['url'] is String) {
            resources.add(
              library.createLink(
                item['title'] as String,
                item['url'] as String,
              ),
            );
          } else if (item['file'] is String) {
            final path = item['file'] as String;
            if (!RegExp(r'^files/[0-9]+
              await temp.delete(recursive: true);
            }
          } else {
            throw const FormatException('Invalid resource type');
          }
        }
        chapters.add(
          CourseChapter(
            id: library.newId(),
            name: chapter['name'] as String,
            materials: resources,
          ),
        );
      }
      return LocalCourse(
        id: library.newId(),
        name: data['name'] as String,
        chapters: chapters,
      );
    } catch (_) {
      for (final resource in imported) {
        await library.deleteMaterial(resource);
      }
      rethrow;
    }
  }
}
).hasMatch(path) ||
                !files.containsKey(path)) {
              throw const FormatException('Invalid attachment');
            }
            final bytes = files[path]!.content as List<int>;
            final temp = await Directory.systemTemp.createTemp(
              'moodle-import-',
            );
            try {
              final original = File('${temp.path}/attachment');
              await original.writeAsBytes(bytes);
              final resource = await library.importFile(
                original.path,
                item['title'] as String,
              );
              imported.add(resource);
              resources.add(resource);
            } finally {
              await temp.delete(recursive: true);
            }
          } else {
            throw const FormatException('Invalid resource type');
          }
        }
        chapters.add(CourseChapter(id: library.newId(), name: chapter['name'] as String, materials: resources));
      }
      return LocalCourse(id: library.newId(), name: data['name'] as String, chapters: chapters);
    } catch (_) {
      for (final resource in imported) {
        await library.deleteMaterial(resource);
      }
      rethrow;
    }
  }
}
