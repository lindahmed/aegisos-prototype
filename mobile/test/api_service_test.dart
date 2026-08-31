import 'dart:convert';

import 'package:advisor_ai_mobile/models/advisor_message.dart';
import 'package:advisor_ai_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads a student from the AegisOS API and accepts a null GPA', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.example.test/student/231027905');
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
      client: MockClient((_) async => http.Response('{"detail":"Student not found"}', 404)),
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

  test('sends student context and conversation history to Advisor AI', () async {
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
  });
}
