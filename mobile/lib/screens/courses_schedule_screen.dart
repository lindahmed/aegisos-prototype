import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_course_schedule.dart';
import '../models/student_group_schedule.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ask_aegis_fab.dart';

const _coursesIndigo = uniTrackBlue;
const _coursesCyan = uniTrackSky;
const _dayOrder = <String, int>{
  'saturday': 0,
  'sunday': 1,
  'monday': 2,
  'tuesday': 3,
  'wednesday': 4,
  'thursday': 5,
  'friday': 6,
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
  StudentGroupScheduleReport? _groupReport;
  String? _error;
  String? _scheduleError;
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
      _scheduleError = null;
    });
    try {
      final report = await widget.apiService.getStudentCourses(
        widget.student.studentId,
        forceRefresh: forceRefresh,
      );
      if (mounted) setState(() => _report = report);
      try {
        final groupReport = await widget.apiService.getStudentGroupSchedule(
          widget.student.studentId,
          forceRefresh: forceRefresh,
        );
        if (mounted) setState(() => _groupReport = groupReport);
      } on ApiException catch (error) {
        if (mounted) setState(() => _scheduleError = error.message);
      }
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
      title: const AppText(
        'Class Timetable',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          tooltip: tr('Refresh class timetable'),
          onPressed: _loading ? null : () => _load(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const ThemeModeToggleButton(),
        const SizedBox(width: 8),
      ],
    ),
    floatingActionButton: AskAegisFab(
      onPressed: () => openAskAegis(
        context,
        student: widget.student,
        apiService: widget.apiService,
        prompt: 'I am viewing my Courses and Class Timetable. Which course should I prioritize and how should I use my free time?',
      ),
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
    final groupSchedule = _groupReport?.schedule;
    final groupSlots = [...?groupSchedule?.slots]
      ..sort((first, second) {
        final day = (_dayOrder[first.day.toLowerCase()] ?? 99).compareTo(
          _dayOrder[second.day.toLowerCase()] ?? 99,
        );
        return day != 0 ? day : first.startMinute.compareTo(second.startMinute);
      });
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
        if (_groupReport?.group != null) ...[
          const SizedBox(height: 14),
          _ScheduleGroupCard(report: _groupReport!),
        ],
        const SizedBox(height: 24),
        _SectionTitle(
          title: 'Weekly timetable',
          subtitle: groupSchedule == null
              ? 'Your timetable updates automatically from university data.'
              : '${groupSchedule.semester} · live from your university schedule',
        ),
        const SizedBox(height: 12),
        if (groupSlots.isNotEmpty)
          _WeeklyGroupSchedule(slots: groupSlots)
        else if (scheduled.isNotEmpty)
          ...scheduled.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScheduleRow(course: item.course, slot: item.slot),
            ),
          )
        else
          _ScheduleUnavailable(
            title: _groupReport?.group == null
                ? 'Class timetable not published yet'
                : 'Class times not published for your group',
            body: _groupReport?.group == null
                ? 'Your registered courses are available below. Class days, times, and rooms will appear here automatically when the university publishes them.'
                : 'Your schedule group is available, but the university API currently returns no class-time slots for these courses.',
            onRefresh: () => _load(forceRefresh: true),
          ),
        if (_scheduleError != null) ...[
          const SizedBox(height: 10),
          _ScheduleNote(
            icon: Icons.sync_problem_outlined,
            text: 'The detailed group timetable is temporarily unavailable. Course times shown above are still current.',
          ),
        ],
        if (groupSchedule?.timesSource == 'provisional') ...[
          const SizedBox(height: 10),
          const _ScheduleNote(
            icon: Icons.info_outline_rounded,
            text: 'Some times are provisional and will update automatically when the university publishes final times.',
          ),
        ],
        if (groupSchedule?.unscheduledCourses.isNotEmpty == true) ...[
          const SizedBox(height: 18),
          _UnscheduledCourses(courses: groupSchedule!.unscheduledCourses),
        ],
        if (_groupReport?.classmates.isNotEmpty == true) ...[
          const SizedBox(height: 18),
          _ClassmatesCard(report: _groupReport!),
        ],
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
              AppText(
                '$courseCount registered course${courseCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: appScreenInk,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              AppText(
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

class _ScheduleGroupCard extends StatelessWidget {
  const _ScheduleGroupCard({required this.report});

  final StudentGroupScheduleReport report;

  @override
  Widget build(BuildContext context) {
    final group = report.group!;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _coursesIndigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _coursesIndigo.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _coursesIndigo.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.groups_2_outlined, color: _coursesIndigo),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  group.label,
                  style: TextStyle(
                    color: appScreenInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  '${group.levelLabel} · ${group.size}/${group.capacity} students',
                  style: TextStyle(color: appScreenMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _coursesCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: AppText(
              'Group ${group.number}',
              style: const TextStyle(
                color: _coursesCyan,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyGroupSchedule extends StatelessWidget {
  const _WeeklyGroupSchedule({required this.slots});

  final List<StudentGroupScheduleSlot> slots;

  @override
  Widget build(BuildContext context) {
    final byDay = <String, List<StudentGroupScheduleSlot>>{};
    for (final slot in slots) {
      byDay.putIfAbsent(slot.day, () => []).add(slot);
    }
    return Column(
      children: byDay.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: appScreenSurface,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: appScreenBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                          color: _coursesCyan,
                        ),
                        const SizedBox(width: 8),
                        AppText(
                          entry.key,
                          style: const TextStyle(
                            color: _coursesCyan,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    ...entry.value.map(
                      (slot) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GroupScheduleRow(slot: slot),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _GroupScheduleRow extends StatelessWidget {
  const _GroupScheduleRow({required this.slot});

  final StudentGroupScheduleSlot slot;

  @override
  Widget build(BuildContext context) {
    final type = slot.sessionType?.trim();
    final location = slot.location?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: AppText(
            slot.timeLabel,
            style: TextStyle(
              color: appScreenInk,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                slot.courseName,
                style: TextStyle(
                  color: appScreenInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  if (slot.courseId.isNotEmpty)
                    _ScheduleChip(label: slot.courseId),
                  if (type?.isNotEmpty == true) _ScheduleChip(label: type!),
                  if (location?.isNotEmpty == true)
                    _ScheduleChip(
                      label: location!,
                      icon: Icons.location_on_outlined,
                    ),
                  if (slot.provisional)
                    const _ScheduleChip(
                      label: 'Provisional',
                      icon: Icons.info_outline_rounded,
                      warning: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip({required this.label, this.icon, this.warning = false});

  final String label;
  final IconData? icon;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: (warning ? Colors.orange : _coursesIndigo).withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 12,
            color: warning ? Colors.orange.shade700 : _coursesIndigo,
          ),
          const SizedBox(width: 4),
        ],
        AppText(
          label,
          style: TextStyle(
            color: warning ? Colors.orange.shade800 : _coursesIndigo,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ScheduleNote extends StatelessWidget {
  const _ScheduleNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _coursesCyan.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _coursesCyan, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: AppText(
            text,
            style: TextStyle(color: appScreenMuted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _UnscheduledCourses extends StatelessWidget {
  const _UnscheduledCourses({required this.courses});

  final List<UnscheduledCourse> courses;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.pending_actions_outlined, color: Colors.orange),
            SizedBox(width: 8),
            AppText(
              'Waiting for university times',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ...courses.map(
          (course) => Padding(
            padding: const EdgeInsets.only(top: 5),
            child: AppText(
              '• ${course.id} · ${course.name}',
              style: TextStyle(color: appScreenMuted, height: 1.35),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ClassmatesCard extends StatelessWidget {
  const _ClassmatesCard({required this.report});

  final StudentGroupScheduleReport report;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: appScreenBorder),
    ),
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.people_outline_rounded, color: _coursesIndigo),
      title: const AppText(
        'My schedule group',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: AppText(
        '${report.classmates.length} classmates',
        style: TextStyle(color: appScreenMuted, fontSize: 12),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: report.classmates
                .map((name) => _ScheduleChip(label: name))
                .toList(),
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
      AppText(
        title,
        style: TextStyle(
          color: appScreenInk,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      AppText(subtitle, style: TextStyle(color: appScreenMuted, fontSize: 12)),
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
          child: AppText(
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
              AppText(
                '${course.code} · ${course.name}',
                style: TextStyle(
                  color: appScreenInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              AppText(
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
              child: AppText(
                course.code,
                style: const TextStyle(
                  color: _coursesIndigo,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            AppText(
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
        AppText(
          course.name,
          style: TextStyle(
            color: appScreenInk,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        AppText(course.semester, style: TextStyle(color: appScreenMuted)),
        const SizedBox(height: 9),
        AppText(
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
    this.body = 'Your registered courses are available below. Class days, times, and rooms will appear here automatically when the university publishes them.',
    this.onRefresh,
  });
  final String title;
  final String body;
  final VoidCallback? onRefresh;

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
              AppText(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              AppText(
                body,
                style: TextStyle(color: appScreenMuted, height: 1.4),
              ),
              if (onRefresh != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const AppText('Refresh timetable'),
                ),
              ],
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
          AppText(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const AppText('Try again'),
          ),
        ],
      ),
    ),
  );
}
