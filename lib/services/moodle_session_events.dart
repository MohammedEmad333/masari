import 'dart:convert';

import '../models/deadline.dart';

/// Only accepts non-secret event metadata from an already authenticated
/// first-party Moodle page. Does not transport cookies or sesskeys.
class MoodleSessionEvents {
  const MoodleSessionEvents._();

  static List<Deadline> parse(Object? result, Uri server) {
    dynamic decoded = result;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
    }
    if (decoded is! List) {
      throw const FormatException('Unexpected Moodle events response');
    }
    final values = <Deadline>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final event = Map<String, dynamic>.from(item);
      final ts = (event['timestart'] as num?)?.toInt();
      final id = (event['id'] as num?)?.toInt();
      final title = event['name'] as String?;
      if (ts == null || ts <= 0 || title == null || title.isEmpty) continue;
      final rawUrl = event['url'] as String? ?? '';
      final url = Uri.tryParse(rawUrl);
      final safeUrl = url != null &&
              url.scheme == 'https' &&
              url.host == server.host
          ? url.toString()
          : '';
      values.add(
        Deadline(
          uid: 'moodle-session:${id ?? '${title.hashCode}-$ts'}',
          title: title,
          course: event['course'] as String? ?? '',
          due: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
          url: safeUrl,
        ),
      );
    }
    return values..sort((a, b) => a.due.compareTo(b.due));
  }
}
