import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_track_mobile/models/student.dart';
import 'package:uni_track_mobile/screens/meetings_screen.dart';

void main() {
  testWidgets('offers both host and join meeting paths', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MeetingsScreen(
          student: Student(
            studentId: 'STU001',
            name: 'Test Student',
            major: 'Computer Science',
            year: 3,
            gpa: 3.4,
            courses: [],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('meeting-title')), findsOneWidget);
    expect(find.byKey(const Key('host-meeting')), findsOneWidget);
    expect(find.byKey(const Key('meeting-invitation')), findsOneWidget);
    expect(find.byKey(const Key('join-meeting')), findsOneWidget);
    expect(find.text('Host or join a live meeting'), findsOneWidget);
  });
}
