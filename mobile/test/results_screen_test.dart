import 'dart:convert';

import 'package:advisor_ai_mobile/models/student.dart';
import 'package:advisor_ai_mobile/screens/results_screen.dart';
import 'package:advisor_ai_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders the database-backed results design', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = ApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'student': {'gpa': 3.4},
            'completed_courses': 12,
            'semesters': [
              {
                'semester': 'Fall 2026',
                'gpa': 4.0,
                'courses_graded': 1,
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
                'coursework_mark': 10,
                'week7_exam_mark': 30,
                'week12_exam_mark': 20,
                'final_exam_mark': 38,
                'total_score': 98,
                'letter_grade': 'A+',
                'gpa_points': 4,
                'grade_source': 'gradebook',
                'grade_posted': true,
              },
            ],
          }),
          200,
        ),
      ),
      baseUrl: 'https://api.example.test',
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          student: const Student(
            studentId: '231027905',
            name: 'Test Student',
            major: 'Computer Science',
            year: 3,
            gpa: 3.4,
            courses: ['Advanced statistics'],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Courses Achieved'), findsOneWidget);
    expect(find.text('Fall 2026'), findsOneWidget);
    expect(find.text('CCS3201'), findsOneWidget);
    expect(find.text('Advanced statistics'), findsOneWidget);
    expect(find.text('A+'), findsOneWidget);
    final scaffoldContext = tester.element(find.byType(Scaffold));
    final activeTheme = Theme.of(scaffoldContext);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      activeTheme.scaffoldBackgroundColor,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      activeTheme.colorScheme.surface,
    );
    expect(tester.takeException(), isNull);
  });
}
