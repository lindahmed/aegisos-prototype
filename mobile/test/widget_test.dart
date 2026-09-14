import 'package:uni_track_mobile/main.dart';
import 'package:uni_track_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appThemeMode.value = ThemeMode.light);

  testWidgets('shows the database-backed student login', (tester) async {
    await tester.pumpWidget(const UniTrackApp());

    expect(find.text('UNI TRACK'), findsOneWidget);
    expect(find.text('Guide. Track. Evolve.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Student ID'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('requires a student ID before calling the API', (tester) async {
    await tester.pumpWidget(const UniTrackApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your student ID.'), findsOneWidget);
  });

  testWidgets('switches the complete app between light and dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(const UniTrackApp());

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
