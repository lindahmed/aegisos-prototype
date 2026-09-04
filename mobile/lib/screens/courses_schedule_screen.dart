import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_course_schedule.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

const _coursesIndigo = Color(0xFF5965F2);
const _coursesCyan = Color(0xFF20B8CD);
const _dayOrder = <String, int>{
  'sunday': 0,
  'monday': 1,
  'tuesday': 2,
  'wednesday': 3,
  'thursday': 4,
  'friday': 5,
  'saturday': 6,
};

class CoursesScheduleScreen extends StatefulWidget {
  const CoursesScheduleScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<CoursesScheduleScreen> createState() => _CoursesScheduleScreenState();
}

class _CoursesScheduleScreenState extends State<CoursesScheduleScreen> {
  StudentCoursesReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.apiService.getStudentCourses(
        widget.student.studentId,
        forceRefresh: forceRefresh,
      );
      if (mounted) setState(() => _report = report);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('courses-schedule-page'),
    appBar: AppBar(
      title: const Text(
        'My Courses & Schedule',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: const [ThemeModeToggleButton(), SizedBox(width: 8)],
    ),
    body: _loading && _report == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _report == null
        ? _CoursesError(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: () => _load(forceRefresh: true),
            child: _buildReport(),
          ),
  );

  Widget _buildReport() {
    final report = _report!;
    final scheduled = <({RegisteredCourse course, CourseScheduleSlot slot})>[];
    for (final course in report.courses) {
      for (final slot in course.schedule) {
        scheduled.add((course: course, slot: slot));
      }
    }
    scheduled.sort((first, second) {
      final day = (_dayOrder[first.slot.day.toLowerCase()] ?? 99).compareTo(
        _dayOrder[second.slot.day.toLowerCase()] ?? 99,
      );
      return day != 0
          ? day
          : first.slot.startMinute.compareTo(second.slot.startMinute);
    });

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        _CoursesHero(courseCount: report.courseCount),
        const SizedBox(height: 24),
        const _SectionTitle(
          title: 'University schedule',
          subtitle: 'Your timetable updates automatically from university data.',
        ),
        const SizedBox(height: 12),
        if (!report.schedulePublished || scheduled.isEmpty)
          const _ScheduleUnavailable()
        else
          ...scheduled.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScheduleRow(course: item.course, slot: item.slot),
            ),
          ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: 'Registered courses',
          subtitle:
              '${report.courseCount} active course${report.courseCount == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 12),
        if (report.courses.isEmpty)
          const _ScheduleUnavailable(
            title: 'No active courses',
            body: 'No current registrations were found in your university record.',
          )
        else
          ...report.courses.map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CourseCard(course: course),
            ),
          ),
      ],
    );
  }
}

class _CoursesHero extends StatelessWidget {
  const _CoursesHero({required this.courseCount});
  final int courseCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isDarkModeEnabled
            ? const [Color(0xFF1C2B4B), Color(0xFF123B43)]
            : const [Color(0xFFE9EDFF), Color(0xFFE4F8F8)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: appScreenBorder),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _coursesIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: _coursesIndigo,
            size: 31,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$courseCount registered course${courseCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: appScreenInk,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Courses and timetable in one place',
                style: TextStyle(color: appScreenMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: appScreenInk,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(subtitle, style: TextStyle(color: appScreenMuted, fontSize: 12)),
    ],
  );
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.course, required this.slot});
  final RegisteredCourse course;
  final CourseScheduleSlot slot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: appScreenBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _coursesCyan.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            slot.day,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _coursesCyan,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${course.code} · ${course.name}',
                style: TextStyle(
                  color: appScreenInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${slot.timeLabel}${slot.location == null || slot.location!.isEmpty ? '' : ' · ${slot.location}'}',
                style: TextStyle(color: appScreenMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});
  final RegisteredCourse course;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: appScreenBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _coursesIndigo.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                course.code,
                style: const TextStyle(
                  color: _coursesIndigo,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            Text(
              course.status,
              style: const TextStyle(
                color: Color(0xFF1A9B78),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          course.name,
          style: TextStyle(
            color: appScreenInk,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(course.semester, style: TextStyle(color: appScreenMuted)),
        const SizedBox(height: 9),
        Text(
          course.schedule.isEmpty
              ? 'Schedule not published'
              : course.schedule
                    .map((slot) => '${slot.day} · ${slot.timeLabel}')
                    .join('\n'),
          style: TextStyle(color: appScreenMuted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
}

class _ScheduleUnavailable extends StatelessWidget {
  const _ScheduleUnavailable({
    this.title = 'University timetable not published yet',
    this.body =
        'Your registered courses are available below. Class days, times, and rooms will appear here automatically when the university publishes them.',
  });
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: appScreenBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.calendar_month_outlined, color: _coursesCyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(color: appScreenMuted, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CoursesError extends StatelessWidget {
  const _CoursesError({required this.message, required this.onRetry});
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
