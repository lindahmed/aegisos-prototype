import 'package:flutter/material.dart';

import '../models/student.dart';
import '../theme/app_theme.dart';

Color get _ink => appScreenInk;
Color get _muted => appScreenMuted;
Color get _surface => appScreenSurface;
Color get _border => appScreenBorder;
const _indigo = Color(0xFF5965F2);

class WeeklyPlanScreen extends StatelessWidget {
  const WeeklyPlanScreen({
    required this.student,
    required this.progress,
    super.key,
  });

  final Student student;
  final Map<String, dynamic>? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final week = (progress?['current_week'] as num?)?.toInt() ?? 1;
    final courses = ((progress?['courses'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final priorities = _buildPriorities(courses, week);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Fix My Week',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [ThemeModeToggleButton()],
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('weekly-plan-page'),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5965F2), Color(0xFF27BBD3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEK $week PLAN',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${student.name.split(RegExp(r'\s+')).first}, focus on what matters most.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${priorities.length} ${priorities.length == 1 ? 'priority' : 'priorities'} built from your live progress.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your priorities',
              style: TextStyle(
                color: _ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Complete these in order and check each one off.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 14),
            if (priorities.isEmpty)
              const _EmptyPlan()
            else
              for (var index = 0; index < priorities.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PriorityCard(
                    number: index + 1,
                    priority: priorities[index],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyPriority {
  const _WeeklyPriority({
    required this.course,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String course;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
}

List<_WeeklyPriority> _buildPriorities(
  List<Map<String, dynamic>> courses,
  int currentWeek,
) {
  final priorities = <_WeeklyPriority>[];
  for (final course in courses) {
    final courseName = course['course_name'] as String? ?? 'Course';
    final risks = ((course['risks'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final risk in risks.take(2)) {
      final message = risk['message'] as String?;
      if (message == null || message.trim().isEmpty) continue;
      priorities.add(
        _WeeklyPriority(
          course: courseName,
          title: 'Review course performance',
          detail: message,
          icon: Icons.priority_high_rounded,
          color: const Color(0xFFFF647C),
        ),
      );
    }

    final assessments = ((course['assessments'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final assessment in assessments) {
      final dueWeek = (assessment['due_week'] as num?)?.toInt();
      if (assessment['mark'] != null ||
          dueWeek == null ||
          dueWeek < currentWeek ||
          dueWeek > currentWeek + 1) {
        continue;
      }
      final name = assessment['name'] as String? ?? 'Assessment';
      priorities.add(
        _WeeklyPriority(
          course: courseName,
          title: 'Prepare for $name',
          detail: dueWeek == currentWeek
              ? 'Due this week. Schedule a focused study block today.'
              : 'Due next week. Start the first review session this week.',
          icon: Icons.event_available_outlined,
          color: const Color(0xFF27BBD3),
        ),
      );
    }
  }
  return priorities.take(6).toList();
}

class _PriorityCard extends StatefulWidget {
  const _PriorityCard({required this.number, required this.priority});

  final int number;
  final _WeeklyPriority priority;

  @override
  State<_PriorityCard> createState() => _PriorityCardState();
}

class _PriorityCardState extends State<_PriorityCard> {
  bool _complete = false;

  @override
  Widget build(BuildContext context) {
    final priority = widget.priority;
    return Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _complete = !_complete),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: priority.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(priority.icon, color: priority.color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.number}. ${priority.course}',
                      style: TextStyle(
                        color: priority.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      priority.title,
                      style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        decoration: _complete
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      priority.detail,
                      style: TextStyle(color: _muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: _complete,
                activeColor: _indigo,
                onChanged: (value) =>
                    setState(() => _complete = value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF22B98B),
          size: 42,
        ),
        const SizedBox(height: 12),
        Text(
          'You are on track',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'No urgent risks or upcoming ungraded assessments were found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );
}
