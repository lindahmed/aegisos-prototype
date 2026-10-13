import 'dart:async';

import 'package:flutter/material.dart';

import '../models/semester_plan.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

const _plannerIndigo = Color(0xFF5965F2);
const _plannerCyan = Color(0xFF20B8CD);
const _plannerGreen = Color(0xFF1A9B78);
const _plannerAmber = Color(0xFFF0A12A);
const _gradePoints = <String, double>{
  'A': 4.0,
  'A-': 3.7,
  'B+': 3.3,
  'B': 3.0,
  'B-': 2.7,
  'C+': 2.3,
  'C': 2.0,
  'D': 1.0,
};

class SemesterPlannerScreen extends StatefulWidget {
  const SemesterPlannerScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<SemesterPlannerScreen> createState() => _SemesterPlannerScreenState();
}

class _SemesterPlannerScreenState extends State<SemesterPlannerScreen> {
  SemesterPlan? _plan;
  String? _error;
  bool _loading = true;
  String _expectedGrade = 'B+';
  String _selectedRouteId = 'normal';
  final Set<String> _selectedIds = {};

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
      final plan = await widget.apiService.getSemesterPlan(
        widget.student.studentId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selectedIds
          ..clear()
          ..addAll(plan.recommendedCourses.map((course) => course.id));
        _selectedRouteId = plan.bestOptionId;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PlanCourse> get _selectedCourses {
    final plan = _plan;
    if (plan == null) return const [];
    return plan.candidateCourses
        .where((course) => _selectedIds.contains(course.id))
        .toList();
  }

  int get _selectedCredits =>
      _selectedCourses.fold(0, (total, course) => total + course.creditHours);

  double get _projectedGpa {
    final plan = _plan;
    if (plan == null) return 0;
    final oldCredits = plan.completedCreditHours;
    final newCredits = _selectedCredits;
    if (oldCredits + newCredits == 0) return _gradePoints[_expectedGrade]!;
    return (plan.currentGpa * oldCredits +
            _gradePoints[_expectedGrade]! * newCredits) /
        (oldCredits + newCredits);
  }

  List<(PlanCourse, PlanCourse)> get _conflicts {
    final courses = _selectedCourses;
    final conflicts = <(PlanCourse, PlanCourse)>[];
    for (var index = 0; index < courses.length; index++) {
      for (
        var otherIndex = index + 1;
        otherIndex < courses.length;
        otherIndex++
      ) {
        if (_coursesConflict(courses[index], courses[otherIndex])) {
          conflicts.add((courses[index], courses[otherIndex]));
        }
      }
    }
    return conflicts;
  }

  static bool _coursesConflict(PlanCourse first, PlanCourse second) {
    for (final left in first.schedule) {
      for (final right in second.schedule) {
        if (left.day.toLowerCase() == right.day.toLowerCase() &&
            left.startMinute < right.endMinute &&
            right.startMinute < left.endMinute) {
          return true;
        }
      }
    }
    return false;
  }

  void _toggleCourse(PlanCourse course, bool selected) {
    if (!course.canSelect) return;
    final plan = _plan;
    if (selected &&
        plan != null &&
        _selectedCredits + course.creditHours > plan.maximumCreditHours) {
      final message = plan.halfLoad
          ? 'Half-load limit: GPA below 2.0 allows up to 9 credits, usually 3 courses.'
          : 'This selection would exceed the ${plan.maximumCreditHours}-credit maximum.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() {
      if (selected) {
        _selectedIds.add(course.id);
      } else {
        _selectedIds.remove(course.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Smart Semester Planner',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: const [ThemeModeToggleButton(), SizedBox(width: 8)],
    ),
    body: _loading && _plan == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _plan == null
        ? _PlannerError(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: () => _load(forceRefresh: true),
            child: _buildPlan(),
          ),
  );

  Widget _buildPlan() {
    final plan = _plan!;
    final selectedRoute = plan.graduationOptions.firstWhere(
      (option) => option.id == _selectedRouteId && option.available,
      orElse: () => plan.graduationOptions.firstWhere(
        (option) => option.available,
        orElse: () => plan.graduationOptions.first,
      ),
    );
    final remaining = plan.candidateCourses
        .where(
          (course) => !plan.recommendedCourses.any(
            (recommended) => recommended.id == course.id,
          ),
        )
        .toList();
    return ListView(
      key: const Key('semester-planner-page'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        _PlannerHero(
          nextSemester: plan.nextSemester,
          maximumProgramSemesters: plan.maximumProgramSemesters,
          selectedCredits: _selectedCredits,
          projectedGpa: _projectedGpa,
          minimumSemesters: selectedRoute.regularSemesters,
        ),
        const SizedBox(height: 24),
        const _SectionHeading(
          title: 'Recommended courses',
          subtitle: 'Built from your curriculum, completed courses, and prerequisites.',
        ),
        const SizedBox(height: 12),
        if (plan.recommendedCourses.isEmpty)
          const _InfoCard(
            icon: Icons.celebration_outlined,
            title: 'No remaining recommended courses',
            body: 'Your database record has no uncompleted curriculum courses to plan.',
          )
        else
          ...plan.recommendedCourses.map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CourseChoiceCard(
                course: course,
                selected: _selectedIds.contains(course.id),
                onChanged: (value) => _toggleCourse(course, value),
              ),
            ),
          ),
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 4),
          _MoreCoursesCard(
            courses: remaining,
            selectedIds: _selectedIds,
            onChanged: _toggleCourse,
          ),
        ],
        const SizedBox(height: 24),
        _SectionHeading(
          title: 'Load & GPA preview',
          subtitle: plan.halfLoad
              ? 'GPA below 2.0 activates a 9-credit limit—normally 3 courses.'
              : 'Adjust the selected courses and expected average grade.',
        ),
        const SizedBox(height: 12),
        _ProjectionCard(
          currentGpa: plan.currentGpa,
          projectedGpa: _projectedGpa,
          credits: _selectedCredits,
          maxCredits: plan.maximumCreditHours,
          halfLoad: plan.halfLoad,
          expectedGrade: _expectedGrade,
          onGradeChanged: (grade) => setState(() => _expectedGrade = grade),
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.calculate_outlined,
          title: 'Credit-hour estimate',
          body: plan.creditNote,
        ),
        const SizedBox(height: 24),
        const _SectionHeading(
          title: 'Schedule check',
          subtitle: 'Overlapping timetable slots are detected automatically.',
        ),
        const SizedBox(height: 12),
        _ScheduleCard(
          available: plan.scheduleStatus == 'checked',
          note: plan.scheduleNote,
          conflicts: _conflicts,
        ),
        const SizedBox(height: 24),
        _SectionHeading(
          title: 'Best Graduation Path',
          subtitle: plan.halfLoad
              ? 'Your 9-credit half-load route is the only available path until your GPA reaches 2.0.'
              : 'Compare normal study, a higher workload, and each available summer.',
        ),
        const SizedBox(height: 12),
        _GraduationSummary(plan: plan),
        const SizedBox(height: 10),
        ...plan.graduationOptions.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GraduationOptionCard(
              option: option,
              selected: option.id == selectedRoute.id,
              recommended: option.id == plan.bestOptionId,
              onTap: option.available
                  ? () => setState(() => _selectedRouteId = option.id)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${selectedRoute.title} plan',
          style: TextStyle(
            color: appScreenInk,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (selectedRoute.terms.isEmpty)
          _InfoCard(
            icon: Icons.info_outline_rounded,
            title: selectedRoute.available
                ? 'No remaining terms'
                : 'Route unavailable',
            body: selectedRoute.note,
          )
        else
          ...selectedRoute.terms.map(
            (term) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PathTermCard(term: term),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          plan.graduationPolicyNote.isEmpty
              ? plan.graduationNote
              : plan.graduationPolicyNote,
          style: TextStyle(color: appScreenMuted, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

class _PlannerHero extends StatelessWidget {
  const _PlannerHero({
    required this.nextSemester,
    required this.maximumProgramSemesters,
    required this.selectedCredits,
    required this.projectedGpa,
    required this.minimumSemesters,
  });
  final int nextSemester;
  final int maximumProgramSemesters;
  final int selectedCredits;
  final double projectedGpa;
  final int minimumSemesters;

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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _plannerIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'SEMESTER $nextSemester OF $maximumProgramSemesters',
            style: const TextStyle(
              color: _plannerIndigo,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Plan with confidence',
          style: TextStyle(
            color: appScreenInk,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select courses and preview the academic impact before registration.',
          style: TextStyle(color: appScreenMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            _HeroStat(value: '$selectedCredits', label: 'Credits'),
            _HeroStat(
              value: projectedGpa.toStringAsFixed(2),
              label: 'Projected GPA',
            ),
            _HeroStat(value: '$minimumSemesters', label: 'Regular terms'),
          ],
        ),
      ],
    ),
  );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        Text(label, style: TextStyle(color: appScreenMuted, fontSize: 11)),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(color: appScreenMuted, height: 1.35)),
    ],
  );
}

class _CourseChoiceCard extends StatelessWidget {
  const _CourseChoiceCard({
    required this.course,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });
  final PlanCourse course;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statusColor = course.eligibility == 'eligible'
        ? _plannerGreen
        : course.eligibility == 'conditional'
        ? _plannerAmber
        : Theme.of(context).colorScheme.error;
    final statusLabel = course.eligibility == 'conditional'
        ? 'PASS CURRENT PREREQ'
        : course.eligibility.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appScreenSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? _plannerIndigo.withValues(alpha: 0.65)
              : appScreenBorder,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: course.canSelect
                    ? (value) => onChanged(value ?? false)
                    : null,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.code,
                      style: const TextStyle(
                        color: _plannerIndigo,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      course.name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${course.creditHours} CR',
                style: TextStyle(
                  color: appScreenMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _StatusPill(label: statusLabel, color: statusColor),
                const Spacer(),
                Text(
                  'Curriculum S${course.curriculumSemester ?? '—'}',
                  style: TextStyle(color: appScreenMuted, fontSize: 12),
                ),
              ],
            ),
            if (course.prerequisites.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Prerequisites',
                  style: TextStyle(
                    color: appScreenMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              ...course.prerequisites.map(
                (requirement) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Icon(
                        requirement.status == 'completed'
                            ? Icons.check_circle_rounded
                            : requirement.status == 'in_progress'
                            ? Icons.timelapse_rounded
                            : Icons.lock_outline_rounded,
                        color: requirement.status == 'completed'
                            ? _plannerGreen
                            : requirement.status == 'in_progress'
                            ? _plannerAmber
                            : Theme.of(context).colorScheme.error,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${requirement.courseCode} · ${requirement.status.replaceAll('_', ' ')}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _MoreCoursesCard extends StatelessWidget {
  const _MoreCoursesCard({
    required this.courses,
    required this.selectedIds,
    required this.onChanged,
  });
  final List<PlanCourse> courses;
  final Set<String> selectedIds;
  final void Function(PlanCourse, bool) onChanged;
  @override
  Widget build(BuildContext context) => Material(
    color: appScreenSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: appScreenBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      title: const Text(
        'Other curriculum courses',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${courses.length} courses · blocked courses show what is missing',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: courses
          .map(
            (course) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _CourseChoiceCard(
                course: course,
                selected: selectedIds.contains(course.id),
                onChanged: (value) => onChanged(course, value),
                compact: true,
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({
    required this.currentGpa,
    required this.projectedGpa,
    required this.credits,
    required this.maxCredits,
    required this.halfLoad,
    required this.expectedGrade,
    required this.onGradeChanged,
  });
  final double currentGpa;
  final double projectedGpa;
  final int credits;
  final int maxCredits;
  final bool halfLoad;
  final String expectedGrade;
  final ValueChanged<String> onGradeChanged;

  @override
  Widget build(BuildContext context) {
    final overloaded = credits > maxCredits;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appScreenSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: overloaded
              ? Theme.of(context).colorScheme.error
              : appScreenBorder,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Metric(
                value: currentGpa.toStringAsFixed(2),
                label: 'Current GPA',
              ),
              Icon(Icons.arrow_forward_rounded, color: appScreenMuted),
              _Metric(
                value: projectedGpa.toStringAsFixed(2),
                label: 'Projected GPA',
                color: _plannerIndigo,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expected average',
                      style: TextStyle(color: appScreenMuted, fontSize: 12),
                    ),
                    DropdownButton<String>(
                      value: expectedGrade,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: _gradePoints.keys
                          .map(
                            (grade) => DropdownMenuItem(
                              value: grade,
                              child: Text(
                                '$grade  ·  ${_gradePoints[grade]!.toStringAsFixed(1)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (grade) {
                        if (grade != null) onGradeChanged(grade);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              _StatusPill(
                label: '$credits / $maxCredits CREDITS',
                color: overloaded
                    ? Theme.of(context).colorScheme.error
                    : _plannerGreen,
              ),
            ],
          ),
          if (overloaded) ...[
            const SizedBox(height: 10),
            Text(
              'Remove a course to stay within the $maxCredits-credit maximum.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (halfLoad) ...[
            const SizedBox(height: 10),
            Text(
              'Half-load rule: because your GPA is below 2.0, you can select up to 9 credits—usually 3 courses. The limit is removed only after your GPA returns to 2.0 or higher.',
              style: const TextStyle(
                color: _plannerAmber,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(label, style: TextStyle(color: appScreenMuted, fontSize: 12)),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: appScreenSurfaceRaised,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: appScreenBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _plannerCyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  color: appScreenMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.available,
    required this.note,
    required this.conflicts,
  });
  final bool available;
  final String note;
  final List<(PlanCourse, PlanCourse)> conflicts;
  @override
  Widget build(BuildContext context) {
    if (!available) {
      return _InfoCard(
        icon: Icons.event_busy_outlined,
        title: 'Timetable data unavailable',
        body: note,
      );
    }
    final hasConflicts = conflicts.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: appScreenSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasConflicts
              ? Theme.of(context).colorScheme.error
              : _plannerGreen,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasConflicts
                ? Icons.warning_amber_rounded
                : Icons.event_available_rounded,
            color: hasConflicts
                ? Theme.of(context).colorScheme.error
                : _plannerGreen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasConflicts
                  ? conflicts
                        .map(
                          (pair) => '${pair.$1.code} overlaps ${pair.$2.code}',
                        )
                        .join('\n')
                  : 'No timetable conflicts in your selected courses.',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraduationSummary extends StatelessWidget {
  const _GraduationSummary({required this.plan});
  final SemesterPlan plan;
  @override
  Widget build(BuildContext context) {
    final needsExtension = plan.graduationStatus == 'late';
    final best = plan.graduationOptions.firstWhere(
      (option) => option.id == plan.bestOptionId,
      orElse: () => plan.graduationOptions.first,
    );
    final color = plan.halfLoad || needsExtension
        ? _plannerAmber
        : _plannerIndigo;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDarkModeEnabled ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            plan.halfLoad || needsExtension
                ? Icons.warning_amber_rounded
                : Icons.route_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              plan.halfLoad
                  ? 'Best available path: Half-load route. Your GPA is below 2.0, so regular semesters are limited to 9 credits and graduation may take longer.'
                  : plan.bestOptionId == 'normal'
                  ? '${plan.remainingCourses} courses remain. The normal route is currently the best path because the other choices do not shorten the prerequisite-valid sequence.'
                  : '${plan.remainingCourses} courses remain. Best option: ${best.title}. Select any route below to compare its complete sequence.',
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraduationOptionCard extends StatelessWidget {
  const _GraduationOptionCard({
    required this.option,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final GraduationOption option;
  final bool selected;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = option.available ? _plannerIndigo : appScreenMuted;
    final details = option.available
        ? <String>[
            if (option.maximumRegularCredits != null)
              'Up to ${option.maximumRegularCredits} credits',
            '${option.regularSemesters} regular semester${option.regularSemesters == 1 ? '' : 's'}',
            if (option.summerTerms > 0)
              '${option.summerTerms} summer term${option.summerTerms == 1 ? '' : 's'}',
            if (option.extensionTerms > 0)
              '${option.extensionTerms} extension term${option.extensionTerms == 1 ? '' : 's'}',
          ]
        : <String>[];
    return Material(
      color: option.available
          ? selected
                ? _plannerIndigo.withValues(alpha: 0.09)
                : appScreenSurface
          : appScreenSurfaceRaised.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? _plannerIndigo : appScreenBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    option.id.startsWith('summer_')
                        ? Icons.wb_sunny_outlined
                        : option.id == 'increased_workload'
                        ? Icons.trending_up_rounded
                        : Icons.school_outlined,
                    color: accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.title,
                      style: TextStyle(
                        color: option.available ? appScreenInk : appScreenMuted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _plannerGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'BEST OPTION',
                        style: TextStyle(
                          color: _plannerGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  else if (!option.available)
                    const Text(
                      'UNAVAILABLE',
                      style: TextStyle(
                        color: _plannerAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  else
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: accent,
                    ),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  details.join(' · '),
                  style: TextStyle(
                    color: option.available ? appScreenInk : appScreenMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                option.note,
                style: TextStyle(
                  color: appScreenMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathTermCard extends StatelessWidget {
  const _PathTermCard({required this.term});
  final PlanTerm term;
  @override
  Widget build(BuildContext context) => Material(
    color: appScreenSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: BorderSide(color: appScreenBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: CircleAvatar(
        backgroundColor:
            (term.termType == 'summer'
                    ? _plannerAmber
                    : term.termType == 'extension'
                    ? _plannerCyan
                    : _plannerIndigo)
                .withValues(alpha: 0.12),
        foregroundColor: term.termType == 'summer'
            ? _plannerAmber
            : term.termType == 'extension'
            ? _plannerCyan
            : _plannerIndigo,
        child: Icon(
          term.termType == 'summer'
              ? Icons.wb_sunny_outlined
              : term.termType == 'extension'
              ? Icons.more_time_rounded
              : Icons.school_outlined,
          size: 20,
        ),
      ),
      title: Text(
        term.label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${term.courses.length} courses · ${term.creditHours} estimated credits',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      children: term.courses
          .map(
            (course) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_rounded, color: _plannerCyan),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${course.code} · ${course.name}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _PlannerError extends StatelessWidget {
  const _PlannerError({required this.message, required this.onRetry});
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
