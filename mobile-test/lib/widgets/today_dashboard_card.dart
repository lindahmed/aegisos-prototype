import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../models/weekly_plan.dart';
import '../theme/app_theme.dart';

class TodayDashboardCard extends StatelessWidget {
  const TodayDashboardCard({
    required this.progress,
    required this.weeklyPlan,
    required this.localEvents,
    required this.onAskAegis,
    super.key,
  });

  final Map<String, dynamic>? progress;
  final WeeklyPlan? weeklyPlan;
  final List<StudentCalendarEvent> localEvents;
  final VoidCallback onAskAegis;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final events = _todayCalendarEvents(now);
    final week = _weekProgress();
    return Container(
      key: const Key('today-dashboard'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appScreenSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appScreenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: uniTrackBlue),
              const SizedBox(width: 9),
              const Expanded(
                child: AppText(
                  'TODAY\'S CALENDAR',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              AppText(
                '${now.day}/${now.month}',
                style: TextStyle(color: appScreenMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            _InfoLine(
              icon: Icons.event_available_outlined,
              text: 'No Calendar events scheduled for today.',
            )
          else
            ...events.map(
              (event) => _InfoLine(
                icon: event.completed
                    ? Icons.check_circle_rounded
                    : event.type == StudentCalendarEventType.studySession
                    ? Icons.menu_book_outlined
                    : Icons.event_note_outlined,
                text:
                    '${_time(event.startAt)} — ${event.title}${event.completed ? ' · Completed' : ''}',
              ),
            ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'YOUR WEEK',
                      style: TextStyle(
                        color: appScreenMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      '${week.$1} / ${week.$2} priorities completed',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('ask-ai-about-day'),
                onPressed: onAskAegis,
                style: FilledButton.styleFrom(
                  backgroundColor: uniTrackBlue,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const AppText('Ask AI'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<StudentCalendarEvent> _todayCalendarEvents(DateTime now) {
    final events =
        [
            ...StudentCalendarBuilder.academicEvents(progress, now: now),
            ...localEvents,
          ].where((event) => DateUtils.isSameDay(event.startAt, now)).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return events;
  }

  (int, int) _weekProgress() {
    final items = weeklyPlan?.items ?? const <WeeklyPlanItem>[];
    return (items.where((item) => item.isCompleted).length, items.length);
  }

  static String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: uniTrackBlue),
        const SizedBox(width: 9),
        Expanded(child: AppText(text, style: const TextStyle(height: 1.3))),
      ],
    ),
  );
}
