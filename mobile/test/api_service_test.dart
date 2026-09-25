import 'dart:async';
import 'dart:convert';

import 'package:uni_track_mobile/models/advisor_message.dart';
import 'package:uni_track_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('coalesces in-flight reads and reuses a fresh response', () async {
    var requestCount = 0;
    final firstResponse = Completer<http.Response>();
    final response = http.Response(
      jsonEncode({
        'student_id': 'STU001',
        'name': 'Test Student',
        'major': 'Computer Science',
        'year': 4,
        'gpa': 3.55,
        'courses': <String>[],
      }),
      200,
    );
    final service = ApiService(
      client: MockClient((_) {
        requestCount += 1;
        return requestCount == 1
            ? firstResponse.future
            : Future.value(response);
      }),
      baseUrl: 'https://api.example.test',
    );

    final first = service.getStudent('STU001');
    final duplicate = service.getStudent('STU001');
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);

    firstResponse.complete(response);
    await Future.wait([first, duplicate]);
    await service.getStudent('STU001');
    expect(requestCount, 1);

    await service.getStudent('STU001', forceRefresh: true);
    expect(requestCount, 2);
    service.close();
  });

  test('calendar reuses the dashboard progress response', () async {
    var requestCount = 0;
    final service = ApiService(
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.url.path, '/progress/STU001');
        return http.Response(
          jsonEncode({
            'student': {
              'student_id': 'STU001',
              'name': 'Test Student',
              'major': 'Computer Science',
              'year': 4,
              'gpa': 3.55,
              'courses': <String>[],
            },
            'semester': 'Current semester',
            'current_week': 5,
            'courses': <Object>[],
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    await service.getStudentProgress('STU001');
    await service.getStudentAcademics('STU001');

    expect(requestCount, 1);
    service.close();
  });

  test('loads a student from the AegisOS API and accepts a null GPA', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.test/student/231027905',
      );
      return http.Response(
        jsonEncode({
          'student_id': '231027905',
          'name': 'Test Student',
          'major': 'Computer Science',
          'year': 3,
          'gpa': null,
          'courses': ['Artificial Intelligence'],
        }),
        200,
      );
    });
    final service = ApiService(
      client: client,
      baseUrl: 'https://api.example.test/',
    );

    final student = await service.getStudent(' 231027905 ');

    expect(student.studentId, '231027905');
    expect(student.gpa, isNull);
    expect(student.courses, ['Artificial Intelligence']);
    service.close();
  });

  test('reports an unknown student ID', () async {
    final service = ApiService(
      client: MockClient(
        (_) async => http.Response('{"detail":"Student not found"}', 404),
      ),
      baseUrl: 'https://api.example.test',
    );

    await expectLater(
      service.getStudent('missing'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Student ID not found.',
        ),
      ),
    );
    service.close();
  });

  test('does not misreport a wrong API server as an unknown student', () async {
    final service = ApiService(
      client: MockClient(
        (_) async => http.Response('{"detail":"Not Found"}', 404),
      ),
      baseUrl: 'https://wrong-server.example.test',
    );

    await expectLater(
      service.getStudent('STU001'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'The configured address is not the UNI Track service. Check the API URL.',
        ),
      ),
    );
    service.close();
  });

  test(
    'sends student context and conversation history to Advisor AI',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://api.example.test/advisor');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['student_id'], '231027905');
        expect(body['message'], 'What careers match my major?');
        expect(body['language'], 'english');
        expect(body['history'], [
          {'role': 'user', 'content': 'Help me plan next semester'},
          {'role': 'assistant', 'content': 'Start with your required courses.'},
        ]);
        return http.Response(
          jsonEncode({
            'intent': 'career_guidance',
            'response': 'Consider roles that use AI and software engineering.',
            'language': 'english',
          }),
          200,
        );
      });
      final service = ApiService(
        client: client,
        baseUrl: 'https://api.example.test',
      );

      final reply = await service.askAdvisor(
        studentId: '231027905',
        message: 'What careers match my major?',
        history: const [
          AdvisorMessage.user('Help me plan next semester'),
          AdvisorMessage.assistant('Start with your required courses.'),
        ],
      );

      expect(reply.intent, 'career_guidance');
      expect(
        reply.response,
        'Consider roles that use AI and software engineering.',
      );
      service.close();
    },
  );

  test('loads notifications from the shared student feed', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/231027905/notifications',
        );
        return http.Response(
          jsonEncode({
            'notifications': [
              {
                'id': 'grade:ai:Fall 2026:86.30',
                'type': 'grade',
                'category': 'Grades',
                'title': 'Grade posted: Artificial Intelligence',
                'body': 'B · 86.3% overall',
                'timestamp': 'Fall 2026',
                'read': false,
              },
            ],
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    final notifications = await service.getStudentNotifications('231027905');

    expect(notifications, hasLength(1));
    expect(notifications.single.type, 'grade');
    expect(notifications.single.read, isFalse);
    service.close();
  });

  test('loads nullable database-backed grade records', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/231027905/grades',
        );
        return http.Response(
          jsonEncode({
            'student': {'gpa': 3.4},
            'completed_courses': 12,
            'semesters': [
              {
                'semester': 'Fall 2026',
                'gpa': null,
                'courses_graded': 0,
                'standing': 'In Progress',
              },
            ],
            'records': [
              {
                'course_id': '12',
                'course_code': 'CCS3201',
                'course_name': 'Advanced statistics',
                'semester': 'Fall 2026',
                'enrollment_status': 'Current',
                'coursework_mark': null,
                'week7_exam_mark': null,
                'week12_exam_mark': null,
                'final_exam_mark': null,
                'total_score': null,
                'letter_grade': null,
                'gpa_points': null,
                'grade_source': 'none',
                'grade_posted': false,
              },
            ],
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    final report = await service.getStudentGrades('231027905');

    expect(report.cumulativeGpa, 3.4);
    expect(report.completedCourses, 12);
    expect(report.semesters.single.gpa, isNull);
    expect(report.records.single.courseCode, 'CCS3201');
    expect(report.records.single.courseworkMark, isNull);
    expect(report.records.single.gradePosted, isFalse);
    service.close();
  });

  test('loads registered courses with university schedule slots', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/STU001/courses',
        );
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
      }),
      baseUrl: 'https://api.example.test',
    );

    final report = await service.getStudentCourses('STU001');

    expect(report.courseCount, 1);
    expect(report.schedulePublished, isTrue);
    expect(report.courses.single.name, 'Database Systems');
    expect(
      report.courses.single.schedule.single.timeLabel,
      '10:00 AM–11:00 AM',
    );
    service.close();
  });

  test('updates shared notification read state', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(
        request.url.toString(),
        'https://api.example.test/portal/students/231027905/notifications/read',
      );
      expect(jsonDecode(request.body), {
        'notification_ids': ['exam:ai-final'],
        'read': true,
      });
      return http.Response(
        jsonEncode({
          'notifications': [
            {
              'id': 'exam:ai-final',
              'type': 'exam',
              'category': 'Registration',
              'title': 'Upcoming final: Final',
              'body': 'Artificial Intelligence · week 12',
              'timestamp': 'Week 12',
              'read': true,
            },
          ],
        }),
        200,
      );
    });
    final service = ApiService(
      client: client,
      baseUrl: 'https://api.example.test',
    );

    final notifications = await service.setNotificationsRead(
      studentId: '231027905',
      notificationIds: ['exam:ai-final'],
      read: true,
    );

    expect(notifications.single.read, isTrue);
    service.close();
  });

  test('loads a database-backed weekly plan', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/231027905/weekly-plan',
        );
        return http.Response(
          jsonEncode({
            'student_id': '231027905',
            'semester': 'Fall 2026',
            'current_week': 6,
            'items': [
              {
                'task_id': 'weekly:abc123',
                'course_id': 'ai',
                'course_name': 'Artificial Intelligence',
                'title': 'Prepare for Week 7 exam',
                'detail': 'Due next week.',
                'task_type': 'assessment',
                'status': 'pending',
                'position': 1,
                'completed_at': null,
              },
            ],
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    final plan = await service.getWeeklyPlan('231027905');

    expect(plan.currentWeek, 6);
    expect(plan.items.single.taskId, 'weekly:abc123');
    expect(plan.items.single.isCompleted, isFalse);
    service.close();
  });

  test('saves a weekly task completion status', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/231027905/weekly-plan/weekly%3Aabc123',
        );
        expect(jsonDecode(request.body), {'status': 'completed'});
        return http.Response(
          jsonEncode({
            'item': {
              'task_id': 'weekly:abc123',
              'course_id': 'ai',
              'course_name': 'Artificial Intelligence',
              'title': 'Prepare for Week 7 exam',
              'detail': 'Due next week.',
              'task_type': 'assessment',
              'status': 'completed',
              'position': 1,
              'completed_at': '2026-09-25T12:00:00Z',
            },
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    final item = await service.setWeeklyPlanItemStatus(
      studentId: '231027905',
      taskId: 'weekly:abc123',
      completed: true,
    );

    expect(item.isCompleted, isTrue);
    expect(item.completedAt, isNotNull);
    service.close();
  });

  test('loads the database-backed smart semester plan', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.example.test/portal/students/STU001/semester-plan?max_credits=18',
        );
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
                'course_type': 'Required',
                'credit_hours': 3,
                'eligibility': 'eligible',
                'prerequisites': [],
                'schedule': [],
              },
            ],
            'candidate_courses': [],
            'credit_policy': {'note': 'Estimated credits'},
            'conflict_check': {
              'status': 'unavailable',
              'note': 'No timetable data',
            },
            'gpa_projection': {'completed_credit_hours': 36},
            'graduation_path': {
              'remaining_courses': 28,
              'minimum_semesters_after_current': 5,
              'planned_semesters': [],
              'note': 'Prerequisite-valid path',
            },
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.test',
    );

    final plan = await service.getSemesterPlan('STU001');

    expect(plan.nextSemester, 4);
    expect(plan.recommendedCourses.single.code, 'CIS2101');
    expect(plan.minimumSemesters, 5);
    service.close();
  });

  test('parses selectable graduation routes and half-load policy', () async {
    final service = ApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'current_semester': 6,
            'next_semester': 7,
            'maximum_program_semesters': 8,
            'program_semesters_remaining': 2,
            'current_gpa': 1.8,
            'maximum_credit_hours': 9,
            'recommended_courses': [],
            'candidate_courses': [],
            'credit_policy': {'note': 'Half load'},
            'conflict_check': {'status': 'unavailable', 'note': ''},
            'gpa_projection': {'completed_credit_hours': 60},
            'graduation_path': {
              'remaining_courses': 10,
              'minimum_semesters_after_current': 2,
              'fits_standard_program_length': false,
              'planned_semesters': [],
              'note': 'Extension required',
            },
            'graduation_options': {
              'half_load': true,
              'accelerated_allowed': false,
              'student_status': 'half_load',
              'best_option_id': 'normal',
              'fastest_option_id': null,
              'policy_note': 'GPA below 2.0 requires half load.',
              'options': [
                {
                  'id': 'normal',
                  'title': 'Half-load route',
                  'available': true,
                  'maximum_regular_credits': 9,
                  'summer_credits': 0,
                  'regular_semesters': 4,
                  'summer_terms': 0,
                  'extension_terms': 2,
                  'total_terms': 4,
                  'saves_regular_semesters': 0,
                  'on_time': false,
                  'note': 'Reduced load',
                  'terms': [
                    {
                      'label': 'Extension term 1',
                      'term_type': 'extension',
                      'semester_number': null,
                      'credit_hours': 9,
                      'courses': [],
                    },
                  ],
                },
                {
                  'id': 'summer_3',
                  'title': 'Summer 3',
                  'available': false,
                  'summer_after_semester': 6,
                  'note': 'Unavailable',
                  'terms': [],
                },
              ],
            },
          }),
          200,
        ),
      ),
      baseUrl: 'https://api.example.test',
    );

    final plan = await service.getSemesterPlan('STU009');

    expect(plan.halfLoad, isTrue);
    expect(plan.acceleratedAllowed, isFalse);
    expect(plan.maximumCreditHours, 9);
    expect(plan.bestOptionId, 'normal');
    expect(plan.graduationOptions.first.extensionTerms, 2);
    expect(plan.graduationOptions.first.terms.single.label, 'Extension term 1');
    expect(plan.graduationOptions.last.available, isFalse);
    expect(plan.graduationOptions.last.summerAfterSemester, 6);
    service.close();
  });

  test('caps a legacy year-four planner response at semester eight', () async {
    final service = ApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'current_semester': 7,
            'next_semester': 8,
            'current_gpa': 3.57,
            'maximum_credit_hours': 18,
            'recommended_courses': [
              {
                'course_id': 'CCS1101',
                'course_code': 'CCS1101',
                'course_name': 'Introduction to Computing',
                'curriculum_semester': 1,
                'credit_hours': 3,
                'eligibility': 'eligible',
                'prerequisites': [],
                'schedule': [],
              },
            ],
            'candidate_courses': [
              {
                'course_id': 'CCS1101',
                'course_code': 'CCS1101',
                'course_name': 'Introduction to Computing',
                'curriculum_semester': 1,
                'credit_hours': 3,
                'eligibility': 'eligible',
                'prerequisites': [],
                'schedule': [],
              },
              {
                'course_id': 'CCS4901',
                'course_code': 'CCS4901',
                'course_name': 'Project I',
                'curriculum_semester': 7,
                'credit_hours': 3,
                'eligibility': 'eligible',
                'prerequisites': [],
                'schedule': [],
              },
            ],
            'credit_policy': {'note': 'Estimated credits'},
            'conflict_check': {'status': 'unavailable', 'note': ''},
            'gpa_projection': {'completed_credit_hours': 0},
            'graduation_path': {
              'remaining_courses': 51,
              'minimum_semesters_after_current': 8,
              'planned_semesters': [
                {
                  'semester_number': 8,
                  'credit_hours': 3,
                  'courses': [
                    {
                      'course_id': 'CCS1101',
                      'course_code': 'CCS1101',
                      'course_name': 'Introduction to Computing',
                      'curriculum_semester': 1,
                      'credit_hours': 3,
                      'eligibility': 'eligible',
                      'prerequisites': [],
                      'schedule': [],
                    },
                  ],
                },
                {'semester_number': 9, 'credit_hours': 3, 'courses': []},
              ],
              'note': 'Legacy response',
            },
          }),
          200,
        ),
      ),
      baseUrl: 'https://api.example.test',
    );

    final plan = await service.getSemesterPlan('STU005');

    expect(plan.maximumProgramSemesters, 8);
    expect(plan.minimumSemesters, 1);
    expect(plan.candidateCourses.map((course) => course.code), ['CCS4901']);
    expect(plan.recommendedCourses.map((course) => course.code), ['CCS4901']);
    expect(
      plan.path.every(
        (term) => term.semesterNumber == null || term.semesterNumber! <= 8,
      ),
      isTrue,
    );
    service.close();
  });
}
