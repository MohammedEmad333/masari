import 'dart:io';

import 'package:crypto/crypto.dart';

import 'course_import_merger.dart';
import 'local_course_library.dart';

/// Deduplicates local ZIP attachments by SHA-256 content, rather than name.
/// Existing files and IDs are preserved; distinct revisions stay available.
class CourseFileHashMerger {
  const CourseFileHashMerger._();

  static Future<String> digest(String path) async {
    final file = File(path);
    return (await sha256.bind(file.openRead()).first).toString();
  }

  static Future<LocalCourse> merge(
    LocalCourse existing,
    LocalCourse incoming,
  ) async {
    final hashes = <String, String>{};
    Future<String> hash(CourseMaterial item) async {
      return hashes[item.value] ??= await digest(item.value);
    }

    final chapters = [...existing.chapters];
    for (final received in incoming.chapters) {
      final index = chapters.indexWhere(
        (chapter) =>
            CourseImportMerger.normalize(chapter.name) ==
            CourseImportMerger.normalize(received.name),
      );
      if (index == -1) {
        chapters.add(received);
        continue;
      }
      final current = chapters[index];
      final materials = [...current.materials];
      for (final resource in received.materials) {
        var duplicate = false;
        for (final item in materials) {
          if (item.isLink != resource.isLink) continue;
          if (item.isLink) {
            if (item.value.trim() == resource.value.trim()) {
              duplicate = true;
              break;
            }
          } else {
            if (await hash(item) == await hash(resource)) {
              duplicate = true;
              break;
            }
          }
        }
        if (!duplicate) materials.add(resource);
      }
      chapters[index] = CourseChapter(
        id: current.id,
        name: current.name,
        materials: materials,
      );
    }
    return LocalCourse(
      id: existing.id,
      name: existing.name,
      chapters: chapters,
    );
  }
}
