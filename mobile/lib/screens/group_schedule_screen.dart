import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_schedule.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

const _weekDays = <String>[
  'Saturday',
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
];

class GroupScheduleScreen extends StatefulWidget {
  const GroupScheduleScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<GroupScheduleScreen> createState() => _GroupScheduleScreenState();
}

class _GroupScheduleScreenState extends State<GroupScheduleScreen> {
  GroupSchedule? _schedule;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedule = await widget.apiService.getGroupSchedule(
        widget.student.studentId,
      );
      if (mounted) setState(() => _schedule = schedule);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('group-schedule-page'),
    appBar: AppBar(
      title: const Text(
        'My Group Schedule',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: const [ThemeModeToggleButton(), SizedBox(width: 8)],
    ),
    body: _loading && _schedule == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _schedule == null
        ? _ScheduleError(message: _error!, onRetry: _load)
        : RefreshIndicator(onRefresh: _load, child: _buildSchedule()),
  );

  Widget _buildSchedule() {
    final schedule = _schedule!;
    if (!schedule.hasGroup) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'No schedule group is available for you yet.',
            style: TextStyle(color: appScreenMuted),
          ),
        ],
      );
    }

    final sessions = [...schedule.sessions]
      ..sort((a, b) {
        final day = _weekDays.indexOf(a.day).compareTo(_weekDays.indexOf(b.day));
        return day != 0 ? day : a.startMinute.compareTo(b.startMinute);
      });
    final days = _weekDays
        .where(
          (day) => day != 'Friday' || sessions.any((item) => item.day == day),
        )
        .toList();
    final busyDays = days
        .where((day) => sessions.any((item) => item.day == day))
        .toList();
    final freeDays = days.where((day) => !busyDays.contains(day)).toList();
    final totalMinutes = sessions.fold<int>(0, (sum, item) => sum + item.minutes);

    final note = switch (schedule.timesSource) {
      'database' =>
        '${schedule.semester} timetable · shared by every student in your group.',
      'partial' =>
        '${schedule.semester} timetable · some courses have no class times yet.',
      'provisional' =>
        'Provisional timetable · placeholder times and rooms until the official ones are published.',
      _ => 'No class times have been published for your courses yet.',
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        Text(
          schedule.label,
          style: TextStyle(
            color: appScreenInk,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${schedule.size} of ${schedule.capacity} students · $note',
          style: TextStyle(color: appScreenMuted, height: 1.4),
        ),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Fact(
                value: '${sessions.length}',
                label: sessions.length == 1 ? 'session a week' : 'sessions a week',
              ),
              _Fact(
                value: '${(totalMinutes / 60).toStringAsFixed(1)} h',
                label: 'in class',
              ),
              _Fact(
                value: '${busyDays.length}',
                label: busyDays.length == 1 ? 'day on campus' : 'days on campus',
              ),
              _Fact(
                value: freeDays.isEmpty
                    ? 'None'
                    : freeDays.map((day) => day.substring(0, 3)).join(' · '),
                label: 'days off',
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DayCard(
              day: day,
              sessions: sessions.where((item) => item.day == day).toList(),
            ),
          ),
        if (schedule.unscheduledCourses.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4DD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF2C46B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Class times not announced yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A5200),
                  ),
                ),
                const SizedBox(height: 6),
                for (final course in schedule.unscheduledCourses)
                  Text(course, style: const TextStyle(color: Color(0xFF3B2A00))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Text(
          'Students who share this schedule',
          style: TextStyle(
            color: appScreenInk,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${schedule.members.length} ${schedule.members.length == 1 ? 'student' : 'students'}',
          style: TextStyle(color: appScreenMuted),
        ),
        const SizedBox(height: 10),
        for (final member in schedule.members) _MemberTile(member: member),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: appScreenSurfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: appScreenBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: appScreenInk,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: appScreenMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.sessions});
  final String day;
  final List<GroupSession> sessions;

  @override
  Widget build(BuildContext context) {
    final off = sessions.isEmpty;
    return Opacity(
      opacity: off ? 0.65 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appScreenSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appScreenBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  day.toUpperCase(),
                  style: const TextStyle(
                    color: uniTrackBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  off
                      ? 'Day off'
                      : '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'}',
                  style: TextStyle(
                    color: off ? const Color(0xFF1E9E6A) : appScreenMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            for (final session in sessions) _SessionRow(session: session),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final GroupSession session;

  @override
  Widget build(BuildContext context) {
    final type = session.sessionType;
    final room = (session.location == null || session.location!.isEmpty)
        ? 'Room to be announced'
        : session.location!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${session.timeLabel} · ${session.durationLabel}',
            style: const TextStyle(
              color: Color(0xFFB7791F),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            session.courseName,
            style: TextStyle(
              color: appScreenInk,
              fontWeight: FontWeight.w800,
              fontStyle: session.provisional ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (type != null && type.isNotEmpty)
                _Tag(text: type, color: _typeColor(type)),
              _Tag(text: room, color: appScreenMuted),
              if (session.provisional)
                _Tag(text: 'Provisional', color: appScreenMuted, dashed: true),
            ],
          ),
        ],
      ),
    );
  }

  static Color _typeColor(String type) => switch (type.toLowerCase()) {
    'lecture' => const Color(0xFF3B82F6),
    'section' => const Color(0xFF10B981),
    'lab' => const Color(0xFFF59E0B),
    _ => const Color(0xFF6B7280),
  };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.dashed = false});
  final String text;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: dashed ? Colors.transparent : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: dashed ? 0.4 : 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});
  final GroupMember member;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: member.isYou
          ? uniTrackBlue.withValues(alpha: 0.10)
          : appScreenSurfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: member.isYou
            ? uniTrackBlue.withValues(alpha: 0.5)
            : appScreenBorder,
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.person_outline, size: 20, color: appScreenMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            member.name,
            style: TextStyle(color: appScreenInk, fontWeight: FontWeight.w600),
          ),
        ),
        if (member.isYou) const _Tag(text: 'You', color: uniTrackBlue),
      ],
    ),
  );
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
