import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Future<void> showRiskDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> course,
  required Map<String, dynamic> risk,
  required VoidCallback onFix,
  required VoidCallback onAddSession,
  required VoidCallback onAskAegis,
}) {
  final reasons = _riskReasons(course, risk);
  final actions = _recommendedActions(risk['code']?.toString() ?? '');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '${course['course_name'] ?? 'Course'} risk explained',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            const AppText('WHY?', style: _headingStyle),
            const SizedBox(height: 8),
            ...reasons.map((item) => _Bullet(text: item)),
            const SizedBox(height: 18),
            const AppText('RECOMMENDED ACTIONS', style: _headingStyle),
            const SizedBox(height: 8),
            ...actions.map((item) => _Bullet(text: item, checked: true)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onFix();
                  },
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const AppText('Build Recovery Plan'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onAddSession();
                  },
                  icon: const Icon(Icons.event_available_outlined),
                  label: const AppText('Add Study Session'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onAskAegis();
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const AppText('Ask AI'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCourseRisksSheet(
  BuildContext context, {
  required Map<String, dynamic> course,
  required bool alreadyInWeekPlanner,
  required VoidCallback onFix,
  required ValueChanged<Map<String, dynamic>> onAddSession,
  required ValueChanged<Map<String, dynamic>> onAskAegis,
}) {
  final risks = ((course['risks'] as List<dynamic>?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (risks.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            AppText(
              '${course['course_name'] ?? 'Course'} risks',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            AppText(
              '${risks.length} active risk${risks.length == 1 ? '' : 's'} with clear reasons and next actions.',
              style: TextStyle(color: appScreenMuted),
            ),
            if (alreadyInWeekPlanner) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: uniTrackBlueSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: uniTrackBlue),
                    SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        'This course already has a priority in Week Planner.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            for (var index = 0; index < risks.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CourseRiskPanel(
                  course: course,
                  risk: risks[index],
                  initiallyExpanded: index == 0,
                  onFix: () {
                    Navigator.pop(sheetContext);
                    onFix();
                  },
                  onAddSession: () {
                    Navigator.pop(sheetContext);
                    onAddSession(risks[index]);
                  },
                  onAskAegis: () {
                    Navigator.pop(sheetContext);
                    onAskAegis(risks[index]);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

List<String> _riskReasons(
  Map<String, dynamic> course,
  Map<String, dynamic> risk,
) {
  final metrics = course['metrics'] as Map<String, dynamic>? ?? const {};
  return <String>[
    if ((risk['message']?.toString() ?? '').isNotEmpty)
      risk['message'].toString(),
    if (metrics['course_health'] != null)
      'Course health: ${(metrics['course_health'] as num).toStringAsFixed(0)}%',
    if (metrics['previous_course_health'] != null)
      'Previous health: ${(metrics['previous_course_health'] as num).toStringAsFixed(0)}%',
    if (metrics['weighted_grade'] != null)
      'Current weighted grade: ${(metrics['weighted_grade'] as num).toStringAsFixed(0)}%',
    if (metrics['lecture_completion'] != null)
      'Lecture completion: ${(metrics['lecture_completion'] as num).toStringAsFixed(0)}%',
  ];
}

class _CourseRiskPanel extends StatelessWidget {
  const _CourseRiskPanel({
    required this.course,
    required this.risk,
    required this.initiallyExpanded,
    required this.onFix,
    required this.onAddSession,
    required this.onAskAegis,
  });

  final Map<String, dynamic> course;
  final Map<String, dynamic> risk;
  final bool initiallyExpanded;
  final VoidCallback onFix;
  final VoidCallback onAddSession;
  final VoidCallback onAskAegis;

  @override
  Widget build(BuildContext context) {
    final reasons = _riskReasons(course, risk);
    final actions = _recommendedActions(risk['code']?.toString() ?? '');
    return Material(
      color: appScreenSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: const Color(0xFFFF647C).withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFFF647C),
        ),
        title: AppText(
          risk['message']?.toString() ?? 'This course needs attention.',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: AppText('WHY?', style: _headingStyle),
          ),
          const SizedBox(height: 8),
          ...reasons.map((item) => _Bullet(text: item)),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: AppText('RECOMMENDED ACTIONS', style: _headingStyle),
          ),
          const SizedBox(height: 8),
          ...actions.map((item) => _Bullet(text: item, checked: true)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onFix,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const AppText('Fix This Risk'),
              ),
              OutlinedButton.icon(
                onPressed: onAddSession,
                icon: const Icon(Icons.event_available_outlined),
                label: const AppText('Add Study Session'),
              ),
              TextButton.icon(
                onPressed: onAskAegis,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const AppText('Ask AI'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _headingStyle = TextStyle(
  color: uniTrackBlue,
  fontSize: 12,
  fontWeight: FontWeight.w900,
  letterSpacing: 0.8,
);

List<String> _recommendedActions(String code) => switch (code) {
  'lecture_backlog' => [
    'Finish the next incomplete lecture.',
    'Reserve a focused study session.',
    'Ask AI for a catch-up plan.',
  ],
  'low_midterm' || 'repeated_poor_assessments' => [
    'Review the weakest assessed topics.',
    'Redo practice questions without notes.',
    'Schedule two short revision sessions.',
  ],
  'incomplete_exam_coverage' => [
    'Complete one uncovered topic first.',
    'Create a five-line summary.',
    'Solve three related questions.',
  ],
  _ => [
    'Review the risk evidence.',
    'Add one focused study session.',
    'Use Week Planner to prioritize the next action.',
  ],
};

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.checked = false});

  final String text;
  final bool checked;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          checked ? Icons.check_circle_outline : Icons.circle,
          size: checked ? 18 : 7,
          color: checked ? const Color(0xFF1A9B78) : appScreenMuted,
        ),
        const SizedBox(width: 9),
        Expanded(child: AppText(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}
