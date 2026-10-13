import 'package:uni_track_mobile/main.dart';
import 'package:uni_track_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    appThemeMode.value = ThemeMode.light;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the database-backed student login', (tester) async {
    await tester.pumpWidget(const UniTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('UNI TRACK'), findsOneWidget);
    expect(find.text('Guide. Track. Evolve.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Student ID'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
  });

  testWidgets('restores a remembered student ID without storing a password', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'remember_student_enabled': true,
      'remember_student_id': '231003445',
    });

    await tester.pumpWidget(const UniTrackApp());
    await tester.pumpAndSettle();

    final studentIdField = tester.widget<TextField>(
      find.byKey(const Key('login-student-id')),
    );
    final passwordField = tester.widget<TextField>(
      find.byKey(const Key('login-password')),
    );
    expect(studentIdField.controller?.text, '231003445');
    expect(passwordField.controller?.text, isEmpty);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('login-remember-me'))).value,
      isTrue,
    );
  });

  testWidgets('requires a password after the student ID', (tester) async {
    await tester.pumpWidget(const UniTrackApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login-student-id')),
      '231027905',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('requires a student ID before calling the API', (tester) async {
    await tester.pumpWidget(const UniTrackApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your student ID.'), findsOneWidget);
  });

  testWidgets('switches the complete app between light and dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(const UniTrackApp());
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    await tester.tap(find.byKey(const Key('theme-mode-toggle')));
    await tester.pumpAndSettle();

    expect(appThemeMode.value, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
  });
}
