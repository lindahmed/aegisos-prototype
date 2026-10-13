import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_track_mobile/models/calendar_event.dart';
import 'package:uni_track_mobile/models/weekly_plan.dart';
import 'package:uni_track_mobile/widgets/today_dashboard_card.dart';

void main() {
  testWidgets('Today shows today calendar events instead of a week-plan task', (
    tester,
  ) async {
    final now = DateTime.now();
    final event = StudentCalendarEvent(
      id: 'today-event',
      title: 'Study Digital Image Processing',
      description: 'Calendar study session',
      startAt: DateTime(now.year, now.month, now.day, 18),
      endAt: DateTime(now.year, now.month, now.day, 19),
      type: StudentCalendarEventType.studySession,
      source: StudentCalendarEventSource.student,
    );
    const plan = WeeklyPlan(
      studentId: 'STU001',
      semester: 'Fall 2026',
      currentWeek: 5,
      items: [
        WeeklyPlanItem(
          taskId: 'task-1',
          courseId: '13',
          courseName: 'Weekly Priority Course',
          title: 'Review a lecture',
          detail: 'Today · 45 min',
          taskType: 'risk',
          status: 'pending',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayDashboardCard(
            progress: null,
            weeklyPlan: plan,
            localEvents: [event],
            onAskAegis: () {},
          ),
        ),
      ),
    );

    expect(find.text("TODAY'S CALENDAR"), findsOneWidget);
    expect(
      find.textContaining('Study Digital Image Processing'),
      findsOneWidget,
    );
    expect(find.textContaining('Week Planner:'), findsNothing);
    expect(find.text('No Calendar events scheduled for today.'), findsNothing);
  });
}
