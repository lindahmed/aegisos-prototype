import 'package:flutter_test/flutter_test.dart';
import 'package:uni_track_mobile/models/group_schedule.dart';

void main() {
  test('parses the group schedule, sessions and members', () {
    final schedule = GroupSchedule.fromJson({
      'group': {'label': 'Computer Science · Semester 5 · Group 1', 'size': 2, 'capacity': 25},
      'schedule': {
        'semester': 'Fall 2026',
        'times_source': 'provisional',
        'slots': [
          {
            'course_id': 'AI',
            'course_name': 'Introduction to Artificial Intelligence',
            'day_of_week': 'Saturday',
            'start_minute': 510,
            'end_minute': 610,
            'location': 'Room 203',
            'session_type': 'Lecture',
            'provisional': true,
          },
        ],
        'unscheduled_courses': [
          {'course_id': 'X', 'course_name': 'Project I'},
        ],
      },
      'members': [
        {'name': 'Aya Salem', 'is_you': false},
        {'name': 'Yasmin Wael', 'is_you': true},
      ],
    });

    expect(schedule.hasGroup, isTrue);
    expect(schedule.sessions.single.timeLabel, '8:30 AM – 10:10 AM');
    expect(schedule.sessions.single.durationLabel, '1 h 40 min');
    expect(schedule.sessions.single.sessionType, 'Lecture');
    expect(schedule.unscheduledCourses, ['Project I']);
    expect(schedule.members.where((m) => m.isYou).single.name, 'Yasmin Wael');
  });

  test('a student without a group has no schedule', () {
    final schedule = GroupSchedule.fromJson({'group': null, 'schedule': null});
    expect(schedule.hasGroup, isFalse);
    expect(schedule.members, isEmpty);
  });
}
