import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../theme/app_theme.dart';

Future<StudentCalendarEvent?> showStudySessionDialog(
  BuildContext context, {
  required String courseName,
  required String reason,
  String? courseId,
  bool alreadyInWeekPlanner = false,
}) {
  return showDialog<StudentCalendarEvent>(
    context: context,
    builder: (_) => _StudySessionDialog(
      courseName: courseName,
      reason: reason,
      courseId: courseId,
      alreadyInWeekPlanner: alreadyInWeekPlanner,
    ),
  );
}

class _StudySessionDialog extends StatefulWidget {
  const _StudySessionDialog({
    required this.courseName,
    required this.reason,
    required this.courseId,
    required this.alreadyInWeekPlanner,
  });

  final String courseName;
  final String reason;
  final String? courseId;
  final bool alreadyInWeekPlanner;

  @override
  State<_StudySessionDialog> createState() => _StudySessionDialogState();
}

class _StudySessionDialogState extends State<_StudySessionDialog> {
  late DateTime _date;
  late TimeOfDay _time;
  int _durationMinutes = 60;

  @override
  void initState() {
    super.initState();
    final next = DateTime.now().add(const Duration(hours: 1));
    _date = DateTime(next.year, next.month, next.day);
    _time = TimeOfDay(hour: next.hour, minute: next.minute < 30 ? 30 : 0);
    if (next.minute >= 30) {
      final hourLater = next.add(const Duration(hours: 1));
      _date = DateTime(hourLater.year, hourLater.month, hourLater.day);
      _time = TimeOfDay(hour: hourLater.hour, minute: 0);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null && mounted) setState(() => _time = selected);
  }

  void _save() {
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    Navigator.of(context).pop(
      StudentCalendarEvent(
        id: 'risk-session:${DateTime.now().microsecondsSinceEpoch}',
        title: 'Study ${widget.courseName}',
        description: widget.reason,
        startAt: start,
        endAt: start.add(Duration(minutes: _durationMinutes)),
        type: StudentCalendarEventType.studySession,
        source: StudentCalendarEventSource.student,
        courseId: widget.courseId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const AppText('Add study session'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            widget.courseName,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (widget.alreadyInWeekPlanner) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
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
                      'This course already has a priority in Week Planner. This calendar session will be an additional scheduled time.',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const AppText('Date'),
            subtitle: AppText('${_date.day}/${_date.month}/${_date.year}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded),
            title: const AppText('Start time'),
            subtitle: AppText(_time.format(context)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickTime,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _durationMinutes,
            decoration: InputDecoration(
              labelText: tr('Duration'),
              prefixIcon: const Icon(Icons.timer_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 30, child: AppText('30 minutes')),
              DropdownMenuItem(value: 45, child: AppText('45 minutes')),
              DropdownMenuItem(value: 60, child: AppText('1 hour')),
              DropdownMenuItem(value: 90, child: AppText('1 hour 30 minutes')),
              DropdownMenuItem(value: 120, child: AppText('2 hours')),
            ],
            onChanged: (value) =>
                setState(() => _durationMinutes = value ?? 60),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const AppText('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('confirm-study-session'),
        onPressed: _save,
        icon: const Icon(Icons.add_rounded),
        label: const AppText('Add to Calendar'),
      ),
    ],
  );
}
