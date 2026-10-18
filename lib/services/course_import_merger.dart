import 'local_course_library.dart';

/// Match imported chapters by their normalized names, and web resources by URL.
/// Existing local copies of files are always preserved.
class CourseImportMerger {
  const CourseImportMerger._();

  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();

  static LocalCourse? findMatch(
    Iterable<LocalCourse> existing,
    LocalCourse incoming,
  ) {
    for (final course in existing) {
      if (normalize(course.name) == normalize(incoming.name)) return course;
    }
    return null;
  }

  /// Merge ZIP contents while retaining existing files. Files with matching
  /// normalized titles in the same chapter are treated as already imported.
  static LocalCourse mergeZip(LocalCourse existing, LocalCourse incoming) {
    final chapters = [...existing.chapters];
    for (final received in incoming.chapters) {
      final index = chapters.indexWhere(
        (chapter) => normalize(chapter.name) == normalize(received.name),
      );
      if (index == -1) {
        chapters.add(received);
        continue;
      }
      final current = chapters[index];
      final materials = [...current.materials];
      for (final resource in received.materials) {
        final duplicate = materials.any(
          (item) => item.isLink == resource.isLink &&
              (item.isLink
                  ? item.value.trim() == resource.value.trim()
                  : normalize(item.title) == normalize(resource.title)),
        );
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

  static LocalCourse merge(LocalCourse existing, LocalCourse incoming) {
    final chapters = [...existing.chapters];
    for (final remote in incoming.chapters) {
      final index = chapters.indexWhere(
        (chapter) => normalize(chapter.name) == normalize(remote.name),
      );
      if (index == -1) {
        chapters.add(remote);
        continue;
      }
      final current = chapters[index];
      final materials = [...current.materials];
      for (final resource in remote.materials) {
        if (!resource.isLink) continue;
        final alreadyExists = materials.any(
          (item) => item.isLink && item.value.trim() == resource.value.trim(),
        );
        if (!alreadyExists) materials.add(resource);
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
