/// The student's common group schedule and the names of everyone who shares it.
/// Comes from GET /portal/students/{id}/schedule (database data only).
class GroupSession {
  const GroupSession({
    required this.courseName,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.provisional,
    this.sessionType,
    this.location,
  });

  factory GroupSession.fromJson(Map<String, dynamic> json) => GroupSession(
    courseName:
        json['course_name']?.toString() ?? json['course_id']?.toString() ?? '',
    day: json['day_of_week']?.toString() ?? '',
    startMinute: (json['start_minute'] as num?)?.toInt() ?? 0,
    endMinute: (json['end_minute'] as num?)?.toInt() ?? 0,
    provisional: json['provisional'] == true,
    sessionType: json['session_type']?.toString(),
    location: json['location']?.toString(),
  );

  final String courseName;
  final String day;
  final int startMinute;
  final int endMinute;
  final bool provisional;
  final String? sessionType;
  final String? location;

  int get minutes => endMinute - startMinute;

  String get timeLabel => '${formatMinute(startMinute)} – ${formatMinute(endMinute)}';

  String get durationLabel {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$hours h';
    return hours == 0 ? '$rest min' : '$hours h $rest min';
  }

  static String formatMinute(int minute) {
    final hour24 = minute ~/ 60;
    final minutePart = minute % 60;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minutePart.toString().padLeft(2, '0')} $suffix';
  }
}

class GroupMember {
  const GroupMember({required this.name, required this.isYou});

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    name: json['name']?.toString() ?? '',
    isYou: json['is_you'] == true,
  );

  final String name;
  final bool isYou;
}

class GroupSchedule {
  const GroupSchedule({
    required this.hasGroup,
    required this.label,
    required this.semester,
    required this.size,
    required this.capacity,
    required this.timesSource,
    required this.sessions,
    required this.unscheduledCourses,
    required this.members,
  });

  factory GroupSchedule.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>?;
    final schedule = json['schedule'] as Map<String, dynamic>?;
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) parse) =>
        (raw as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(parse)
            .toList();
    return GroupSchedule(
      hasGroup: group != null && schedule != null,
      label: group?['label']?.toString() ?? '',
      semester: schedule?['semester']?.toString() ?? '',
      size: (group?['size'] as num?)?.toInt() ?? 0,
      capacity: (group?['capacity'] as num?)?.toInt() ?? 25,
      timesSource: schedule?['times_source']?.toString() ?? 'none',
      sessions: list(schedule?['slots'], GroupSession.fromJson),
      unscheduledCourses: list(
        schedule?['unscheduled_courses'],
        (item) => item['course_name']?.toString() ?? '',
      ),
      members: list(json['members'], GroupMember.fromJson),
    );
  }

  final bool hasGroup;
  final String label;
  final String semester;
  final int size;
  final int capacity;
  final String timesSource;
  final List<GroupSession> sessions;
  final List<String> unscheduledCourses;
  final List<GroupMember> members;
}
