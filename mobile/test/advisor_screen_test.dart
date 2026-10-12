import 'dart:convert';
import 'dart:typed_data';

import 'package:uni_track_mobile/models/student.dart';
import 'package:uni_track_mobile/localization/app_language.dart';
import 'package:uni_track_mobile/screens/advisor_screen.dart';
import 'package:uni_track_mobile/services/api_service.dart';
import 'package:uni_track_mobile/services/advisor_voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAdvisorVoiceService implements AdvisorVoiceService {
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int stopPlaybackCalls = 0;
  Uint8List? playedAudio;
  void Function()? playbackComplete;
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
  Future<void> play(Uint8List audioBytes, {void Function()? onComplete}) async {
    playedAudio = audioBytes;
    playbackComplete = onComplete;
  }

  @override
  Future<void> cancelListening() async {
    cancelCalls += 1;
  }

  @override
  Future<void> stopPlayback() async {
    stopPlaybackCalls += 1;
    playbackComplete = null;
  }

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

  setUp(() => appLanguageController.value = const Locale('en'));

  testWidgets('asks Advisor AI and displays its response', (tester) async {
    final voiceService = FakeAdvisorVoiceService();
    String? lastLanguage;
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/weekly-plan')) {
          return http.Response(
            jsonEncode({
              'student_id': student.studentId,
              'semester': 'Fall 2026',
              'current_week': 5,
              'items': <dynamic>[],
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lastLanguage = body['language'] as String?;
        expect(body['student_id'], student.studentId);
        if (body['message'] == 'مرحبا') {
          return http.Response(
            jsonEncode({
              'intent': 'general',
              'response': 'مرحبًا، كيف أساعدك؟',
              'language': 'arabic',
            }),
            200,
          );
        }
        expect(body['message'], 'What careers fit me?');
        expect(body['language'], 'english');
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
    expect(find.byKey(const Key('advisor-language-english')), findsNothing);
    expect(find.byKey(const Key('advisor-language-arabic')), findsNothing);

    await tester.tap(find.byKey(const Key('advisor-action-addStudySession')));
    await tester.pumpAndSettle();
    expect(find.text('Add study session'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('advisor-input')), 'مرحبا');
    await tester.tap(find.byKey(const Key('advisor-send')));
    await tester.pumpAndSettle();
    expect(lastLanguage, 'arabic');
    service.close();
  });

  testWidgets('uses live progress when the remote Advisor is unavailable', (
    tester,
  ) async {
    final voiceService = FakeAdvisorVoiceService();
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/advisor') {
          return http.Response(
            jsonEncode({
              'detail': 'Advisor AI could not complete the request.',
            }),
            502,
          );
        }
        expect(request.url.path, '/progress/${student.studentId}');
        return http.Response(
          jsonEncode({
            'current_week': 6,
            'overall_academic_health': 72,
            'courses': [
              {
                'course_name': 'Artificial Intelligence',
                'risk_level': 'medium',
                'risks': [
                  {'message': 'Lecture completion needs attention.'},
                ],
              },
            ],
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
      'What should I study?',
    );
    await tester.tap(find.byKey(const Key('advisor-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisor-error')), findsNothing);
    expect(find.textContaining('Artificial Intelligence'), findsOneWidget);
    expect(find.textContaining('Lecture completion'), findsOneWidget);
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
    expect(find.byKey(const Key('advisor-speaking')), findsOneWidget);

    await tester.tap(find.byKey(const Key('advisor-stop-speaking')));
    await tester.pumpAndSettle();

    expect(voiceService.stopPlaybackCalls, 1);
    expect(find.byKey(const Key('advisor-speaking')), findsNothing);
    service.close();
  });

  testWidgets('discards a voice recording without sending it', (tester) async {
    final voiceService = FakeAdvisorVoiceService();
    var requestCalls = 0;
    final service = ApiService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        requestCalls += 1;
        return http.Response('{}', 500);
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

    expect(find.byKey(const Key('advisor-recording')), findsOneWidget);
    expect(find.byKey(const Key('advisor-discard-recording')), findsOneWidget);

    await tester.tap(find.byKey(const Key('advisor-discard-recording')));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(const Key('advisor-input')),
    );
    expect(voiceService.cancelCalls, 1);
    expect(input.controller?.text, isEmpty);
    expect(find.byKey(const Key('advisor-recording')), findsNothing);
    expect(find.byKey(const Key('advisor-message-list')), findsNothing);
    expect(requestCalls, 0);
    service.close();
  });
}
