import 'package:advisor_ai_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the database-backed student login', (tester) async {
    await tester.pumpWidget(const AdvisorAIApp());

    expect(find.text('Welcome to AegisOS'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Student ID'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('requires a student ID before calling the API', (tester) async {
    await tester.pumpWidget(const AdvisorAIApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your student ID.'), findsOneWidget);
  });
}
