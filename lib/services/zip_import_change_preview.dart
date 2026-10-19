import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'course_file_hash_merger.dart';
import 'course_import_merger.dart';
import 'course_zip_bundle.dart';
import 'local_course_library.dart';

/// Read-only comparison of a ZIP bundle against an existing local course.
class ZipImportChangePreview {
  const ZipImportChangePreview({
    required this.newChapters,
    required this.newFiles,
    required this.duplicateFiles,
    required this.changedFiles,
    required this.newLinks,
  });

  final int newChapters;
  final int newFiles;
  final int duplicateFiles;
  final int changedFiles;
  final int newLinks;

  static Future<ZipImportChangePreview> inspect(
    File zip,
    LocalCourse existing,
  ) async {
    // Validate every archive entry before inspecting its contents.
    await CourseZipBundle.previewCourse(zip);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final entries = {for (final entry in archive.files) entry.name: entry};
    final manifest = entries['course.json']!;
    final data =
        jsonDecode(utf8.decode(manifest.readBytes() ?? <int>[])) as Map;
    final hashes = <String, String>{};
    Future<String> hash(CourseMaterial material) async {
      final previous = hashes[material.value];
      if (previous != null) return previous;
      final value = await CourseFileHashMerger.digest(material.value);
      hashes[material.value] = value;
      return value;
    }

    var chaptersAdded = 0;
    var filesAdded = 0;
    var filesDuplicate = 0;
    var filesChanged = 0;
    var linksAdded = 0;
    for (final chapter in data['chapters'] as List) {
      final received = chapter as Map;
      final name = received['name'] as String;
      final index = existing.chapters.indexWhere(
        (item) =>
            CourseImportMerger.normalize(item.name) ==
            CourseImportMerger.normalize(name),
      );
      if (index == -1) chaptersAdded++;
      final current = index == -1
          ? <CourseMaterial>[]
          : existing.chapters[index].materials;
      final seenHashes = <String>{
        for (final material in current)
          if (!material.isLink) await hash(material),
      };
      final seenLinks = <String>{
        for (final material in current)
          if (material.isLink) material.value.trim(),
      };
      final names = <String>{
        for (final material in current)
          if (!material.isLink) CourseImportMerger.normalize(material.title),
      };
      for (final resource in received['resources'] as List) {
        final item = resource as Map;
        if (item['url'] is String) {
          if (seenLinks.add((item['url'] as String).trim())) linksAdded++;
        } else {
          final bytes = entries[item['file']]!.readBytes()!;
          final digest = sha256.convert(bytes).toString();
          if (!seenHashes.add(digest)) {
            filesDuplicate++;
          } else {
            final normalized = CourseImportMerger.normalize(
              item['title'] as String,
            );
            if (names.contains(normalized)) {
              filesChanged++;
            } else {
              filesAdded++;
            }
            names.add(normalized);
          }
        }
      }
    }
    return ZipImportChangePreview(
      newChapters: chaptersAdded,
      newFiles: filesAdded,
      duplicateFiles: filesDuplicate,
      changedFiles: filesChanged,
      newLinks: linksAdded,
    );
  }
}
