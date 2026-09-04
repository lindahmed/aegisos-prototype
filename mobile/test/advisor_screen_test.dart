import 'dart:convert';
import 'dart:typed_data';

import 'package:advisor_ai_mobile/models/student.dart';
import 'package:advisor_ai_mobile/screens/advisor_screen.dart';
import 'package:advisor_ai_mobile/services/api_service.dart';
import 'package:advisor_ai_mobile/services/advisor_voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAdvisorVoiceService implements AdvisorVoiceService {
  int startCalls = 0;
  int stopCalls = 0;
  Uint8List? playedAudio;

  @override
  Future<bool> startRecording() async {
    startCalls += 1;
    return true;
  }

  @override
  Future<Uint8List?> stopRecording() async {
    stopCalls += 1;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> play(Uint8List audioBytes) async {
    playedAudio = audioBytes;
  }

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}
}

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
    final voiceService = FakeAdvisorVoiceService();
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
        home: AdvisorScreen(
          student: student,
          apiService: service,
          voiceService: voiceService,
        ),
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

  testWidgets('records a voice question and plays the Advisor response', (
    tester,
  ) async {
    final voiceService = FakeAdvisorVoiceService();
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.example.test/advisor/voice',
        );
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.body, contains('231027905'));
        expect(request.body, contains('english'));
        expect(request.body, contains('advisor_voice.wav'));
        return http.Response(
          jsonEncode({
            'student_id': student.studentId,
            'transcript': 'What should I study next?',
            'intent': 'semester_planning',
            'response': 'Start with your required major courses.',
            'language': 'english',
            'audio_base64': base64Encode([4, 5, 6]),
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdvisorScreen(
          student: student,
          apiService: service,
          voiceService: voiceService,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('advisor-voice')));
    await tester.pump();

    expect(voiceService.startCalls, 1);
    expect(find.byKey(const Key('advisor-recording')), findsOneWidget);

    await tester.tap(find.byKey(const Key('advisor-voice')));
    await tester.pumpAndSettle();

    expect(voiceService.stopCalls, 1);
    expect(find.text('What should I study next?'), findsOneWidget);
    expect(
      find.text('Start with your required major courses.'),
      findsOneWidget,
    );
    expect(voiceService.playedAudio, Uint8List.fromList([4, 5, 6]));
    service.close();
  });
}
