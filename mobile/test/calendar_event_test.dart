import 'package:uni_track_mobile/models/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final academics = <String, dynamic>{
    'semester': 'Fall 2026',
    'current_week': 1,
    'courses': [
      {
        'course_id': 'CCS2102',
        'course_name': 'Digital Logic Design',
        'risk_level': 'high',
        'metrics': {'course_health': 42},
        'risks': [
          {'message': 'Course health is below target.'},
        ],
        'assessments': [
          {
            'assessment_id': 'exam-1',
            'name': 'Week 2 exam',
            'assessment_type': 'midterm',
            'due_week': 2,
            'max_marks': 30,
            'mark': null,
          },
          {
            'assessment_id': 'assignment-1',
            'name': 'Week 2 assignment',
            'assessment_type': 'assignment',
            'due_week': 2,
            'max_marks': 10,
            'mark': 8,
          },
        ],
      },
    ],
  };

  test('academic events match the portal calendar placement rules', () {
    final events = StudentCalendarBuilder.academicEvents(
      academics,
      now: DateTime(2026, 9, 2, 12),
    );

    expect(events, hasLength(2));
    expect(events[0].startAt, DateTime(2026, 9, 7, 9));
    expect(events[0].endAt, DateTime(2026, 9, 7, 11));
    expect(events[0].type, StudentCalendarEventType.exam);
    expect(events[1].startAt, DateTime(2026, 9, 13, 22));
    expect(events[1].completed, isTrue);
  });

  test('AI planning is urgent-only and idempotent', () {
    final first = StudentCalendarBuilder.addUrgentStudySessions(
      academics: academics,
      customEvents: const [],
      now: DateTime(2026, 9, 2, 12),
    );
    final second = StudentCalendarBuilder.addUrgentStudySessions(
      academics: academics,
      customEvents: first,
      now: DateTime(2026, 9, 2, 12),
    );

    expect(first, hasLength(1));
    expect(first.single.source, StudentCalendarEventSource.ai);
    expect(first.single.startAt.hour, 18);
    expect(second, hasLength(1));
  });

  test('custom events persist per student', () async {
    SharedPreferences.setMockInitialValues({});
    final event = StudentCalendarEvent(
      id: 'student:1',
      title: 'Study algorithms',
      description: 'Chapter 4',
      startAt: DateTime(2026, 9, 4, 18),
      endAt: DateTime(2026, 9, 4, 19),
      type: StudentCalendarEventType.studySession,
      source: StudentCalendarEventSource.student,
    );

    await StudentCalendarStore.save('STU001', [event]);

    expect(
      (await StudentCalendarStore.load('stu001')).single.title,
      event.title,
    );
    expect(await StudentCalendarStore.load('STU002'), isEmpty);
  });
}
