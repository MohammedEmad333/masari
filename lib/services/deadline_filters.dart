import '../models/deadline.dart';

/// Pure filtering logic shared by the home screen and unit tests.
List<Deadline> filterDeadlines(
  Iterable<Deadline> deadlines, {
  String query = '',
  String? course,
}) {
  final needle = query.trim().toLowerCase();
  return deadlines.where((deadline) {
    if (course != null && deadline.course != course) return false;
    if (needle.isEmpty) return true;
    return deadline.title.toLowerCase().contains(needle) ||
        deadline.course.toLowerCase().contains(needle) ||
        deadline.description.toLowerCase().contains(needle);
  }).toList();
}
