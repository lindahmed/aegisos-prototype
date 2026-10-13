class CourseScheduleSlot {
  const CourseScheduleSlot({
    required this.day,
    required this.startMinute,
    required this.endMinute,
    this.location,
  });

  factory CourseScheduleSlot.fromJson(Map<String, dynamic> json) =>
      CourseScheduleSlot(
        day: json['day_of_week']?.toString() ?? '',
        startMinute: (json['start_minute'] as num?)?.toInt() ?? 0,
        endMinute: (json['end_minute'] as num?)?.toInt() ?? 0,
        location: json['location']?.toString(),
      );

  final String day;
  final int startMinute;
  final int endMinute;
  final String? location;

  String get timeLabel => '${_formatMinute(startMinute)}–${_formatMinute(endMinute)}';

  static String _formatMinute(int minute) {
    final hour24 = minute ~/ 60;
    final minutePart = minute % 60;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minutePart.toString().padLeft(2, '0')} $suffix';
  }
}

class RegisteredCourse {
  const RegisteredCourse({
    required this.code,
    required this.name,
    required this.status,
    required this.semester,
    required this.schedule,
  });

  factory RegisteredCourse.fromJson(Map<String, dynamic> json) =>
      RegisteredCourse(
        code: json['course_code']?.toString() ?? '',
        name: json['course_name']?.toString() ?? 'Course',
        status: json['status']?.toString() ?? 'Current',
        semester: json['semester']?.toString() ?? 'Current semester',
        schedule: ((json['schedule'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CourseScheduleSlot.fromJson)
            .toList(),
      );

  final String code;
  final String name;
  final String status;
  final String semester;
  final List<CourseScheduleSlot> schedule;
}

class StudentCoursesReport {
  const StudentCoursesReport({
    required this.courseCount,
    required this.schedulePublished,
    required this.courses,
  });

  factory StudentCoursesReport.fromJson(Map<String, dynamic> json) =>
      StudentCoursesReport(
        courseCount: (json['course_count'] as num?)?.toInt() ?? 0,
        schedulePublished: json['schedule_published'] as bool? ?? false,
        courses: ((json['courses'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RegisteredCourse.fromJson)
            .toList(),
      );

  final int courseCount;
  final bool schedulePublished;
  final List<RegisteredCourse> courses;
}
