import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum StudentCalendarEventType { exam, assignment, personal, studySession }

enum StudentCalendarEventSource { academic, student, ai }

class StudentCalendarEvent {
  const StudentCalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.type,
    required this.source,
    this.courseId,
    this.urgent = false,
    this.completed = false,
  });

  factory StudentCalendarEvent.fromJson(Map<String, dynamic> json) {
    return StudentCalendarEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      type: StudentCalendarEventType.values.byName(json['type'] as String),
      source: StudentCalendarEventSource.values.byName(
        json['source'] as String,
      ),
      courseId: json['course_id']?.toString(),
      urgent: json['urgent'] == true,
      completed: json['completed'] == true,
    );
  }

  final String id;
  final String title;
  final String description;
  final DateTime startAt;
  final DateTime endAt;
  final StudentCalendarEventType type;
  final StudentCalendarEventSource source;
  final String? courseId;
  final bool urgent;
  final bool completed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(),
    'type': type.name,
    'source': source.name,
    'course_id': courseId,
    'urgent': urgent,
    'completed': completed,
  };
}

class StudentCalendarStore {
  static String _key(String studentId) =>
      'aegisos-calendar:${studentId.trim().toUpperCase()}';

  static Future<List<StudentCalendarEvent>> load(String studentId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(studentId));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(StudentCalendarEvent.fromJson)
          .where((event) => event.id.isNotEmpty && event.title.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
    String studentId,
    List<StudentCalendarEvent> events,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(studentId),
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }
}

class StudentCalendarBuilder {
  static const _examTypes = {'midterm', 'final', 'exam'};

  static List<StudentCalendarEvent> academicEvents(
    Map<String, dynamic>? academics, {
    DateTime? now,
  }) {
    if (academics == null) return [];
    final today = now ?? DateTime.now();
    final currentWeek = (academics['current_week'] as num?)?.toInt() ?? 1;
    final start = _semesterStart(today, currentWeek);
    final courses = ((academics['courses'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>();
    return courses.expand((course) {
      final assessments =
          ((course['assessments'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>();
      return assessments.map((assessment) {
        final assessmentType = assessment['assessment_type']
            ?.toString()
            .toLowerCase();
        final isExam = _examTypes.contains(assessmentType);
        final dueWeek =
            (assessment['due_week'] as num?)?.toInt() ?? currentWeek;
        final eventStart = DateTime(
          start.year,
          start.month,
          start.day + (dueWeek - 1) * 7 + (isExam ? 0 : 6),
          isExam ? 9 : 22,
        );
        final maximum = (assessment['max_marks'] as num?)?.toInt() ?? 100;
        return StudentCalendarEvent(
          id: 'academic:${assessment['assessment_id'] ?? '${course['course_id']}:$dueWeek:$assessmentType'}',
          title: assessment['name']?.toString() ?? 'Assessment',
          description:
              '${course['course_name'] ?? 'Course'} · $maximum marks · academic week $dueWeek',
          startAt: eventStart,
          endAt: eventStart.add(Duration(minutes: isExam ? 120 : 60)),
          type: isExam
              ? StudentCalendarEventType.exam
              : StudentCalendarEventType.assignment,
          source: StudentCalendarEventSource.academic,
          courseId: course['course_id']?.toString(),
          completed: assessment['mark'] != null,
        );
      });
    }).toList();
  }

  static List<StudentCalendarEvent> addUrgentStudySessions({
    required Map<String, dynamic> academics,
    required List<StudentCalendarEvent> customEvents,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final semester = academics['semester']?.toString() ?? '';
    final currentWeek = (academics['current_week'] as num?)?.toInt() ?? 1;
    final allEvents = [
      ...academicEvents(academics, now: current),
      ...customEvents,
    ];
    final result = [...customEvents];
    final courses = ((academics['courses'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .where(_isUrgent)
        .toList();

    for (var index = 0; index < courses.length; index += 1) {
      final course = courses[index];
      final courseId = course['course_id']?.toString() ?? 'course-$index';
      final id = 'ai:$semester:$currentWeek:$courseId';
      if (result.any((event) => event.id == id)) continue;
      final start = _nextStudySlot(
        [
          ...allEvents,
          ...result.where((event) => !customEvents.contains(event)),
        ],
        index,
        current,
      );
      final riskMessages = ((course['risks'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((risk) => risk['message']?.toString() ?? '')
          .where((message) => message.isNotEmpty)
          .take(2)
          .join('; ');
      result.add(
        StudentCalendarEvent(
          id: id,
          title: 'Urgent study: ${course['course_name'] ?? 'Course'}',
          description: riskMessages.isEmpty
              ? 'AI reserved this focus session because the course needs attention.'
              : 'AI reserved this focus session because $riskMessages',
          startAt: start,
          endAt: start.add(const Duration(minutes: 90)),
          type: StudentCalendarEventType.studySession,
          source: StudentCalendarEventSource.ai,
          courseId: courseId,
          urgent: true,
        ),
      );
    }
    return result;
  }

  static bool _isUrgent(Map<String, dynamic> course) {
    if (course['risk_level']?.toString().toLowerCase() == 'high') return true;
    final metrics = course['metrics'] as Map<String, dynamic>? ?? const {};
    final health = (metrics['course_health'] as num?)?.toDouble();
    final risks = (course['risks'] as List<dynamic>?) ?? const [];
    return health != null && health < 60 && risks.isNotEmpty;
  }

  static DateTime _semesterStart(DateTime now, int currentWeek) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return monday.subtract(Duration(days: (currentWeek - 1) * 7));
  }

  static DateTime _nextStudySlot(
    List<StudentCalendarEvent> events,
    int offset,
    DateTime now,
  ) {
    var first = DateTime(now.year, now.month, now.day, now.hour);
    if (first.hour >= 18) first = first.add(const Duration(days: 1));
    final candidates = <DateTime>[];
    for (var day = 0; day < 5; day += 1) {
      for (final hour in const [18, 20]) {
        candidates.add(
          DateTime(first.year, first.month, first.day + day, hour),
        );
      }
    }
    final rotation = offset % candidates.length;
    final rotated = [
      ...candidates.skip(rotation),
      ...candidates.take(rotation),
    ];
    return rotated.firstWhere(
      (start) =>
          start.isAfter(now) &&
          !_overlaps(start, start.add(const Duration(minutes: 90)), events),
      orElse: () => candidates.last,
    );
  }

  static bool _overlaps(
    DateTime start,
    DateTime end,
    List<StudentCalendarEvent> events,
  ) => events.any(
    (event) => start.isBefore(event.endAt) && end.isAfter(event.startAt),
  );
}
