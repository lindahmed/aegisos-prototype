import 'package:flutter/material.dart';

import '../models/grade_report.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

Color get _surface => appScreenSurface;
Color get _summarySurface => appScreenSurfaceRaised;
Color get _border => appScreenBorder;
Color get _ink => appScreenInk;
Color get _muted => appScreenMuted;
const _teal = Color(0xFF0F7780);
const _gradeInk = Color(0xFF16373A);

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({required this.student, this.apiService, super.key});

  final Student student;
  final ApiService? apiService;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ApiService _apiService;
  late final bool _ownsApiService;
  StudentGradeReport? _report;
  String? _selectedSemester;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final report = await _apiService.getStudentGrades(
        widget.student.studentId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _selectedSemester =
            report.semesters.any((item) => item.semester == _selectedSemester)
            ? _selectedSemester
            : report.semesters.firstOrNull?.semester;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: Color(0xFF27BBD3)),
        title: const Text(
          'Results',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          const ThemeModeToggleButton(),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: _summarySurface,
              foregroundColor: _ink,
              child: Text(_initials(widget.student.name)),
            ),
          ),
        ],
      ),
      body: _loading && _report == null
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _error != null && _report == null
          ? _ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              color: _teal,
              child: _buildResults(),
            ),
    );
  }

  Widget _buildResults() {
    final report = _report!;
    final semester = _selectedSemester;
    final records = report.records
        .where((record) => record.semester == semester)
        .toList();
    final selectedSummary = report.semesters
        .where((item) => item.semester == semester)
        .firstOrNull;
    final displayedGpa = report.cumulativeGpa ?? selectedSummary?.gpa;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            border: Border(bottom: BorderSide(color: _border)),
            boxShadow: [
              BoxShadow(
                color: _ink.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _SummaryPanel(
                  completedCourses: report.completedCourses,
                  gpa: displayedGpa,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Semesters',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              if (report.semesters.isEmpty)
                Text(
                  'No semesters are available yet.',
                  style: TextStyle(color: _muted),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: report.semesters.map((summary) {
                      final selected = summary.semester == semester;
                      return Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: ChoiceChip(
                          selected: selected,
                          showCheckmark: false,
                          label: Text(summary.semester),
                          onSelected: (_) => setState(
                            () => _selectedSemester = summary.semester,
                          ),
                          selectedColor: _teal,
                          backgroundColor: _summarySurface,
                          side: BorderSide(color: selected ? _teal : _border),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : _ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          child: records.isEmpty
              ? const _EmptyResults()
              : Column(
                  children: records
                      .map(
                        (record) => Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: _GradeCard(record: record),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.completedCourses, required this.gpa});

  final int completedCourses;
  final double? gpa;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: _summarySurface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: _SummaryMetric(
                value: completedCourses.toString(),
                label: 'Courses Achieved',
              ),
            ),
            VerticalDivider(color: _border, width: 1),
            Expanded(
              child: _SummaryMetric(
                value: gpa?.toStringAsFixed(2) ?? '—',
                label: 'GPA',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: _ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.record});

  final StudentGradeRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Column(
              children: [
                Text(
                  record.courseCode.toUpperCase(),
                  style: TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.courseName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _border),
                    IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _MarkMetric(
                    value: record.week7ExamMark,
                    label: '7th Week',
                  ),
                ),
                VerticalDivider(width: 1, color: _border),
                Expanded(
                  child: _MarkMetric(
                    value: record.week12ExamMark,
                    label: '12th Week',
                  ),
                ),
                VerticalDivider(width: 1, color: _border),
                Expanded(
                  child: _MarkMetric(
                    value: record.courseworkMark,
                    label: 'Course Work',
                  ),
                ),
                _GradeTile(grade: record.letterGrade),
              ],
            ),
          ),
        ],
      ),
    );
  }

   static String _detailLine(StudentGradeRecord record) {
    if (record.gradeSource == 'transcript') {
      return 'Stored transcript grade · component marks are not available';
    }
    if (record.gradeSource == 'none') {
      return 'No grade has been posted for this course yet';
    }
    return 'Final grade posted';
  }
}

class _MarkMetric extends StatelessWidget {
  const _MarkMetric({required this.value, required this.label});

  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value?.toStringAsFixed(2) ?? '—',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: const TextStyle(
              color: _teal,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({required this.grade});

  final String? grade;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      alignment: Alignment.center,
      color: _gradeColor(grade),
      child: Text(
        grade ?? '—',
        style: const TextStyle(
          color: _gradeInk,
          fontSize: 31,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  static Color _gradeColor(String? grade) {
    if (grade == null) return const Color(0xFFD7E1E8);
    if (grade == 'U') return const Color(0xFFD7E1E8);
    if (grade.startsWith('A')) return const Color(0xFFE9F5C8);
    if (grade.startsWith('B')) return const Color(0xFFE6F2FC);
    if (grade.startsWith('C')) return const Color(0xFFF0EEFA);
    return const Color(0xFFFFE2D9);
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Icon(Icons.school_outlined, color: _muted, size: 46),
          const SizedBox(height: 12),
          Text(
            'No course results are available for this semester.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: _muted, size: 44),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
