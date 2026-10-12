class StudentScheduleGroup {
  const StudentScheduleGroup({
    required this.id,
    required this.label,
    required this.major,
    required this.levelLabel,
    required this.number,
    required this.size,
    required this.capacity,
    required this.automatic,
  });

  factory StudentScheduleGroup.fromJson(Map<String, dynamic> json) =>
      StudentScheduleGroup(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Schedule group',
        major: json['major']?.toString() ?? '',
        levelLabel: json['level_label']?.toString() ?? '',
        number: (json['number'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        automatic: json['automatic'] == true,
      );

  final String id;
  final String label;
  final String major;
  final String levelLabel;
  final int number;
  final int size;
  final int capacity;
  final bool automatic;
}

class StudentGroupScheduleSlot {
  const StudentGroupScheduleSlot({
    required this.courseId,
    required this.courseName,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    this.location,
    this.sessionType,
    this.provisional = false,
  });

  factory StudentGroupScheduleSlot.fromJson(Map<String, dynamic> json) =>
      StudentGroupScheduleSlot(
        courseId: json['course_id']?.toString() ?? '',
        courseName:
            json['course_name']?.toString() ??
            json['course_id']?.toString() ??
            'Course',
        day: json['day_of_week']?.toString() ?? '',
        startMinute: (json['start_minute'] as num?)?.toInt() ?? 0,
        endMinute: (json['end_minute'] as num?)?.toInt() ?? 0,
        location: json['location']?.toString(),
        sessionType: json['session_type']?.toString(),
        provisional: json['provisional'] == true,
      );

  final String courseId;
  final String courseName;
  final String day;
  final int startMinute;
  final int endMinute;
  final String? location;
  final String? sessionType;
  final bool provisional;

  String get timeLabel =>
      '${_formatMinute(startMinute)}–${_formatMinute(endMinute)}';

  static String _formatMinute(int minute) {
    final hour24 = minute ~/ 60;
    final minutePart = minute % 60;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minutePart.toString().padLeft(2, '0')} $suffix';
  }
}

class UnscheduledCourse {
  const UnscheduledCourse({required this.id, required this.name});

  factory UnscheduledCourse.fromJson(Map<String, dynamic> json) =>
      UnscheduledCourse(
        id: json['course_id']?.toString() ?? '',
        name: json['course_name']?.toString() ?? 'Course',
      );

  final String id;
  final String name;
}

class StudentGroupSchedule {
  const StudentGroupSchedule({
    required this.id,
    required this.name,
    required this.semester,
    required this.slots,
    required this.unscheduledCourses,
    required this.timesSource,
  });

  factory StudentGroupSchedule.fromJson(Map<String, dynamic> json) =>
      StudentGroupSchedule(
        id: json['schedule_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'University schedule',
        semester: json['semester']?.toString() ?? 'Current semester',
        slots: ((json['slots'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StudentGroupScheduleSlot.fromJson)
            .toList(),
        unscheduledCourses:
            ((json['unscheduled_courses'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(UnscheduledCourse.fromJson)
                .toList(),
        timesSource: json['times_source']?.toString() ?? 'none',
      );

  final String id;
  final String name;
  final String semester;
  final List<StudentGroupScheduleSlot> slots;
  final List<UnscheduledCourse> unscheduledCourses;
  final String timesSource;
}

class StudentGroupScheduleReport {
  const StudentGroupScheduleReport({
    required this.studentId,
    required this.semester,
    required this.group,
    required this.schedule,
    required this.classmates,
    required this.groupSize,
  });

  factory StudentGroupScheduleReport.fromJson(Map<String, dynamic> json) =>
      StudentGroupScheduleReport(
        studentId: json['student_id']?.toString() ?? '',
        semester: json['semester']?.toString() ?? 'Current semester',
        group: json['group'] is Map<String, dynamic>
            ? StudentScheduleGroup.fromJson(
                json['group'] as Map<String, dynamic>,
              )
            : null,
        schedule: json['schedule'] is Map<String, dynamic>
            ? StudentGroupSchedule.fromJson(
                json['schedule'] as Map<String, dynamic>,
              )
            : null,
        classmates: ((json['classmates'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((item) => item['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        groupSize: (json['group_size'] as num?)?.toInt() ?? 0,
      );

  final String studentId;
  final String semester;
  final StudentScheduleGroup? group;
  final StudentGroupSchedule? schedule;
  final List<String> classmates;
  final int groupSize;
}
