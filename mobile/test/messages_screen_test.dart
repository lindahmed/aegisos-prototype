import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uni_track_mobile/models/student.dart';
import 'package:uni_track_mobile/screens/messages_screen.dart';
import 'package:uni_track_mobile/services/api_service.dart';

void main() {
  testWidgets('opens a real conversation and sends a message', (tester) async {
    final messages = <Map<String, dynamic>>[
      {
        'message_id': 'MSG001',
        'sender_type': 'staff',
        'sender_id': 'PROF001',
        'sender_name': 'Dr. Salma',
        'recipient_type': 'student',
        'recipient_id': 'STU001',
        'recipient_name': 'Test Student',
        'is_broadcast': false,
        'body': 'Please review chapter four.',
        'created_at': '2026-10-08T10:00:00Z',
        'read': false,
      },
    ];
    final service = ApiService(
      client: MockClient((request) async {
        if (request.url.path == '/messages/contacts') {
          return http.Response(
            jsonEncode({
              'contacts': [
                {
                  'type': 'staff',
                  'id': 'PROF001',
                  'name': 'Dr. Salma',
                  'subtitle': 'Professor · Computer Science',
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path == '/messages') {
          return http.Response(jsonEncode({'messages': messages}), 200);
        }
        if (request.method == 'PUT' && request.url.path == '/messages/read') {
          return http.Response(
            jsonEncode({
              'read': ['MSG001'],
            }),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/messages') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final message = {
            'message_id': 'MSG002',
            'sender_type': 'student',
            'sender_id': 'STU001',
            'sender_name': 'Test Student',
            'recipient_type': 'staff',
            'recipient_id': 'PROF001',
            'recipient_name': 'Dr. Salma',
            'is_broadcast': false,
            'body': payload['body'],
            'created_at': '2026-10-08T10:05:00Z',
            'read': true,
          };
          messages.add(message);
          return http.Response(jsonEncode({'message': message}), 200);
        }
        return http.Response('Not found', 404);
      }),
      baseUrl: 'https://api.example.test',
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(
          student: const Student(
            studentId: 'STU001',
            name: 'Test Student',
            major: 'Computer Science',
            year: 3,
            gpa: 3.5,
            courses: [],
          ),
          apiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dr. Salma'), findsOneWidget);
    expect(find.text('Please review chapter four.'), findsOneWidget);
    await tester.tap(find.text('Dr. Salma'));
    await tester.pumpAndSettle();
    expect(find.text('Please review chapter four.'), findsOneWidget);
    expect(find.byKey(const Key('attach-message-document')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'Thank you, I will.',
    );
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();

    expect(find.text('Thank you, I will.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
