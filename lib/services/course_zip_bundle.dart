import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'local_course_library.dart';

/// Course ZIP: manifest plus explicitly indexed copied files. Never extract
/// arbitrary archive paths into the device filesystem.
class CourseZipBundle {
  const CourseZipBundle._();

  static const maxArchiveBytes = 40 * 1024 * 1024;
  static const maxExpandedBytes = 100 * 1024 * 1024;
  static const maxFiles = 300;
  static const maxChapters = 100;

  static Future<File> exportCourse(LocalCourse course) async {
    final cache = await getTemporaryDirectory();
    final output = File(
      '${cache.path}/moodle-course-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(output.path);
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
            if (++serial > maxFiles) {
              throw const FormatException('Too many attached files');
            }
            final path = 'files/$serial';
            await encoder.addFile(original, path);
            resources.add({'title': item.title, 'file': path});
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
    if (await output.length() > maxArchiveBytes) {
      await output.delete();
      throw const FormatException('ZIP exceeds sharing size limit');
    }
    return output;
  }

  /// Reads ZIP summary without copying attachments into app storage.
  static Future<({String name, int chapters, int files, int links})> previewCourse(File zip) async {
    if (await zip.length() > maxArchiveBytes) {
      throw const FormatException('ZIP exceeds size limit');
    }
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    if (archive.files.length > maxFiles + 1) {
      throw const FormatException('Too many ZIP entries');
    }
    final entries = <String, ArchiveFile>{};
    var expandedSize = 0;
    for (final entry in archive.files) {
      if (!entry.isFile ||
          (entry.name != 'course.json' && !RegExp(r'^files/[0-9]+\x24').hasMatch(entry.name)) ||
          entries.containsKey(entry.name)) {
        throw const FormatException('Unsafe ZIP entry');
      }
      expandedSize += entry.size;
      if (expandedSize > maxExpandedBytes) {
        throw const FormatException('ZIP expands beyond safety limit');
      }
      entries[entry.name] = entry;
    }
    final manifest = entries['course.json'];
    if (manifest == null || manifest.size > 1024 * 1024) {
      throw const FormatException('Invalid ZIP manifest');
    }
    final decoded = jsonDecode(utf8.decode(manifest.readBytes() ?? <int>[]));
    if (decoded is! Map || decoded['v'] != 1 || decoded['name'] is! String ||
        (decoded['name'] as String).trim().isEmpty || decoded['chapters'] is! List) {
      throw const FormatException('Invalid course metadata');
    }
    final chapters = decoded['chapters'] as List;
    if (chapters.length > maxChapters) throw const FormatException('Too many chapters');
    var files = 0;
    var links = 0;
    for (final chapter in chapters) {
      if (chapter is! Map || chapter['name'] is! String || chapter['resources'] is! List) {
        throw const FormatException('Invalid chapter');
      }
      for (final resource in chapter['resources'] as List) {
        if (resource is! Map || resource['title'] is! String) {
          throw const FormatException('Invalid material');
        }
        if (resource['file'] is String && entries.containsKey(resource['file'])) {
          files++;
        } else if (resource['url'] is String) {
          links++;
        } else {
          throw const FormatException('Invalid material reference');
        }
      }
    }
    return (name: decoded['name'] as String, chapters: chapters.length, files: files, links: links);
  }
  static Future<LocalCourse> importCourse(
    File zip,
    LocalCourseLibrary library,
  ) async {
    if (await zip.length() > maxArchiveBytes) {
      throw const FormatException('ZIP exceeds size limit');
    }
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    if (archive.files.length > maxFiles + 1) {
      throw const FormatException('Too many ZIP entries');
    }
    var expandedSize = 0;
    final entries = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (!entry.isFile) {
        throw const FormatException('Unsupported ZIP entry');
      }
      if (entry.name != 'course.json' &&
          !RegExp(r'^files/[0-9]+$').hasMatch(entry.name)) {
        throw const FormatException('Unsafe ZIP entry');
      }
      if (entries.containsKey(entry.name)) {
        throw const FormatException('Duplicate ZIP path');
      }
      expandedSize += entry.size;
      if (expandedSize > maxExpandedBytes) {
        throw const FormatException('ZIP expands beyond safety limit');
      }
      entries[entry.name] = entry;
    }
    final manifest = entries['course.json'];
    if (manifest == null || manifest.size > 1024 * 1024) {
      throw const FormatException('Invalid ZIP manifest');
    }
    final data = jsonDecode(utf8.decode(manifest.readBytes() ?? <int>[]));
    if (data is! Map ||
        data['v'] != 1 ||
        data['name'] is! String ||
        data['chapters'] is! List ||
        (data['name'] as String).trim().isEmpty) {
      throw const FormatException('Invalid course metadata');
    }
    final chapterData = data['chapters'] as List;
    if (chapterData.length > maxChapters) {
      throw const FormatException('Too many chapters');
    }
    final chapters = <CourseChapter>[];
    final created = <CourseMaterial>[];
    try {
      for (final chapter in chapterData) {
        if (chapter is! Map ||
            chapter['name'] is! String ||
            chapter['resources'] is! List) {
          throw const FormatException('Invalid chapter');
        }
        final resources = <CourseMaterial>[];
        for (final item in chapter['resources'] as List) {
          if (item is! Map || item['title'] is! String) {
            throw const FormatException('Invalid material');
          }
          final title = item['title'] as String;
          if (title.trim().isEmpty || title.length > 250) {
            throw const FormatException('Invalid material title');
          }
          if (item['url'] is String) {
            resources.add(library.createLink(title, item['url'] as String));
          } else if (item['file'] is String) {
            final path = item['file'] as String;
            final entry = entries[path];
            if (!RegExp(r'^files/[0-9]+$').hasMatch(path) || entry == null) {
              throw const FormatException('Missing or invalid attachment');
            }
            final folder = await Directory.systemTemp.createTemp('course-zip-');
            try {
              final source = File('${folder.path}/attachment');
              await source.writeAsBytes(entry.readBytes() ?? <int>[]);
              final attached = await library.importFile(source.path, title);
              created.add(attached);
              resources.add(attached);
            } finally {
              await folder.delete(recursive: true);
            }
          } else {
            throw const FormatException('Unsupported material');
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
      for (final item in created) {
        await library.deleteMaterial(item);
      }
      rethrow;
    }
  }
}
