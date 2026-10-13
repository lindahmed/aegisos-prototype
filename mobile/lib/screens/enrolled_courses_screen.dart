import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_course_schedule.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class EnrolledCoursesScreen extends StatefulWidget {
  const EnrolledCoursesScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<EnrolledCoursesScreen> createState() => _EnrolledCoursesScreenState();
}

class _EnrolledCoursesScreenState extends State<EnrolledCoursesScreen> {
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
    key: const Key('enrolled-courses-page'),
    appBar: AppBar(
      title: const AppText(
        'Enrolled Courses',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          tooltip: tr('Refresh courses'),
          onPressed: _loading ? null : () => _load(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: _loading && _report == null
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _load(forceRefresh: true),
            child: _buildContent(),
          ),
  );

  Widget _buildContent() {
    final courses = _report?.courses ?? const <RegisteredCourse>[];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        _CoursesOverview(
          studentName: widget.student.name.split(RegExp(r'\s+')).first,
          courseCount: courses.length,
        ),
        const SizedBox(height: 22),
        AppText(
          'Your courses',
          style: TextStyle(
            color: appScreenInk,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        AppText(
          'Only the courses currently registered to your account.',
          style: TextStyle(color: appScreenMuted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _CoursesError(message: _error!, onRetry: _load),
        ] else if (courses.isEmpty) ...[
          const SizedBox(height: 14),
          const _EmptyCourses(),
        ] else ...[
          const SizedBox(height: 14),
          ...courses.indexed.map(
            (entry) => _AnimatedCourseCard(index: entry.$1, course: entry.$2),
          ),
        ],
      ],
    );
  }
}

class _CoursesOverview extends StatelessWidget {
  const _CoursesOverview({
    required this.studentName,
    required this.courseCount,
  });

  final String studentName;
  final int courseCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDarkModeEnabled
            ? const [Color(0xFF15345F), Color(0xFF0D536A)]
            : const [Color(0xFFEAF2FF), Color(0xFFDFF8FF)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: appScreenBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [uniTrackBlue, uniTrackSky]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: uniTrackBlue.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                '$courseCount enrolled course${courseCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: appScreenInk,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              AppText(
                '$studentName, these are your active courses.',
                style: TextStyle(color: appScreenMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AnimatedCourseCard extends StatelessWidget {
  const _AnimatedCourseCard({required this.index, required this.course});

  final int index;
  final RegisteredCourse course;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 360 + (index.clamp(0, 6) * 90)),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 22 * (1 - value)),
        child: child,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: Key('enrolled-course-$index'),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: appScreenSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: appScreenBorder),
          boxShadow: [
            BoxShadow(
              color: uniTrackNavy.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: uniTrackBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: AppText(
                  '${index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(
                    color: uniTrackBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    course.name,
                    style: TextStyle(
                      color: appScreenInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (course.code.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    AppText(
                      course.code,
                      style: TextStyle(
                        color: appScreenMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const AppText(
                'Enrolled',
                style: TextStyle(
                  color: Color(0xFF07875F),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CoursesError extends StatelessWidget {
  const _CoursesError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        AppText(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const AppText('Try again'),
        ),
      ],
    ),
  );
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: appScreenBorder),
    ),
    child: Column(
      children: [
        Icon(Icons.menu_book_outlined, color: appScreenMuted, size: 38),
        const SizedBox(height: 10),
        const AppText(
          'No enrolled courses were found.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
