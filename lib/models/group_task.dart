enum GroupTaskStatus { notStarted, inProgress, completed }

class GroupTaskMember {
  const GroupTaskMember({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory GroupTaskMember.fromJson(Map<String, dynamic> json) =>
      GroupTaskMember(id: json['id'] as String, name: json['name'] as String);
}

class GroupTaskPart {
  const GroupTaskPart({
    required this.id,
    required this.title,
    required this.assigneeId,
    this.status = GroupTaskStatus.notStarted,
  });

  final String id;
  final String title;
  final String assigneeId;
  final GroupTaskStatus status;

  GroupTaskPart copyWith({
    String? title,
    String? assigneeId,
    GroupTaskStatus? status,
  }) => GroupTaskPart(
    id: id,
    title: title ?? this.title,
    assigneeId: assigneeId ?? this.assigneeId,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'assigneeId': assigneeId,
    'status': status.name,
  };

  factory GroupTaskPart.fromJson(Map<String, dynamic> json) => GroupTaskPart(
    id: json['id'] as String,
    title: json['title'] as String,
    assigneeId: json['assigneeId'] as String,
    status: GroupTaskStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => GroupTaskStatus.notStarted,
    ),
  );
}

class GroupTask {
  const GroupTask({
    required this.id,
    required this.deadlineId,
    required this.name,
    required this.members,
    required this.parts,
  });

  final String id;
  final String deadlineId;
  final String name;
  final List<GroupTaskMember> members;
  final List<GroupTaskPart> parts;

  double get progress => parts.isEmpty
      ? 0
      : parts.where((part) => part.status == GroupTaskStatus.completed).length /
            parts.length;

  bool get assignmentsValid =>
      members.map((member) => member.id).toSet().length == members.length &&
      parts.every(
        (part) =>
            part.assigneeId.isEmpty ||
            members.any((member) => member.id == part.assigneeId),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deadlineId': deadlineId,
    'name': name,
    'members': members.map((member) => member.toJson()).toList(),
    'parts': parts.map((part) => part.toJson()).toList(),
  };

  factory GroupTask.fromJson(Map<String, dynamic> json) => GroupTask(
    id: json['id'] as String,
    deadlineId: json['deadlineId'] as String,
    name: json['name'] as String,
    members: (json['members'] as List)
        .map(
          (value) =>
              GroupTaskMember.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(),
    parts: (json['parts'] as List)
        .map(
          (value) =>
              GroupTaskPart.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(),
  );
}
