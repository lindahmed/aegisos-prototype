import 'dart:convert';

import 'package:advisor_ai_mobile/models/student.dart';
import 'package:advisor_ai_mobile/screens/student_home_screen.dart';
import 'package:advisor_ai_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('keeps Results and displays STU001 coursework as 3/10', (
    tester,
  ) async {
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
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

    await tester.tap(find.text('Academics').last);
    await tester.pumpAndSettle();

    expect(find.text('Coursework'), findsOneWidget);
    expect(find.text('3/10'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Smart Semester Planner'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('open-semester-planner')));
    await tester.tap(find.byKey(const Key('open-semester-planner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('semester-planner-page')), findsOneWidget);
    expect(find.text('Database Systems'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Schedule check'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Timetable data unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Best Graduation Path'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Best Graduation Path'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fix My Week opens the weekly plan instead of Advisor AI', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
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
    expect(find.text('Fix My Week'), findsOneWidget);
    expect(find.text('Advisor AI'), findsNothing);
    expect(find.textContaining('Digital Logic Design'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Courses dashboard card opens courses and university schedule', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) {
          return http.Response(jsonEncode({'notifications': []}), 200);
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

    await tester.tap(find.byKey(const Key('open-courses')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('courses-schedule-page')), findsOneWidget);
    expect(find.text('My Courses & Schedule'), findsOneWidget);
    expect(find.textContaining('Database Systems'), findsWidgets);
    expect(find.textContaining('10:00 AM'), findsWidgets);
    expect(find.textContaining('Room A12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
