import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CourseMaterial {
  const CourseMaterial({
    required this.id,
    required this.title,
    required this.value,
    required this.isLink,
  });
  final String id;
  final String title;
  final String value;
  final bool isLink;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'value': value,
    'isLink': isLink,
  };

  factory CourseMaterial.fromJson(Map<String, dynamic> json) => CourseMaterial(
    id: json['id'] as String,
    title: json['title'] as String,
    value: json['value'] as String,
    isLink: json['isLink'] as bool,
  );
}

class CourseChapter {
  const CourseChapter({
    required this.id,
    required this.name,
    this.materials = const [],
  });
  final String id;
  final String name;
  final List<CourseMaterial> materials;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'materials': materials.map((m) => m.toJson()).toList(),
  };

  factory CourseChapter.fromJson(Map<String, dynamic> json) => CourseChapter(
    id: json['id'] as String,
    name: json['name'] as String,
    materials: (json['materials'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CourseMaterial.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

class LocalCourse {
  const LocalCourse({
    required this.id,
    required this.name,
    this.chapters = const [],
  });
  final String id;
  final String name;
  final List<CourseChapter> chapters;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'chapters': chapters.map((ch) => ch.toJson()).toList(),
  };

  factory LocalCourse.fromJson(Map<String, dynamic> json) => LocalCourse(
    id: json['id'] as String,
    name: json['name'] as String,
    chapters: (json['chapters'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CourseChapter.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

/// Stores a private copy of each imported file in the app documents directory.
class LocalCourseLibrary {
  LocalCourseLibrary(this.directory);

  final Directory directory;
  int _counter = 0;

  static Future<LocalCourseLibrary> open() async =>
      LocalCourseLibrary(await getApplicationDocumentsDirectory());

  String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  File get _index => File('${directory.path}/study_library/index.json');
  Directory get _files => Directory('${directory.path}/study_library/files');

  Future<List<LocalCourse>> load() async {
    if (!await _index.exists()) return [];
    final decoded = jsonDecode(await _index.readAsString()) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              LocalCourse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> save(List<LocalCourse> courses) async {
    await _index.parent.create(recursive: true);
    final temp = File('${_index.path}.tmp');
    await temp.writeAsString(
      jsonEncode(courses.map((c) => c.toJson()).toList()),
      flush: true,
    );
    await temp.rename(_index.path);
  }

  /// Only accepts a local file produced by the platform picker.
  Future<CourseMaterial> importFile(
    String sourcePath,
    String displayName,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('Selected file not found');
    }
    await _files.create(recursive: true);
    final id = newId();
    final suffix = displayName.contains('.')
        ? '.${displayName.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}'
        : '';
    final target = File('${_files.path}/$id$suffix');
    await source.copy(target.path);
    return CourseMaterial(
      id: id,
      title: displayName,
      value: target.path,
      isLink: false,
    );
  }

  CourseMaterial createLink(String title, String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid HTTP or HTTPS URL');
    }
    return CourseMaterial(
      id: newId(),
      title: title.trim(),
      value: uri.toString(),
      isLink: true,
    );
  }

  Future<void> deleteMaterial(CourseMaterial material) async {
    if (material.isLink) return;
    final file = File(material.value);
    final parent = _files.absolute.path;
    if (file.parent.absolute.path != parent) return;
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteChapterFiles(CourseChapter chapter) async {
    for (final material in chapter.materials) {
      await deleteMaterial(material);
    }
  }
}
