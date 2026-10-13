import 'dart:convert';

import 'package:uni_track_mobile/models/student.dart';
import 'package:uni_track_mobile/screens/student_home_screen.dart';
import 'package:uni_track_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('keeps each academic feature in one clear place', (tester) async {
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
        }
        if (request.url.path.endsWith('/weekly-plan')) {
          return http.Response(
            jsonEncode({
              'student_id': 'STU001',
              'semester': 'Fall 2026',
              'current_week': 1,
              'items': [
                {
                  'task_id': 'risk:13:lecture_backlog:1',
                  'course_id': '13',
                  'course_name': 'Digital Logic Design',
                  'title': 'Catch up on lectures',
                  'detail': 'Review the next incomplete lecture.',
                  'task_type': 'risk',
                  'status': 'pending',
                  'position': 1,
                  'completed_at': null,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/semester-plan')) {
          return http.Response(
            jsonEncode({
              'current_semester': 3,
              'next_semester': 4,
              'current_gpa': 3.55,
              'maximum_credit_hours': 18,
              'recommended_courses': [
                {
                  'course_id': '21',
                  'course_code': 'CIS2101',
                  'course_name': 'Database Systems',
                  'curriculum_semester': 3,
                  'credit_hours': 3,
                  'eligibility': 'eligible',
                  'prerequisites': [],
                  'schedule': [],
                },
              ],
              'candidate_courses': [
                {
                  'course_id': '21',
                  'course_code': 'CIS2101',
                  'course_name': 'Database Systems',
                  'curriculum_semester': 3,
                  'credit_hours': 3,
                  'eligibility': 'eligible',
                  'prerequisites': [],
                  'schedule': [],
                },
              ],
              'credit_policy': {'note': 'Estimated at 3 credits'},
              'conflict_check': {
                'status': 'unavailable',
                'note': 'Timetable slots are not available.',
              },
              'gpa_projection': {'completed_credit_hours': 36},
              'graduation_path': {
                'remaining_courses': 1,
                'minimum_semesters_after_current': 1,
                'planned_semesters': [],
                'note': 'Prerequisite-valid path.',
              },
            }),
            200,
          );
        }
        expect(request.url.path, '/progress/STU001');
        return http.Response(
          jsonEncode({
            'semester': 'Fall 2026',
            'current_week': 1,
            'overall_academic_health': 30,
            'courses': [
              {
                'course_id': '13',
                'course_name': 'Digital Logic Design',
                'risk_level': 'medium',
                'metrics': {
                  'course_health': 30,
                  'lecture_completion': 0,
                  'assessment_completion': 25,
                },
                'risks': [
                  {
                    'message': 'Assignment average is 30%, below the configured 60% threshold.',
                  },
                ],
                'assessments': [
                  {
                    'name': 'Coursework',
                    'assessment_type': 'assignment',
                    'mark': 3,
                    'max_marks': 10,
                    'due_week': 5,
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomeScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Mohamed Ahmed',
            major: 'Computer Science',
            year: 2,
            gpa: 3.55,
            courses: ['Digital Logic Design'],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const Key('app-language-toggle')), findsOneWidget);
    expect(find.text('Academic alerts'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.text('Courses'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-messages')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('Campus communication'), findsOneWidget);
    expect(
      find.byKey(const Key('open-messages'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('open-meetings'), skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('Progress').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digital Logic Design'));
    await tester.pumpAndSettle();
    expect(find.text('Digital Logic Design risks'), findsOneWidget);
    expect(find.text('Fix This Risk'), findsOneWidget);
    expect(find.text('Add Study Session'), findsOneWidget);
    expect(
      find.text('This course already has a priority in Week Planner.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Add Study Session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Study Session'));
    await tester.pumpAndSettle();
    expect(find.text('Add study session'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Academics').last);
    await tester.pumpAndSettle();

    expect(find.text('Class Timetable'), findsOneWidget);
    expect(find.text('Grades'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-calendar')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Coursework'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('open-semester-planner')));
    await tester.pumpAndSettle();
    expect(find.text('Academic Roadmap'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-semester-planner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('semester-planner-page')), findsOneWidget);
    expect(find.text('Database Systems'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Schedule check'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Timetable data unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Accelerated Graduation Path'),
      400,
    );
    await tester.pumpAndSettle();
    expect(find.text('Accelerated Graduation Path'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Week Planner opens the weekly priorities screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taskCompleted = false;
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
        }
        if (request.url.path.endsWith('/weekly-plan')) {
          return http.Response(
            jsonEncode({
              'student_id': 'STU001',
              'semester': 'Fall 2026',
              'current_week': 5,
              'items': [
                {
                  'task_id': 'weekly:test-task',
                  'course_id': '13',
                  'course_name': 'Digital Logic Design',
                  'title': 'Review course performance',
                  'detail': 'Assignment average is below the threshold.',
                  'task_type': 'risk',
                  'status': taskCompleted ? 'completed' : 'pending',
                  'position': 1,
                  'completed_at': taskCompleted ? '2026-09-25T12:00:00Z' : null,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('/weekly-plan/')) {
          expect(request.method, 'PUT');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          taskCompleted = body['status'] == 'completed';
          return http.Response(
            jsonEncode({
              'item': {
                'task_id': 'weekly:test-task',
                'course_id': '13',
                'course_name': 'Digital Logic Design',
                'title': 'Review course performance',
                'detail': 'Assignment average is below the threshold.',
                'task_type': 'risk',
                'status': taskCompleted ? 'completed' : 'pending',
                'position': 1,
                'completed_at': taskCompleted ? '2026-09-25T12:00:00Z' : null,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'semester': 'Fall 2026',
            'current_week': 5,
            'overall_academic_health': 30,
            'courses': [
              {
                'course_id': '13',
                'course_name': 'Digital Logic Design',
                'risk_level': 'medium',
                'risks': [
                  {
                    'message': 'Assignment average is 30%, below the configured 60% threshold.',
                  },
                ],
                'assessments': [],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomeScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Mohamed Ahmed',
            major: 'Computer Science',
            year: 2,
            gpa: 3.55,
            courses: ['Digital Logic Design'],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fix-my-week')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weekly-plan-page')), findsOneWidget);
    expect(find.text('Week Planner'), findsOneWidget);
    expect(find.text('Aegis AI Advisor'), findsNothing);
    expect(find.textContaining('Digital Logic Design'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('weekly-task-checkbox-weekly:test-task')),
    );
    await tester.pumpAndSettle();

    expect(taskCompleted, isTrue);
    expect(find.text('Completed'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 / 1 priorities completed'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fix-my-week')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('weekly-task-checkbox-weekly:test-task')),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Academics opens the single Class Timetable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
        }
        if (request.url.path.endsWith('/schedule')) {
          return http.Response(
            jsonEncode({
              'student_id': 'STU001',
              'semester': 'Fall 2026',
              'group': {
                'id': 'group-2',
                'label': 'Computer Science · Semester 5 · Group 2',
                'major': 'Computer Science',
                'level_label': 'Semester 5',
                'number': 2,
                'size': 25,
                'capacity': 25,
                'automatic': true,
              },
              'schedule': {
                'schedule_id': 'group-2',
                'name': 'Computer Science · Semester 5 · Group 2',
                'semester': 'Fall 2026',
                'times_source': 'database',
                'slots': [
                  {
                    'course_id': 'CIS2101',
                    'course_name': 'Database Systems',
                    'day_of_week': 'Monday',
                    'start_minute': 720,
                    'end_minute': 810,
                    'location': 'Room B21',
                    'session_type': 'Lecture',
                    'provisional': false,
                  },
                ],
                'unscheduled_courses': [],
              },
              'classmates': [
                {'name': 'Aya Salem'},
              ],
              'group_size': 25,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/courses')) {
          return http.Response(
            jsonEncode({
              'course_count': 1,
              'schedule_published': true,
              'courses': [
                {
                  'course_code': 'CIS2101',
                  'course_name': 'Database Systems',
                  'status': 'Current',
                  'semester': 'Fall 2026',
                  'schedule': [
                    {
                      'day_of_week': 'Sunday',
                      'start_minute': 600,
                      'end_minute': 660,
                      'location': 'Room A12',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'semester': 'Fall 2026',
            'current_week': 5,
            'overall_academic_health': 80,
            'courses': [
              {
                'course_id': '21',
                'course_name': 'Database Systems',
                'risk_level': null,
                'assessments': [],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomeScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Mohamed Ahmed',
            major: 'Computer Science',
            year: 2,
            gpa: 3.55,
            courses: ['Database Systems'],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Academics').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-courses-from-hub')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('courses-schedule-page')), findsOneWidget);
    expect(find.text('Class Timetable'), findsOneWidget);
    expect(find.textContaining('Database Systems'), findsWidgets);
    expect(find.textContaining('12:00 PM'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Room B21'), findsOneWidget);
    expect(find.text('Group 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start a conversation opens an empty Advisor chat', (
    tester,
  ) async {
    var advisorRequests = 0;
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/advisor') {
          advisorRequests += 1;
          return http.Response(jsonEncode({'reply': 'Unexpected reply'}), 200);
        }
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
        }
        if (request.url.path.endsWith('/schedule')) {
          return http.Response(
            jsonEncode({
              'student_id': 'STU001',
              'semester': 'Fall 2026',
              'group': null,
              'schedule': null,
              'classmates': [],
              'group_size': null,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'semester': 'Fall 2026',
            'current_week': 5,
            'overall_academic_health': 80,
            'courses': [],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomeScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Mohamed Ahmed',
            major: 'Computer Science',
            year: 2,
            gpa: 3.55,
            courses: [],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI Advisor'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('open-advisor')), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-advisor')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisor-input')), findsOneWidget);
    expect(find.text('Help me plan my next semester'), findsOneWidget);
    expect(find.byKey(const Key('advisor-loading')), findsNothing);
    expect(advisorRequests, 0);
  });
}
