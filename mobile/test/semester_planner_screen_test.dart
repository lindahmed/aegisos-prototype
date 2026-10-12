import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uni_track_mobile/models/student.dart';
import 'package:uni_track_mobile/screens/semester_planner_screen.dart';
import 'package:uni_track_mobile/services/api_service.dart';

void main() {
  testWidgets('replaces a half-load course without exceeding nine credits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Map<String, dynamic> course(String id, String name) => {
      'course_id': id,
      'course_code': 'CIS$id',
      'course_name': name,
      'curriculum_semester': 6,
      'course_type': 'Required',
      'credit_hours': 3,
      'eligibility': 'eligible',
      'prerequisites': <dynamic>[],
      'schedule': <dynamic>[],
    };

    final recommended = [
      course('31', 'Course One'),
      course('32', 'Course Two'),
      course('33', 'Course Three'),
    ];
    final candidate = [...recommended, course('34', 'Course Four')];
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'current_semester': 5,
            'next_semester': 6,
            'maximum_program_semesters': 8,
            'program_semesters_remaining': 3,
            'current_gpa': 1.8,
            'maximum_credit_hours': 9,
            'recommended_courses': recommended,
            'candidate_courses': candidate,
            'credit_policy': {'note': 'Half load'},
            'conflict_check': {
              'status': 'unavailable',
              'note': 'Timetable data unavailable',
            },
            'gpa_projection': {'completed_credit_hours': 60},
            'graduation_path': {
              'remaining_courses': 4,
              'minimum_semesters_after_current': 2,
              'fits_standard_program_length': true,
              'planned_semesters': <dynamic>[],
              'note': 'Half-load route',
            },
            'graduation_options': {
              'half_load': true,
              'accelerated_allowed': false,
              'student_status': 'half_load',
              'best_option_id': 'normal',
              'policy_note': 'Nine-credit maximum',
              'options': [
                {
                  'id': 'normal',
                  'title': 'Normal route',
                  'available': true,
                  'maximum_regular_credits': 9,
                  'regular_semesters': 2,
                  'summer_terms': 0,
                  'extension_terms': 0,
                  'total_terms': 2,
                  'saves_regular_semesters': 0,
                  'on_time': true,
                  'note': 'Half-load route',
                  'terms': <dynamic>[],
                },
              ],
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SemesterPlannerScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Test Student',
            major: 'Computer Science',
            year: 3,
            gpa: 1.8,
            courses: [],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Other curriculum courses'), 300);
    await tester.tap(find.text('Other curriculum courses'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Course Four'), 300);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();

    final courseFourCheckbox = tester.widget<Checkbox>(
      find.byType(Checkbox).last,
    );
    expect(courseFourCheckbox.value, isTrue);
    expect(find.textContaining('Half-load limit:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
