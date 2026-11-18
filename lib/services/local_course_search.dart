import '../services/local_course_library.dart';

/// Presentation-only search across course titles, chapter names and material
/// titles. Never filters nested content or mutates persisted library objects.
List<LocalCourse> searchLocalCourses(
  Iterable<LocalCourse> courses,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return courses.toList();
  return courses.where((course) {
    if (course.name.toLowerCase().contains(needle)) return true;
    return course.chapters.any(
      (chapter) =>
          chapter.name.toLowerCase().contains(needle) ||
          chapter.materials.any(
            (material) => material.title.toLowerCase().contains(needle),
          ),
    );
  }).toList();
}

int localCourseMaterialCount(LocalCourse course) => course.chapters.fold<int>(
  0,
  (sum, chapter) => sum + chapter.materials.length,
);

int localChapterFileCount(CourseChapter chapter) =>
    chapter.materials.where((material) => !material.isLink).length;

int localChapterLinkCount(CourseChapter chapter) =>
    chapter.materials.where((material) => material.isLink).length;
