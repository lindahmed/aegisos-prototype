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
  String recognizedWords = 'What should I study next?';

  @override
  Future<bool> startListening({
    required String language,
    required void Function(String words) onResult,
  }) async {
    startCalls += 1;
    onResult(recognizedWords);
    return true;
  }

  @override
  Future<String> stopListening() async {
    stopCalls += 1;
    return recognizedWords;
  }

  @override
  Future<void> play(Uint8List audioBytes) async {
    playedAudio = audioBytes;
  }

  @override
  Future<void> cancelListening() async {}

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

  testWidgets('recognizes a voice question and plays the Advisor response', (
    tester,
  ) async {
    final voiceService = FakeAdvisorVoiceService();
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        if (request.url.path == '/advisor') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['student_id'], student.studentId);
          expect(body['message'], 'What should I study next?');
          return http.Response(
            jsonEncode({
              'intent': 'semester_planning',
              'response': 'Start with your required major courses.',
              'language': 'english',
            }),
            200,
          );
        }
        expect(request.url.path, '/advisor/speak');
        expect(
          request.url.queryParameters['text'],
          'Start with your required major courses.',
        );
        expect(request.url.queryParameters['language'], 'english');
        return http.Response(
          jsonEncode({
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
