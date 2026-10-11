class Deadline {
  const Deadline({
    required this.uid,
    required this.title,
    required this.due,
    this.description = '',
    this.course = '',
    this.url = '',
    this.location = '',
    this.status = '',
    this.sequence = 0,
    this.priority = 1,
    this.lastModified,
  });

  final String uid;
  final String title;
  final DateTime due;
  final String description;
  final String course;
  final String url;
  final String location;
  final String status;
  final int sequence;
  final int priority;
  final DateTime? lastModified;

  double get hoursRemaining => due.difference(DateTime.now()).inMinutes / 60;
  bool get isPast => due.isBefore(DateTime.now());

  String get stableKey => uid.isNotEmpty
      ? uid
      : '${title.trim()}|${course.trim()}|${due.toUtc().toIso8601String()}';

  String get remainingText {
    final difference = due.difference(DateTime.now());
    if (difference.isNegative) return 'Past';

    final minutes = difference.inMinutes;
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    final mins = minutes % 60;

    if (days > 0) return '$days d${hours > 0 ? ' $hours h' : ''}';
    if (hours > 0) return '$hours h${mins > 0 ? ' $mins m' : ''}';
    return '$mins m';
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'title': title,
    'due': due.toIso8601String(),
    'description': description,
    'course': course,
    'url': url,
    'location': location,
    'status': status,
    'sequence': sequence,
    'priority': priority,
    'lastModified': lastModified?.toIso8601String(),
  };

  factory Deadline.fromJson(Map<String, dynamic> json) {
    final dueValue = json['due'];
    if (dueValue is! String || dueValue.isEmpty) {
      throw const FormatException('Deadline is missing a due date.');
    }

    return Deadline(
      uid: (json['uid'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      due: DateTime.parse(dueValue),
      description: (json['description'] as String?) ?? '',
      course: (json['course'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 1,
      lastModified: json['lastModified'] is String
          ? DateTime.tryParse(json['lastModified'] as String)
          : null,
    );
  }
}
