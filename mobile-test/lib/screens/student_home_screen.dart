import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/calendar_event.dart';
import '../models/student_notification.dart';
import '../models/weekly_plan.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ask_aegis_fab.dart';
import '../widgets/risk_details_sheet.dart';
import '../widgets/study_session_dialog.dart';
import '../widgets/today_dashboard_card.dart';
import 'advisor_screen.dart';
import 'calendar_screen.dart';
import 'courses_schedule_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';
import 'meetings_screen.dart';
import 'results_screen.dart';
import 'semester_planner_screen.dart';
import 'weekly_plan_screen.dart';
import 'what_if_simulator_screen.dart';

Color get _dashboardInk => appScreenInk;
Color get _dashboardMuted => appScreenMuted;
Color get _dashboardBorder => appScreenBorder;
Color get _dashboardSurface => appScreenSurface;
Color get _dashboardHeroStart =>
    isDarkModeEnabled ? const Color(0xFF16243E) : const Color(0xFFEAF2FF);
Color get _dashboardHeroEnd =>
    isDarkModeEnabled ? const Color(0xFF12344B) : const Color(0xFFE8F8FF);
Color get _dashboardTrack =>
    isDarkModeEnabled ? const Color(0xFF2A3952) : const Color(0xFFE4EDF3);
const _dashboardIndigo = uniTrackNavy;
const _dashboardCyan = uniTrackBlueMid;
const _dashboardCoral = Color(0xFFFF647C);

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({required this.student, this.apiService, super.key});

  final Student student;
  final ApiService? apiService;

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  late final ApiService _apiService;
  late final bool _ownsApiService;
  Map<String, dynamic>? _progress;
  WeeklyPlan? _weeklyPlan;
  List<StudentCalendarEvent> _localEvents = const [];
  String? _error;
  bool _loading = true;
  int _selectedIndex = 0;

  Student get student => widget.student;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    appLanguageController.addListener(_refreshLanguage);
    unawaited(_loadProgress());
  }

  void _refreshLanguage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appLanguageController.removeListener(_refreshLanguage);
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  Future<void> _loadProgress({bool forceRefresh = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final progress = await _apiService.getStudentProgress(
        student.studentId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _error = null;
      });
      await _loadHomeExtras(forceRefresh: forceRefresh);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHomeExtras({bool forceRefresh = false}) async {
    try {
      final events = await StudentCalendarStore.load(student.studentId);
      if (mounted) setState(() => _localEvents = events);
    } catch (_) {
      // Local calendar data should never block the Today dashboard.
    }
    try {
      final plan = await _apiService.getWeeklyPlan(
        student.studentId,
        forceRefresh: forceRefresh,
      );
      if (mounted) setState(() => _weeklyPlan = plan);
    } catch (_) {
      // Progress remains usable if the weekly-plan endpoint is unavailable.
    }
  }

  Future<void> _openAdvisor([String? initialMessage]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdvisorScreen(
          student: student,
          apiService: _apiService,
          initialMessage: initialMessage,
        ),
      ),
    );
    final localEvents = await StudentCalendarStore.load(student.studentId);
    if (mounted) setState(() => _localEvents = localEvents);
  }

  void _openResults() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ResultsScreen(student: student, apiService: _apiService),
      ),
    );
  }

  void _openCourses() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CoursesScheduleScreen(student: student, apiService: _apiService),
      ),
    );
  }

  void _openWeeklyPlan() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => WeeklyPlanScreen(
              student: student,
              apiService: _apiService,
              onPlanChanged: (plan) {
                if (mounted) setState(() => _weeklyPlan = plan);
              },
            ),
          ),
        )
        .then((_) => _loadHomeExtras(forceRefresh: true));
  }

  void _openSemesterPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SemesterPlannerScreen(student: student, apiService: _apiService),
      ),
    );
  }

  void _openCalendar() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CalendarScreen(student: student, apiService: _apiService),
          ),
        )
        .then((_) async {
          final localEvents = await StudentCalendarStore.load(
            student.studentId,
          );
          if (mounted) setState(() => _localEvents = localEvents);
        });
  }

  void _openWhatIf() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WhatIfSimulatorScreen(student: student, apiService: _apiService),
      ),
    );
  }

  void _openMessages() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MessagesScreen(student: student, apiService: _apiService),
      ),
    );
  }

  void _openMeetings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MeetingsScreen(student: student)),
    );
  }

  Future<void> _addRiskSession(
    Map<String, dynamic> course,
    Map<String, dynamic> risk,
  ) async {
    final courseId = course['course_id']?.toString();
    final courseName = course['course_name']?.toString() ?? 'Focused Study';
    final event = await showStudySessionDialog(
      context,
      courseId: courseId,
      courseName: courseName,
      reason: risk['message']?.toString() ?? 'Added from academic risk.',
      alreadyInWeekPlanner: _courseIsInWeekPlanner(courseId, courseName),
    );
    if (event == null) return;
    try {
      final localEvents = await StudentCalendarStore.load(student.studentId);
      final updated = [...localEvents, event];
      await StudentCalendarStore.save(student.studentId, updated);
      if (!mounted) return;
      setState(() => _localEvents = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            'Study session added to Calendar on ${event.startAt.day}/${event.startAt.month}.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Could not save the study session.')),
      );
    }
  }

  bool _courseIsInWeekPlanner(String? courseId, String courseName) {
    final normalizedName = courseName.trim().toLowerCase();
    return _weeklyPlan?.items.any(
          (item) =>
              item.courseId == courseId ||
              item.courseName.trim().toLowerCase() == normalizedName,
        ) ??
        false;
  }

  Future<void> _showCourseRisks(Map<String, dynamic> course) async {
    if (_weeklyPlan == null) {
      try {
        final plan = await _apiService.getWeeklyPlan(student.studentId);
        if (mounted) setState(() => _weeklyPlan = plan);
      } catch (_) {
        // Risk details still open if Week Planner cannot be refreshed.
      }
    }
    if (!mounted) return;
    final courseId = course['course_id']?.toString();
    final courseName = course['course_name']?.toString() ?? 'Course';
    await showCourseRisksSheet(
      context,
      course: course,
      alreadyInWeekPlanner: _courseIsInWeekPlanner(courseId, courseName),
      onFix: _openWeeklyPlan,
      onAddSession: (risk) => _addRiskSession(course, risk),
      onAskAegis: (risk) => _openAdvisor(
        'Explain this $courseName risk and give me a practical recovery plan: ${risk['message']}',
      ),
    );
  }

  String _contextPrompt() => switch (_selectedIndex) {
    0 => 'I am on my Home dashboard. Explain my day and tell me the most important next action.',
    1 => 'I am viewing Academic Progress. Explain my progress and the main risk I should fix.',
    2 => 'Analyze my progress and tell me what I should study today.',
    3 =>
      'I am viewing Academics. Which assessment or course should I prioritize?',
    _ => 'Give me a concise academic status update and my best next action.',
  };

  void _signOut() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titles = [
      'Home',
      'Progress & Risks',
      'AI Advisor',
      'Academics',
      'Student Profile',
    ];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: _selectedIndex == 0 ? 76 : 64,
        title: _selectedIndex == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    _greeting(),
                    style: TextStyle(
                      color: _dashboardMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  AppText(
                    student.name.split(RegExp(r'\s+')).first,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ],
              )
            : AppText(
                titles[_selectedIndex],
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
        actions: [
          if (_selectedIndex == 0) const AppLanguageToggleButton(),
          const ThemeModeToggleButton(),
          _NotificationButton(
            studentId: student.studentId,
            apiService: _apiService,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              backgroundColor: uniTrackBlueSoft,
              foregroundColor: _dashboardIndigo,
              child: AppText(
                _initials(student.name),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: _loading && _progress == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadProgress(forceRefresh: true),
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _HomeDashboard(
                    student: student,
                    progress: _progress,
                    weeklyPlan: _weeklyPlan,
                    localEvents: _localEvents,
                    error: _error,
                    onFixWeek: _openWeeklyPlan,
                    onMessages: _openMessages,
                    onMeetings: _openMeetings,
                    onAskDay: () => _openAdvisor(
                      'I am on my Home dashboard. Plan my day using my real courses, risks, and deadlines.',
                    ),
                  ),
                  _ProgressDashboard(
                    progress: _progress,
                    error: _error,
                    onCourseTap: _showCourseRisks,
                  ),
                  _AdvisorLanding(
                    student: student,
                    onStartConversation: () => _openAdvisor(),
                    onSuggestionSelected: (prompt) => _openAdvisor(prompt),
                  ),
                  _AcademicsDashboard(
                    onCourses: _openCourses,
                    onResults: _openResults,
                    onPlanner: _openSemesterPlanner,
                    onCalendar: _openCalendar,
                    onWhatIf: _openWhatIf,
                  ),
                  _ProfileDashboard(student: student, onSignOut: _signOut),
                ],
              ),
            ),
      floatingActionButton: _selectedIndex == 2
          ? null
          : AskAegisFab(onPressed: () => _openAdvisor(_contextPrompt())),
      bottomNavigationBar: NavigationBar(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: tr('Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights_rounded),
            label: tr('Progress'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: tr('AI Advisor'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school_rounded),
            label: tr('Academics'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_circle_outlined),
            selectedIcon: const Icon(Icons.account_circle_rounded),
            label: tr('Profile'),
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

List<Map<String, dynamic>> _progressCourses(Map<String, dynamic>? progress) =>
    ((progress?['courses'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.student,
    required this.progress,
    required this.weeklyPlan,
    required this.localEvents,
    required this.error,
    required this.onFixWeek,
    required this.onMessages,
    required this.onMeetings,
    required this.onAskDay,
  });

  final Student student;
  final Map<String, dynamic>? progress;
  final WeeklyPlan? weeklyPlan;
  final List<StudentCalendarEvent> localEvents;
  final String? error;
  final VoidCallback onFixWeek;
  final VoidCallback onMessages;
  final VoidCallback onMeetings;
  final VoidCallback onAskDay;

  @override
  Widget build(BuildContext context) {
    final courses = _progressCourses(progress);
    final assessments = courses
        .expand(
          (course) => (course['assessments'] as List<dynamic>?) ?? const [],
        )
        .whereType<Map<String, dynamic>>()
        .toList();
    final completedWork = assessments
        .where((item) => item['mark'] != null)
        .length;
    return ListView(
      key: const PageStorageKey('home-dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (error != null) _InlineError(message: error!),
        TodayDashboardCard(
          progress: progress,
          weeklyPlan: weeklyPlan,
          localEvents: localEvents,
          onAskAegis: onAskDay,
        ),
        const SizedBox(height: 18),
        _SnapshotStrip(
          gpa: student.gpa,
          completedWork: completedWork,
          courseCount: courses.isEmpty
              ? student.courses.length
              : courses.length,
        ),
        const SizedBox(height: 18),
        _GradientAction(
          key: const Key('fix-my-week'),
          icon: Icons.auto_awesome,
          title: 'WEEK PLANNER',
          subtitle: 'Review priorities and complete this week\'s study tasks',
          onTap: onFixWeek,
        ),
        const SizedBox(height: 18),
        _CampusCommunicationCard(
          onMessages: onMessages,
          onMeetings: onMeetings,
        ),
      ],
    );
  }
}

class _SnapshotStrip extends StatelessWidget {
  const _SnapshotStrip({
    required this.gpa,
    required this.completedWork,
    required this.courseCount,
  });

  final double? gpa;
  final int completedWork;
  final int courseCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_dashboardHeroStart, _dashboardHeroEnd],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _dashboardBorder),
    ),
    child: Row(
      children: [
        _SnapshotValue(label: 'GPA', value: gpa?.toStringAsFixed(2) ?? '—'),
        const _SnapshotDivider(),
        _SnapshotValue(label: 'Completed', value: '$completedWork'),
        const _SnapshotDivider(),
        _SnapshotValue(label: 'Courses', value: '$courseCount'),
      ],
    ),
  );
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        AppText(
          value,
          style: TextStyle(
            color: _dashboardInk,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        AppText(label, style: TextStyle(color: _dashboardMuted, fontSize: 12)),
      ],
    ),
  );
}

class _SnapshotDivider extends StatelessWidget {
  const _SnapshotDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 38, color: _dashboardBorder);
}

class _ProgressDashboard extends StatelessWidget {
  const _ProgressDashboard({
    required this.progress,
    required this.error,
    required this.onCourseTap,
  });
  final Map<String, dynamic>? progress;
  final String? error;
  final Future<void> Function(Map<String, dynamic>) onCourseTap;

  @override
  Widget build(BuildContext context) {
    final courses = _progressCourses(progress);
    final week = (progress?['current_week'] as num?)?.toInt() ?? 1;
    final semester = progress?['semester'] as String? ?? 'Current semester';
    return ListView(
      key: const PageStorageKey('progress-dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (error != null) _InlineError(message: error!),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _dashboardSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _dashboardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppText(
                      semester,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const _LiveBadge(),
                ],
              ),
              const SizedBox(height: 6),
              AppText(
                'Week $week of 14',
                style: TextStyle(color: _dashboardMuted),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: (week / 14).clamp(0, 1),
                minHeight: 12,
                borderRadius: BorderRadius.circular(20),
                color: _dashboardCyan,
                backgroundColor: _dashboardTrack,
              ),
              const SizedBox(height: 8),
              AppText(
                '${((week / 14) * 100).round()}% of the semester timeline',
                style: TextStyle(color: _dashboardMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppText(
          'Course performance',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: _dashboardInk,
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          'Health, completion, and explained academic risks',
          style: TextStyle(color: _dashboardMuted),
        ),
        const SizedBox(height: 14),
        if (courses.isEmpty)
          const _EmptyCard(
            message: 'No live course progress is available yet.',
          ),
        ...courses.map(
          (course) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CourseProgressCard(
              course: course,
              onTap: () => onCourseTap(course),
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseProgressCard extends StatelessWidget {
  const _CourseProgressCard({required this.course, required this.onTap});
  final Map<String, dynamic> course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = (course['metrics'] as Map<String, dynamic>?) ?? const {};
    final health = _asDouble(metrics['course_health']);
    final lectures = _asDouble(metrics['lecture_completion']) ?? 0;
    final assessments = _asDouble(metrics['assessment_completion']) ?? 0;
    final risky = course['risk_level'] != null;
    final risks = ((course['risks'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: risks.isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _dashboardSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _dashboardBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: (risky ? _dashboardCoral : _dashboardCyan)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.menu_book_outlined,
                      color: risky ? _dashboardCoral : _dashboardCyan,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          course['course_name'] as String? ?? 'Course',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        AppText(
                          course['course_id']?.toString() ?? '',
                          style: TextStyle(color: _dashboardMuted),
                        ),
                      ],
                    ),
                  ),
                  AppText(
                    health == null ? '—' : '${health.round()}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: risky ? _dashboardCoral : _dashboardCyan,
                    ),
                  ),
                  if (risks.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              _ProgressLine(
                label: 'Lectures',
                value: lectures,
                color: _dashboardCyan,
              ),
              const SizedBox(height: 10),
              _ProgressLine(
                label: 'Assessments',
                value: assessments,
                color: _dashboardIndigo,
              ),
              if (risks.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: _dashboardCoral,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: AppText(
                        '${risks.length} risk${risks.length == 1 ? '' : 's'} · Tap to see why and recommended actions',
                        style: const TextStyle(
                          color: _dashboardCoral,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 88,
        child: AppText(label, style: TextStyle(color: _dashboardMuted)),
      ),
      Expanded(
        child: LinearProgressIndicator(
          value: (value / 100).clamp(0, 1),
          minHeight: 8,
          borderRadius: BorderRadius.circular(10),
          color: color,
          backgroundColor: _dashboardTrack,
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 40,
        child: AppText(
          '${value.round()}%',
          textAlign: TextAlign.end,
          style: TextStyle(color: _dashboardMuted),
        ),
      ),
    ],
  );
}

class _AdvisorLanding extends StatelessWidget {
  const _AdvisorLanding({
    required this.student,
    required this.onStartConversation,
    required this.onSuggestionSelected,
  });
  final Student student;
  final VoidCallback onStartConversation;
  final ValueChanged<String> onSuggestionSelected;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [uniTrackBlue, uniTrackSky],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 42),
            const SizedBox(height: 40),
            AppText(
              'Hi ${student.name.split(' ').first}, what can I help you solve?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            const AppText(
              'Ask about your courses, grades, risks, timetable, or study priorities. Answers use your current academic data.',
              style: TextStyle(color: Color(0xFFEAF5FF), height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AppText(
        'Try asking',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: _dashboardInk,
        ),
      ),
      const SizedBox(height: 12),
      for (final suggestion in [
        (
          label: 'Explain my academic progress',
          prompt: 'Explain my academic progress and the main reason behind each risk.',
        ),
        (
          label: 'Plan what I should study today',
          prompt:
              'Using my real courses and deadlines, what should I study today?',
        ),
        (
          label: 'Show my highest-priority course',
          prompt: 'Which course needs my attention most, why, and what should I do next?',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            onPressed: () => onSuggestionSelected(suggestion.prompt),
            style: OutlinedButton.styleFrom(
              backgroundColor: _dashboardSurface,
              foregroundColor: _dashboardIndigo,
              side: BorderSide(color: uniTrackBlue.withValues(alpha: 0.38)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            ),
            icon: const Icon(Icons.north_east_rounded, size: 20),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: AppText(suggestion.label),
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('open-advisor'),
        onPressed: onStartConversation,
        icon: const Icon(Icons.auto_awesome),
        style: FilledButton.styleFrom(
          backgroundColor: uniTrackBlue,
          shape: const StadiumBorder(),
        ),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 15),
          child: AppText('Start a conversation'),
        ),
      ),
    ],
  );
}

class _AcademicsDashboard extends StatelessWidget {
  const _AcademicsDashboard({
    required this.onCourses,
    required this.onResults,
    required this.onPlanner,
    required this.onCalendar,
    required this.onWhatIf,
  });
  final VoidCallback onCourses;
  final VoidCallback onResults;
  final VoidCallback onPlanner;
  final VoidCallback onCalendar;
  final VoidCallback onWhatIf;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('academics-dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        const _AcademicHubHero(),
        const SizedBox(height: 24),
        const _HubSectionTitle(
          eyebrow: 'CORE ACADEMICS',
          title: 'Classes and grades',
          subtitle: 'One clear place for official university information.',
        ),
        const SizedBox(height: 12),
        _SurfaceAction(
          key: const Key('open-courses-from-hub'),
          icon: Icons.calendar_view_week_rounded,
          title: 'Class Timetable',
          subtitle: 'Courses, lecture times, sections, labs, and rooms',
          onTap: onCourses,
        ),
        const SizedBox(height: 10),
        _SurfaceAction(
          icon: Icons.workspace_premium_outlined,
          title: 'Grades',
          subtitle: 'Official marks, course grades, and semester GPA',
          onTap: onResults,
        ),
        const SizedBox(height: 26),
        const _HubSectionTitle(
          eyebrow: 'PLAN & PREPARE',
          title: 'Planning tools',
          subtitle: 'Personal planning, separate from your class timetable.',
        ),
        const SizedBox(height: 12),
        _SurfaceAction(
          key: const Key('open-calendar'),
          icon: Icons.event_note_rounded,
          title: 'Calendar',
          subtitle: 'Academic deadlines and events you add',
          onTap: onCalendar,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 176,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PlanningTool(
                  key: const Key('open-semester-planner'),
                  icon: Icons.route_rounded,
                  title: 'Academic Roadmap',
                  subtitle:
                      'Future courses, prerequisites, and graduation routes',
                  onTap: onPlanner,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PlanningTool(
                  key: const Key('open-what-if-simulator'),
                  icon: Icons.science_outlined,
                  title: 'Grade Simulator',
                  subtitle: 'Preview grade impact',
                  onTap: onWhatIf,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AcademicHubHero extends StatelessWidget {
  const _AcademicHubHero();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isDarkModeEnabled
            ? const [Color(0xFF152845), Color(0xFF123B43)]
            : const [Color(0xFFEAF0FF), Color(0xFFE8FAF8)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: _dashboardBorder),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _dashboardIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: _dashboardIndigo,
            size: 30,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Everything academic, organised',
                style: TextStyle(
                  color: _dashboardInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              AppText(
                'Open the exact record or planning tool you need.',
                style: TextStyle(color: _dashboardMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HubSectionTitle extends StatelessWidget {
  const _HubSectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        eyebrow,
        style: const TextStyle(
          color: _dashboardCyan,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 4),
      AppText(
        title,
        style: TextStyle(
          color: _dashboardInk,
          fontSize: 21,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      AppText(subtitle, style: TextStyle(color: _dashboardMuted, height: 1.35)),
    ],
  );
}

class _PlanningTool extends StatelessWidget {
  const _PlanningTool({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _dashboardSurface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _dashboardBorder),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: uniTrackBlueSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: uniTrackBlue, size: 24),
            ),
            const Spacer(),
            AppText(
              title,
              style: TextStyle(
                color: _dashboardInk,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            AppText(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _dashboardMuted,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileDashboard extends StatelessWidget {
  const _ProfileDashboard({required this.student, required this.onSignOut});
  final Student student;
  final VoidCallback onSignOut;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _dashboardSurface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _dashboardBorder),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: uniTrackBlueSoft,
              foregroundColor: _dashboardIndigo,
              child: AppText(
                _initials(student.name),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppText(
              student.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: _dashboardInk,
              ),
            ),
            const SizedBox(height: 4),
            AppText(
              student.studentId,
              style: TextStyle(color: _dashboardMuted),
            ),
            const SizedBox(height: 12),
            Chip(
              label: AppText(student.major.toUpperCase()),
              backgroundColor: uniTrackBlueSoft,
              labelStyle: const TextStyle(
                color: uniTrackBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      AppText(
        'Academic information',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: _dashboardInk,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: _dashboardSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _dashboardBorder),
        ),
        child: Column(
          children: [
            _ProfileRow(
              icon: Icons.school_outlined,
              label: 'Program',
              value: student.major,
            ),
            _ProfileRow(
              icon: Icons.layers_outlined,
              label: 'Level',
              value: 'Year ${student.year}',
            ),
            _ProfileRow(
              icon: Icons.trending_up,
              label: 'GPA',
              value: student.gpa?.toStringAsFixed(2) ?? 'Unavailable',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: AppText('Sign out'),
        ),
      ),
    ],
  );

  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

class _CampusCommunicationCard extends StatelessWidget {
  const _CampusCommunicationCard({
    required this.onMessages,
    required this.onMeetings,
  });

  final VoidCallback onMessages;
  final VoidCallback onMeetings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppText(
        'Campus communication',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _dashboardSurface,
          border: Border.all(color: _dashboardBorder),
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _CommunicationAction(
              key: const Key('open-messages'),
              icon: Icons.forum_rounded,
              title: 'Messages',
              subtitle: 'Chat with professors and classmates',
              onTap: onMessages,
            ),
            Divider(height: 1, indent: 72, color: _dashboardBorder),
            _CommunicationAction(
              key: const Key('open-meetings'),
              icon: Icons.video_call_rounded,
              title: 'Live Meetings',
              subtitle: 'Host or join lectures and study rooms',
              onTap: onMeetings,
            ),
          ],
        ),
      ),
    ],
  );
}

class _CommunicationAction extends StatelessWidget {
  const _CommunicationAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: uniTrackBlueSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: uniTrackBlue, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    subtitle,
                    style: TextStyle(color: _dashboardMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: _dashboardIndigo),
    title: AppText(label),
    subtitle: AppText(value),
    shape: Border(bottom: BorderSide(color: _dashboardBorder)),
  );
}

class _GradientAction extends StatelessWidget {
  const _GradientAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_dashboardIndigo, uniTrackBlue],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  AppText(
                    subtitle,
                    style: TextStyle(color: Color(0xFFEAF5FF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _SurfaceAction extends StatelessWidget {
  const _SurfaceAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: _dashboardSurface,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _dashboardBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: uniTrackBlueSoft,
              foregroundColor: uniTrackBlue,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _dashboardInk,
                    ),
                  ),
                  AppText(
                    subtitle,
                    style: TextStyle(color: _dashboardMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: _dashboardMuted),
          ],
        ),
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: uniTrackBlueSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const AppText(
      'LIVE DATA',
      style: TextStyle(
        color: uniTrackBlue,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: AppText(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _dashboardSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _dashboardBorder),
    ),
    child: AppText(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: _dashboardMuted),
    ),
  );
}

class _NotificationButton extends StatefulWidget {
  const _NotificationButton({required this.studentId, this.apiService});

  final String studentId;
  final ApiService? apiService;

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton>
    with WidgetsBindingObserver {
  late final ApiService _apiService;
  late final bool _ownsApiService;
  Timer? _pollTimer;
  List<StudentNotification> _notifications = const [];
  bool _loading = false;
  bool _opening = false;
  String? _error;

  int get _unreadCount =>
      _notifications.where((notification) => !notification.read).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    unawaited(_loadNotifications());
    _pollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_loadNotifications()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadNotifications());
    }
  }

  Future<void> _loadNotifications({
    bool showError = false,
    bool forceRefresh = false,
  }) async {
    if (_loading) return;
    _loading = true;
    try {
      final notifications = await _apiService.getStudentNotifications(
        widget.studentId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (showError) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: AppText(error.message)));
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _openNotifications() async {
    if (_opening) return;
    _opening = true;
    await _loadNotifications(showError: true, forceRefresh: true);
    if (!mounted) return;

    final updated = await showModalBottomSheet<List<StudentNotification>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NotificationsSheet(
        studentId: widget.studentId,
        apiService: _apiService,
        initialNotifications: _notifications,
        initialError: _error,
      ),
    );
    if (!mounted) return;
    setState(() {
      if (updated != null) _notifications = updated;
      _opening = false;
    });
    unawaited(_loadNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final countLabel = _unreadCount > 99 ? '99+' : _unreadCount.toString();
    return IconButton(
      key: const Key('notifications-button'),
      tooltip: tr('Notifications'),
      onPressed: _openNotifications,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (_unreadCount > 0)
            Positioned(
              right: -9,
              top: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppText(
                  countLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet({
    required this.studentId,
    required this.apiService,
    required this.initialNotifications,
    this.initialError,
  });

  final String studentId;
  final ApiService apiService;
  final List<StudentNotification> initialNotifications;
  final String? initialError;

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  static const _filters = [
    'All',
    'Unread',
    'Grades',
    'Registration',
    'Financial',
    'System',
  ];

  late List<StudentNotification> _notifications;
  String? _error;
  bool _updating = false;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _notifications = widget.initialNotifications;
    _error = widget.initialError;
  }

  Future<void> _setRead(List<String> ids, bool read) async {
    if (_updating || ids.isEmpty) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final notifications = await widget.apiService.setNotificationsRead(
        studentId: widget.studentId,
        notificationIds: ids,
        read: read,
      );
      if (!mounted) return;
      setState(() => _notifications = notifications);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadIds = _notifications
        .where((notification) => !notification.read)
        .map((notification) => notification.id)
        .toList();
    final filteredNotifications = _notifications.where((notification) {
      if (_filter == 'All') return true;
      if (_filter == 'Unread') return !notification.read;
      return notification.category == _filter;
    }).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (unreadIds.isNotEmpty)
                    TextButton(
                      onPressed: _updating
                          ? null
                          : () => _setRead(unreadIds, true),
                      child: const AppText('Mark all read'),
                    ),
                  IconButton(
                    tooltip: tr('Close notifications'),
                    onPressed: () => Navigator.of(context).pop(_notifications),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_updating) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: AppText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  return ChoiceChip(
                    label: AppText(filter),
                    selected: filter == _filter,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = filter),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filteredNotifications.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: AppText(
                          'You are all caught up. No notifications match this filter.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredNotifications.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final notification = filteredNotifications[index];
                        final colorScheme = Theme.of(context).colorScheme;
                        return Material(
                          color: notification.read
                              ? Colors.transparent
                              : colorScheme.primaryContainer.withValues(
                                  alpha: 0.28,
                                ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: _notificationColor(
                                notification.category,
                                colorScheme,
                              ),
                              child: Icon(
                                _notificationIcon(notification.category),
                              ),
                            ),
                            title: AppText(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.read
                                    ? FontWeight.w500
                                    : FontWeight.bold,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(notification.body),
                                  const SizedBox(height: 5),
                                  AppText(
                                    '${notification.category} · ${notification.timestamp}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            trailing: notification.read
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: colorScheme.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                            onTap: _updating
                                ? null
                                : () => _setRead([
                                    notification.id,
                                  ], !notification.read),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _notificationIcon(String category) {
    return switch (category) {
      'Grades' => Icons.school_outlined,
      'Registration' => Icons.assignment_turned_in_outlined,
      'Financial' => Icons.account_balance_wallet_outlined,
      _ => Icons.settings_outlined,
    };
  }

  static Color _notificationColor(String category, ColorScheme colorScheme) {
    return switch (category) {
      'Grades' => colorScheme.primaryContainer,
      'Registration' => colorScheme.secondaryContainer,
      'Financial' => colorScheme.tertiaryContainer,
      _ => colorScheme.surfaceContainerHighest,
    };
  }
}
