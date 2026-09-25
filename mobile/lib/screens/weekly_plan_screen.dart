import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/weekly_plan.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

Color get _ink => appScreenInk;
Color get _muted => appScreenMuted;
Color get _surface => appScreenSurface;
Color get _border => appScreenBorder;
const _indigo = Color(0xFF5965F2);

class WeeklyPlanScreen extends StatefulWidget {
  const WeeklyPlanScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  WeeklyPlan? _plan;
  String? _error;
  bool _loading = true;
  final Set<String> _savingTaskIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlan());
  }

  Future<void> _loadPlan({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final plan = await widget.apiService.getWeeklyPlan(
        widget.student.studentId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
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

  Future<void> _setCompleted(WeeklyPlanItem item, bool completed) async {
    if (_savingTaskIds.contains(item.taskId) || _plan == null) return;
    final previous = item;
    setState(() {
      _savingTaskIds.add(item.taskId);
      _plan = _plan!.replaceItem(
        item.withStatus(completed ? 'completed' : 'pending'),
      );
    });
    try {
      final saved = await widget.apiService.setWeeklyPlanItemStatus(
        studentId: widget.student.studentId,
        taskId: item.taskId,
        completed: completed,
      );
      if (!mounted) return;
      setState(() => _plan = _plan!.replaceItem(saved));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _plan = _plan!.replaceItem(previous));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _savingTaskIds.remove(item.taskId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Fix My Week',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh plan',
            onPressed: _loading ? null : () => _loadPlan(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const ThemeModeToggleButton(),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _plan == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _plan == null) {
      return _PlanError(message: _error!, onRetry: _loadPlan);
    }

    final plan = _plan!;
    final remaining = plan.items.where((item) => !item.isCompleted).length;
    return RefreshIndicator(
      onRefresh: () => _loadPlan(forceRefresh: true),
      child: ListView(
        key: const Key('weekly-plan-page'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5965F2), Color(0xFF27BBD3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WEEK ${plan.currentWeek} PLAN',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.student.name.split(RegExp(r'\s+')).first}, focus on what matters most.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$remaining ${remaining == 1 ? 'priority' : 'priorities'} remaining this week.',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your priorities',
            style: TextStyle(
              color: _ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your progress is saved and a fresh plan appears each week.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 14),
          if (plan.items.isEmpty)
            const _EmptyPlan()
          else
            for (final item in plan.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PriorityCard(
                  item: item,
                  saving: _savingTaskIds.contains(item.taskId),
                  onChanged: (value) => _setCompleted(item, value),
                ),
              ),
        ],
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.item,
    required this.saving,
    required this.onChanged,
  });

  final WeeklyPlanItem item;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = item.taskType == 'risk'
        ? const Color(0xFFFF647C)
        : const Color(0xFF27BBD3);
    final icon = item.taskType == 'risk'
        ? Icons.priority_high_rounded
        : Icons.event_available_outlined;
    return Material(
      key: Key('weekly-task-${item.taskId}'),
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: saving ? null : () => onChanged(!item.isCompleted),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.position}. ${item.courseName}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        decoration: item.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.detail,
                      style: TextStyle(color: _muted, height: 1.35),
                    ),
                    if (item.isCompleted) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Completed',
                        style: TextStyle(
                          color: Color(0xFF22B98B),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              saving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Checkbox(
                      key: Key('weekly-task-checkbox-${item.taskId}'),
                      value: item.isCompleted,
                      activeColor: _indigo,
                      onChanged: (value) => onChanged(value ?? false),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanError extends StatelessWidget {
  const _PlanError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function({bool forceRefresh}) onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: _indigo),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => onRetry(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF22B98B),
          size: 42,
        ),
        const SizedBox(height: 12),
        Text(
          'You are on track',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'No urgent risks or upcoming ungraded assessments were found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );
}
