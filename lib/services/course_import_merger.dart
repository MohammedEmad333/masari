import 'local_course_library.dart';

/// Merge imported chapters/links without discarding local files or IDs.
class CourseImportMerger {
  const CourseImportMerger._();

  static LocalCourse? matching(
    List<LocalCourse> courses,
    LocalCourse incoming,
  ) {
    final key = incoming.name.trim().toLowerCase();
    for (final course in courses) {
      if (course.name.trim().toLowerCase() == key) return course;
    }
    return null;
  }

  static LocalCourse merge(LocalCourse existing, LocalCourse incoming) {
    final chapters = [...existing.chapters];
    for (final newChapter in incoming.chapters) {
      final index = chapters.indexWhere(
        (ch) =>
            ch.name.trim().toLowerCase() ==
            newChapter.name.trim().toLowerCase(),
      );
      if (index < 0) {
        chapters.add(newChapter);
        continue;
      }
      final oldChapter = chapters[index];
      final urls = oldChapter.materials
          .where((m) => m.isLink)
          .map((m) => m.value.trim().toLowerCase())
          .toSet();
      final materials = [...oldChapter.materials];
      for (final material in newChapter.materials) {
        if (!material.isLink || urls.add(material.value.trim().toLowerCase())) {
          materials.add(material);
        }
      }
      chapters[index] = CourseChapter(
        id: oldChapter.id,
        name: oldChapter.name,
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
