import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ask_aegis_fab.dart';

class WhatIfSimulatorScreen extends StatefulWidget {
  const WhatIfSimulatorScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<WhatIfSimulatorScreen> createState() => _WhatIfSimulatorScreenState();
}

class _WhatIfSimulatorScreenState extends State<WhatIfSimulatorScreen> {
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _course;
  Map<String, dynamic>? _assessment;
  Map<String, dynamic>? _result;
  double _grade = 85;
  bool _loading = true;
  bool _simulating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  List<Map<String, dynamic>> get _courses =>
      ((_progress?['courses'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((course) => _supportedAssessments(course).isNotEmpty)
          .toList();

  List<Map<String, dynamic>> _supportedAssessments(
    Map<String, dynamic> course,
  ) => ((course['assessments'] as List<dynamic>?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .where(
        (assessment) => const {
          'assignment',
          'lab',
          'quiz',
          'midterm',
          'final',
          'exam',
        }.contains(assessment['assessment_type']?.toString()),
      )
      .toList();

  Future<void> _load() async {
    try {
      final progress = await widget.apiService.getStudentProgress(
        widget.student.studentId,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _course = _courses.isEmpty ? null : _courses.first;
        _assessment = _course == null
            ? null
            : _supportedAssessments(_course!).first;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _simulate() async {
    final course = _course;
    final assessment = _assessment;
    if (course == null || assessment == null || _simulating) return;
    setState(() {
      _simulating = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.apiService.simulateAssessmentGrade(
        studentId: widget.student.studentId,
        courseId: course['course_id'].toString(),
        assessmentId: assessment['assessment_id'].toString(),
        hypotheticalGrade: _grade,
      );
      if (mounted) setState(() => _result = result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('what-if-simulator-page'),
    appBar: AppBar(
      title: const AppText(
        'Grade Impact Simulator',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: const [ThemeModeToggleButton(), SizedBox(width: 8)],
    ),
    floatingActionButton: AskAegisFab(
      onPressed: () => openAskAegis(
        context,
        student: widget.student,
        apiService: widget.apiService,
        prompt: 'I am using the Grade Impact Simulator. Help me understand which realistic grade scenario I should test.',
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _courses.isEmpty
        ? const Center(
            child: AppText('No assessments are available to simulate.'),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [uniTrackBlue, uniTrackSky],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'TEST A FUTURE RESULT',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      'Current GPA: ${widget.student.gpa?.toStringAsFixed(2) ?? '—'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const AppText(
                      'Read-only projection — no official grade is changed.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<Map<String, dynamic>>(
                initialValue: _course,
                decoration: InputDecoration(labelText: tr('Course')),
                items: _courses
                    .map(
                      (course) => DropdownMenuItem(
                        value: course,
                        child: AppText(
                          course['course_name']?.toString() ?? 'Course',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (course) {
                  if (course == null) return;
                  setState(() {
                    _course = course;
                    _assessment = _supportedAssessments(course).first;
                    _result = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<Map<String, dynamic>>(
                key: ValueKey(_course?['course_id']),
                initialValue: _assessment,
                decoration: InputDecoration(labelText: tr('Assessment')),
                items: _course == null
                    ? const []
                    : _supportedAssessments(_course!)
                          .map(
                            (assessment) => DropdownMenuItem(
                              value: assessment,
                              child: AppText(
                                assessment['name']?.toString() ?? 'Assessment',
                              ),
                            ),
                          )
                          .toList(),
                onChanged: (assessment) => setState(() {
                  _assessment = assessment;
                  _result = null;
                }),
              ),
              const SizedBox(height: 22),
              AppText(
                'Hypothetical grade: ${_grade.round()}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Slider(
                value: _grade,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${_grade.round()}%',
                onChanged: (value) => setState(() {
                  _grade = value;
                  _result = null;
                }),
              ),
              FilledButton.icon(
                key: const Key('run-what-if'),
                onPressed: _simulating ? null : _simulate,
                icon: const Icon(Icons.science_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: AppText(
                    _simulating ? 'Calculating…' : 'Run simulation',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AppText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 20),
                _ProjectionCard(result: _result!),
              ],
            ],
          ),
  );
}

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final before = result['before'] as Map<String, dynamic>? ?? const {};
    final after = result['after'] as Map<String, dynamic>? ?? const {};
    final difference =
        result['difference'] as Map<String, dynamic>? ?? const {};
    String metric(Map<String, dynamic> source, String key) {
      final value = source[key] as num?;
      return value == null ? '—' : '${value.toStringAsFixed(1)}%';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appScreenSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: appScreenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            'PROJECTED IMPACT',
            style: TextStyle(
              color: uniTrackBlue,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          _MetricRow(
            label: 'Weighted grade',
            before: metric(before, 'weighted_grade'),
            after: metric(after, 'weighted_grade'),
          ),
          _MetricRow(
            label: 'Course health',
            before: metric(before, 'course_health'),
            after: metric(after, 'course_health'),
          ),
          const SizedBox(height: 10),
          AppText(
            'Impact: ${metric(difference, 'course_health')}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          AppText(
            result['explanation']?.toString() ?? '',
            style: TextStyle(color: appScreenMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Expanded(child: AppText(label)),
        AppText(before, style: TextStyle(color: appScreenMuted)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 9),
          child: Icon(Icons.arrow_forward_rounded, size: 18),
        ),
        AppText(after, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}
