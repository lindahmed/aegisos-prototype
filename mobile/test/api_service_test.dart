import 'dart:convert';

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
}
