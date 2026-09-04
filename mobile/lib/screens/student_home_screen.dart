import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_notification.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'advisor_screen.dart';
import 'calendar_screen.dart';
import 'courses_schedule_screen.dart';
import 'login_screen.dart';
import 'results_screen.dart';
import 'semester_planner_screen.dart';
import 'weekly_plan_screen.dart';

Color get _dashboardInk => appScreenInk;
Color get _dashboardMuted => appScreenMuted;
Color get _dashboardBorder => appScreenBorder;
Color get _dashboardSurface => appScreenSurface;
Color get _dashboardHeroStart =>
    isDarkModeEnabled ? const Color(0xFF16243E) : const Color(0xFFEDF0FF);
Color get _dashboardHeroEnd =>
    isDarkModeEnabled ? const Color(0xFF12313D) : const Color(0xFFE7F7FA);
Color get _dashboardTrack =>
    isDarkModeEnabled ? const Color(0xFF2A3952) : const Color(0xFFE4EDF3);
const _dashboardIndigo = Color(0xFF5965F2);
const _dashboardCyan = Color(0xFF27BBD3);
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
  String? _error;
  bool _loading = true;
  int _selectedIndex = 0;

  Student get student => widget.student;

  List<Map<String, dynamic>> get _courses =>
      ((_progress?['courses'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    unawaited(_loadProgress());
  }

  @override
  void dispose() {
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
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAdvisor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AdvisorScreen(student: student, apiService: _apiService),
      ),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WeeklyPlanScreen(student: student, progress: _progress),
      ),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CalendarScreen(student: student, apiService: _apiService),
      ),
    );
  }

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
      'Academic Progress',
      'Aegis Advisor',
      'Academics',
      'Profile',
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
                  Text(
                    _greeting(),
                    style: TextStyle(
                      color: _dashboardMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    student.name.split(RegExp(r'\s+')).first,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ],
              )
            : Text(
                titles[_selectedIndex],
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
        actions: [
          const ThemeModeToggleButton(),
          _NotificationButton(
            studentId: student.studentId,
            apiService: _apiService,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              backgroundColor: const Color(0xFFE6E9FF),
              foregroundColor: _dashboardIndigo,
              child: Text(
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
                    error: _error,
                    onFixWeek: _openWeeklyPlan,
                    onResults: _openResults,
                    onCourses: _openCourses,
                  ),
                  _ProgressDashboard(progress: _progress, error: _error),
                  _AdvisorLanding(
                    student: student,
                    onOpenAdvisor: _openAdvisor,
                  ),
                  _AcademicsDashboard(
                    courses: _courses,
                    onResults: _openResults,
                    onPlanner: _openSemesterPlanner,
                    onCalendar: _openCalendar,
                  ),
                  _ProfileDashboard(student: student, onSignOut: _signOut),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Advisor',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline_rounded),
            selectedIcon: Icon(Icons.check_circle_rounded),
            label: 'Academics',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle_rounded),
            label: 'Profile',
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
    required this.error,
    required this.onFixWeek,
    required this.onResults,
    required this.onCourses,
  });

  final Student student;
  final Map<String, dynamic>? progress;
  final String? error;
  final VoidCallback onFixWeek;
  final VoidCallback onResults;
  final VoidCallback onCourses;

  @override
  Widget build(BuildContext context) {
    final courses = _progressCourses(progress);
    final health = _asDouble(progress?['overall_academic_health']);
    final assessments = courses
        .expand(
          (course) => (course['assessments'] as List<dynamic>?) ?? const [],
        )
        .whereType<Map<String, dynamic>>()
        .toList();
    final completedWork = assessments
        .where((item) => item['mark'] != null)
        .length;
    final needsAttention = courses
        .where((course) => course['risk_level'] != null)
        .length;
    return ListView(
      key: const PageStorageKey('home-dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (error != null) _InlineError(message: error!),
        _HealthCard(
          health: health,
          semester: (progress?['semester'] as String?) ?? 'Current semester',
          studentId: student.studentId,
        ),
        const SizedBox(height: 18),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.12,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _MetricCard(
              icon: Icons.school_outlined,
              color: _dashboardCyan,
              value: student.gpa?.toStringAsFixed(2) ?? '—',
              title: 'Current GPA',
              subtitle: 'Official student record',
            ),
            _MetricCard(
              icon: Icons.task_alt,
              color: const Color(0xFF22B98B),
              value: '$completedWork',
              title: 'Completed work',
              subtitle: 'Recorded assessments',
            ),
            _MetricCard(
              key: const Key('open-courses'),
              icon: Icons.menu_book_outlined,
              color: _dashboardIndigo,
              value: '${courses.isEmpty ? student.courses.length : courses.length}',
              title: 'Courses',
              subtitle: 'Tap for courses & schedule',
              onTap: onCourses,
            ),
            _MetricCard(
              icon: Icons.bolt,
              color: _dashboardCoral,
              value: '$needsAttention',
              title: 'Need attention',
              subtitle: 'Review recommended',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GradientAction(
          key: const Key('fix-my-week'),
          icon: Icons.auto_awesome,
          title: 'FIX MY WEEK',
          subtitle: 'Turn your priorities into a focused plan',
          onTap: onFixWeek,
        ),
        const SizedBox(height: 12),
        _SurfaceAction(
          key: const Key('open-results'),
          icon: Icons.assessment_outlined,
          title: 'Results',
          subtitle: 'View marks from the shared AAST database',
          onTap: onResults,
        ),
        const SizedBox(height: 24),
        Text(
          'Academic insights',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: _dashboardInk,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Generated from your live progress data',
          style: TextStyle(color: _dashboardMuted),
        ),
        const SizedBox(height: 12),
        ...courses.expand((course) {
          final risks = ((course['risks'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .take(2);
          return risks.map(
            (risk) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RiskCard(course: course, risk: risk),
            ),
          );
        }),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.health,
    required this.semester,
    required this.studentId,
  });
  final double? health;
  final String semester;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final score = health?.round();
    final attention = score != null && score < 60;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_dashboardHeroStart, _dashboardHeroEnd],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _dashboardBorder),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 112,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: health == null ? 0 : (health! / 100).clamp(0, 1),
                  strokeWidth: 11,
                  backgroundColor: _dashboardTrack,
                  color: attention ? _dashboardCoral : _dashboardCyan,
                ),
                Center(
                  child: Text(
                    score == null ? '—' : '$score%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _dashboardInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACADEMIC HEALTH',
                  style: TextStyle(
                    color: _dashboardMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: attention
                        ? const Color(0xFFFFE4E9)
                        : const Color(0xFFDDF7F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    attention ? 'NEEDS ATTENTION' : 'ON TRACK',
                    style: TextStyle(
                      color: attention
                          ? const Color(0xFFD84460)
                          : const Color(0xFF148267),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  semester,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _dashboardInk,
                  ),
                ),
                Text(studentId, style: TextStyle(color: _dashboardMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _dashboardSurface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _dashboardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: color),
                ],
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: _dashboardInk,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _dashboardInk,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: _dashboardMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProgressDashboard extends StatelessWidget {
  const _ProgressDashboard({required this.progress, required this.error});
  final Map<String, dynamic>? progress;
  final String? error;

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
                    child: Text(
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
              Text(
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
              Text(
                '${((week / 14) * 100).round()}% of the semester timeline',
                style: TextStyle(color: _dashboardMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Course performance',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: _dashboardInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Health, completion, and current trend',
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
            child: _CourseProgressCard(course: course),
          ),
        ),
      ],
    );
  }
}

class _CourseProgressCard extends StatelessWidget {
  const _CourseProgressCard({required this.course});
  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final metrics = (course['metrics'] as Map<String, dynamic>?) ?? const {};
    final health = _asDouble(metrics['course_health']);
    final lectures = _asDouble(metrics['lecture_completion']) ?? 0;
    final assessments = _asDouble(metrics['assessment_completion']) ?? 0;
    final risky = course['risk_level'] != null;
    return Container(
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
                  color: (risky ? _dashboardCoral : _dashboardCyan).withValues(
                    alpha: 0.12,
                  ),
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
                    Text(
                      course['course_name'] as String? ?? 'Course',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      course['course_id']?.toString() ?? '',
                      style: TextStyle(color: _dashboardMuted),
                    ),
                  ],
                ),
              ),
              Text(
                health == null ? '—' : '${health.round()}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: risky ? _dashboardCoral : _dashboardCyan,
                ),
              ),
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
        ],
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
        child: Text(label, style: TextStyle(color: _dashboardMuted)),
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
        child: Text(
          '${value.round()}%',
          textAlign: TextAlign.end,
          style: TextStyle(color: _dashboardMuted),
        ),
      ),
    ],
  );
}

class _AdvisorLanding extends StatelessWidget {
  const _AdvisorLanding({required this.student, required this.onOpenAdvisor});
  final Student student;
  final VoidCallback onOpenAdvisor;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5965F2), Color(0xFF8252E9)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 42),
            const SizedBox(height: 40),
            Text(
              'Hi ${student.name.split(' ').first}, what are we solving?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'I can explain your progress, identify weak areas, help you prioritize coursework, and build a study strategy using your academic context.',
              style: TextStyle(color: Color(0xFFE4E6FF), height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Try asking',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: _dashboardInk,
        ),
      ),
      const SizedBox(height: 12),
      for (final label in [
        'Analyze my progress',
        'What should I study today?',
        'Find my weak courses',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            onPressed: onOpenAdvisor,
            icon: const Icon(Icons.north_east),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(label),
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('open-advisor'),
        onPressed: onOpenAdvisor,
        icon: const Icon(Icons.auto_awesome),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 15),
          child: Text('Open Advisor chat'),
        ),
      ),
    ],
  );
}

class _AcademicsDashboard extends StatelessWidget {
  const _AcademicsDashboard({
    required this.courses,
    required this.onResults,
    required this.onPlanner,
    required this.onCalendar,
  });
  final List<Map<String, dynamic>> courses;
  final VoidCallback onResults;
  final VoidCallback onPlanner;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    final assessments =
        <({Map<String, dynamic> course, Map<String, dynamic> assessment})>[];
    for (final course in courses) {
      for (final assessment
          in ((course['assessments'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()) {
        assessments.add((course: course, assessment: assessment));
      }
    }
    return ListView(
      key: const PageStorageKey('academics-dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _dashboardSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _dashboardBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: _dashboardCyan),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Assessment marks and due weeks come directly from AegisOS.',
                  style: TextStyle(color: _dashboardInk, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (assessments.isEmpty)
          const _EmptyCard(message: 'No assessments have been recorded yet.'),
        ...assessments.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AssessmentCard(
              course: item.course,
              assessment: item.assessment,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SurfaceAction(
          key: const Key('open-calendar'),
          icon: Icons.calendar_month_rounded,
          title: 'My Calendar',
          subtitle: 'Exams, deadlines, personal events, and AI study time',
          onTap: onCalendar,
        ),
        const SizedBox(height: 10),
        _SurfaceAction(
          key: const Key('open-semester-planner'),
          icon: Icons.route_rounded,
          title: 'Smart Semester Planner',
          subtitle: 'Plan courses, prerequisites, GPA, and graduation',
          onTap: onPlanner,
        ),
        const SizedBox(height: 10),
        _SurfaceAction(
          icon: Icons.assessment_outlined,
          title: 'Results',
          subtitle: 'Open your complete semester results',
          onTap: onResults,
        ),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.course, required this.assessment});
  final Map<String, dynamic> course;
  final Map<String, dynamic> assessment;
  @override
  Widget build(BuildContext context) {
    final mark = _asDouble(assessment['mark']);
    final max =
        _asDouble(assessment['max_marks']) ??
        _asDouble(assessment['weight']) ??
        0;
    final recorded = mark != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dashboardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dashboardBorder),
      ),
      child: Row(
        children: [
          Icon(
            recorded ? Icons.check_box : Icons.check_box_outline_blank,
            color: recorded ? const Color(0xFF1CA77F) : _dashboardMuted,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment['name'] as String? ?? 'Assessment',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${course['course_name']} · ${assessment['assessment_type']}',
                  style: TextStyle(color: _dashboardMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: recorded
                  ? const Color(0xFFDDF7F1)
                  : const Color(0xFFEEF1F5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              recorded
                  ? '${mark.toStringAsFixed(mark % 1 == 0 ? 0 : 1)}/${max.toStringAsFixed(0)}'
                  : 'DUE W${assessment['due_week']}',
              style: TextStyle(
                color: recorded ? const Color(0xFF148267) : _dashboardMuted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
              backgroundColor: const Color(0xFFE6E9FF),
              foregroundColor: _dashboardIndigo,
              child: Text(
                _initials(student.name),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              student.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: _dashboardInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(student.studentId, style: TextStyle(color: _dashboardMuted)),
            const SizedBox(height: 12),
            Chip(
              label: Text(student.major.toUpperCase()),
              backgroundColor: const Color(0xFFE7F7FA),
              labelStyle: const TextStyle(
                color: Color(0xFF16879B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Text(
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
          child: Text('Sign out'),
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
    title: Text(label),
    subtitle: Text(value),
    shape: Border(bottom: BorderSide(color: _dashboardBorder)),
  );
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.course, required this.risk});
  final Map<String, dynamic> course;
  final Map<String, dynamic> risk;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _dashboardSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isDarkModeEnabled
            ? const Color(0xFF713746)
            : const Color(0xFFFFD3DB),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: _dashboardCoral),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${course['course_name']} needs attention',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _dashboardInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                risk['message'] as String? ?? '',
                style: TextStyle(color: _dashboardMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
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
            colors: [_dashboardIndigo, Color(0xFF8252E9)],
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
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 12),
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
              backgroundColor: const Color(0xFFE7F7FA),
              foregroundColor: _dashboardCyan,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _dashboardInk,
                    ),
                  ),
                  Text(
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
      color: const Color(0xFFE7F7FA),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'LIVE DATA',
      style: TextStyle(
        color: Color(0xFF16879B),
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
    child: Text(
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
    child: Text(
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
            .showSnackBar(SnackBar(content: Text(error.message)));
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
      tooltip: 'Notifications',
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
                child: Text(
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
                    child: Text(
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
                      child: const Text('Mark all read'),
                    ),
                  IconButton(
                    tooltip: 'Close notifications',
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
                child: Text(
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
                    label: Text(filter),
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
                        child: Text(
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
                            title: Text(
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
                                  Text(notification.body),
                                  const SizedBox(height: 5),
                                  Text(
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
