import 'dart:convert';

import 'package:advisor_ai_mobile/models/student.dart';
import 'package:advisor_ai_mobile/screens/advisor_screen.dart';
import 'package:advisor_ai_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const student = Student(
    studentId: '231027905',
    name: 'Test Student',
    major: 'Computer Science',
    year: 3,
    gpa: 3.5,
    courses: ['Artificial Intelligence'],
  );

  testWidgets('asks Advisor AI and displays its response', (tester) async {
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['student_id'], student.studentId);
        expect(body['message'], 'What careers fit me?');
        return http.Response(
          jsonEncode({
            'intent': 'career_guidance',
            'response': 'Explore software engineering and AI roles.',
            'language': 'english',
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdvisorScreen(student: student, apiService: service),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('advisor-input')),
      'What careers fit me?',
    );
    await tester.tap(find.byKey(const Key('advisor-send')));
    await tester.pumpAndSettle();

    expect(find.text('What careers fit me?'), findsOneWidget);
    expect(
      find.text('Explore software engineering and AI roles.'),
      findsOneWidget,
    );
    service.close();
  });
}
