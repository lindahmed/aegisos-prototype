import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_track_mobile/localization/app_language.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appLanguageController.value = const Locale('en');
  });

  test('saves and restores the selected application language', () async {
    await appLanguageController.setLanguage('ar');
    expect(appLanguageController.value.languageCode, 'ar');

    appLanguageController.value = const Locale('en');
    await appLanguageController.load();

    expect(appLanguageController.value.languageCode, 'ar');
  });

  testWidgets('translates shared application text when Arabic is selected', (
    tester,
  ) async {
    appLanguageController.value = const Locale('ar');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppText('Home'))),
    );

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('updates visible text immediately in both directions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppLanguageToggleButton(),
              AppText('Start a conversation'),
              AppText(
                'Ask about your courses, grades, risks, timetable, or study priorities. Answers use your current academic data.',
              ),
              AppText('Classes and grades'),
              AppText('Planning tools'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Start a conversation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-language-toggle')));
    await tester.pump();
    expect(find.text('ابدئي محادثة'), findsOneWidget);
    expect(find.textContaining('اسألي عن المقررات'), findsOneWidget);
    expect(find.text('المحاضرات والدرجات'), findsOneWidget);
    expect(find.text('أدوات التخطيط'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-language-toggle')));
    await tester.pump();
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('ابدئي محادثة'), findsNothing);
  });

  test('translates generated Week Planner content to Arabic', () {
    appLanguageController.value = const Locale('ar');

    expect(tr('Digital Image Processing'), 'Digital Image Processing');
    expect(tr('1. Digital Image Processing'), '1. Digital Image Processing');
    expect(
      tr('Review Digital Image Processing mistakes'),
      'راجعي أخطاء Digital Image Processing',
    );
    expect(
      tr(
        'Today · 45 min — choose the two weakest topics, review one worked example for each, then solve one question alone.',
      ),
      'اليوم · 45 دقيقة — اختاري أضعف موضوعين، وراجعي مثالًا محلولًا لكل منهما، ثم حلي سؤالًا بنفسك.',
    );
    expect(
      tr('Assignment average is 30%, below the configured 60% threshold.'),
      'متوسط التكليفات 30٪، وهو أقل من الحد المحدد 60٪.',
    );
    expect(
      tr('Digital Image Processing risks'),
      'مخاطر Digital Image Processing',
    );
  });

  test('translates live meeting controls and generated counts', () {
    appLanguageController.value = const Locale('ar');

    expect(tr('Live Meetings'), 'الاجتماعات المباشرة');
    expect(tr('Request to join'), 'طلب الانضمام');
    expect(tr('Share screen'), 'مشاركة الشاشة');
    expect(tr('3 in meeting'), '3 في الاجتماع');
    expect(tr('2 admitted · 1 waiting'), '2 مشاركون · 1 في الانتظار');
  });
}
