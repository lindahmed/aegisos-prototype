import 'dart:async';

import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

const _calendarIndigo = Color(0xFF5965F2);
const _calendarCyan = Color(0xFF20B8CD);
const _calendarGreen = Color(0xFF1A9B78);
const _calendarAmber = Color(0xFFF0A12A);
const _calendarCoral = Color(0xFFFF647C);
const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    required this.student,
    required this.apiService,
    super.key,
  });

  final Student student;
  final ApiService apiService;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Map<String, dynamic>? _academics;
  List<StudentCalendarEvent> _customEvents = [];
  late DateTime _selectedDate;
  late DateTime _month;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
    unawaited(_load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        StudentCalendarStore.load(widget.student.studentId),
        widget.apiService.getStudentAcademics(
          widget.student.studentId,
          forceRefresh: forceRefresh,
        ),
      ]);
      final saved = results[0] as List<StudentCalendarEvent>;
      final academics = results[1] as Map<String, dynamic>;
      final planned = StudentCalendarBuilder.addUrgentStudySessions(
        academics: academics,
        customEvents: saved,
      );
      if (planned.length != saved.length) {
        await StudentCalendarStore.save(widget.student.studentId, planned);
      }
      if (!mounted) return;
      setState(() {
        _academics = academics;
        _customEvents = planned;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StudentCalendarEvent> get _events =>
      [...StudentCalendarBuilder.academicEvents(_academics), ..._customEvents]
        ..sort((first, second) => first.startAt.compareTo(second.startAt));

  List<DateTime> get _days {
    final first = DateTime(_month.year, _month.month);
    final gridStart = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => gridStart.add(Duration(days: index)));
  }

  List<StudentCalendarEvent> _eventsOn(DateTime date) => _events
      .where((event) => DateUtils.isSameDay(event.startAt, date))
      .toList();

  Future<void> _saveCustom(List<StudentCalendarEvent> events) async {
    setState(() => _customEvents = events);
    await StudentCalendarStore.save(widget.student.studentId, events);
  }

  Future<void> _planWithAi() async {
    final academics = _academics;
    if (academics == null) return;
    final next = StudentCalendarBuilder.addUrgentStudySessions(
      academics: academics,
      customEvents: _customEvents,
    );
    final added = next.length - _customEvents.length;
    await _saveCustom(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'No new urgent study sessions are needed right now.'
              : 'AI scheduled $added urgent study session${added == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  Future<void> _removeEvent(StudentCalendarEvent event) =>
      _saveCustom(_customEvents.where((item) => item.id != event.id).toList());

  Future<void> _openAddEvent([DateTime? date]) async {
    final chosenDate = date ?? _selectedDate;
    final event = await showDialog<StudentCalendarEvent>(
      context: context,
      builder: (_) => _AddCalendarEventDialog(initialDate: chosenDate),
    );
    if (event == null) return;
    await _saveCustom([..._customEvents, event]);
    if (!mounted) return;
    setState(() {
      _selectedDate = DateTime(
        event.startAt.year,
        event.startAt.month,
        event.startAt.day,
      );
      _month = DateTime(event.startAt.year, event.startAt.month);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Calendar event added.')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('calendar-page'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Calendar'),
        actions: const [ThemeModeToggleButton(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('calendar-add-event'),
        onPressed: _loading ? null : _openAddEvent,
        backgroundColor: _calendarIndigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add event'),
      ),
      body: _loading && _academics == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _academics == null
          ? _CalendarError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
                children: [
                  _CalendarIntro(
                    semester: _academics?['semester']?.toString() ?? '',
                    currentWeek:
                        (_academics?['current_week'] as num?)?.toInt() ?? 1,
                    onPlanWithAi: _planWithAi,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: appScreenSurface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: appScreenBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _MonthToolbar(
                          month: _month,
                          onPrevious: () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month - 1,
                            ),
                          ),
                          onNext: () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month + 1,
                            ),
                          ),
                          onToday: () {
                            final now = DateTime.now();
                            setState(() {
                              _selectedDate = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              _month = DateTime(now.year, now.month);
                            });
                          },
                        ),
                        Container(
                          color: appScreenSurfaceRaised,
                          child: Row(
                            children: _weekdays
                                .map(
                                  (day) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        day,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: appScreenMuted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _days.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: 0.64,
                              ),
                          itemBuilder: (context, index) {
                            final day = _days[index];
                            return _CalendarDay(
                              date: day,
                              outside: day.month != _month.month,
                              selected: DateUtils.isSameDay(day, _selectedDate),
                              today: DateUtils.isSameDay(day, DateTime.now()),
                              events: _eventsOn(day),
                              onTap: () => setState(() => _selectedDate = day),
                              onLongPress: () => _openAddEvent(day),
                            );
                          },
                        ),
                        const _CalendarLegend(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Agenda(
                    date: _selectedDate,
                    events: _eventsOn(_selectedDate),
                    onAdd: () => _openAddEvent(),
                    onDelete: _removeEvent,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CalendarIntro extends StatelessWidget {
  const _CalendarIntro({
    required this.semester,
    required this.currentWeek,
    required this.onPlanWithAi,
  });

  final String semester;
  final int currentWeek;
  final VoidCallback onPlanWithAi;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isDarkModeEnabled
            ? const [Color(0xFF17243D), Color(0xFF123440)]
            : const [Color(0xFFEEF0FF), Color(0xFFE5F8FA)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _calendarCyan.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_rounded, color: _calendarIndigo),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '$semester · Week $currentWeek',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('calendar-plan-ai'),
              onPressed: onPlanWithAi,
              icon: const Icon(Icons.auto_awesome_rounded, size: 17),
              label: const Text('Plan with AI'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Exams are placed Monday at 9:00 AM and coursework deadlines Sunday at 10:00 PM of their academic week.',
          style: TextStyle(color: appScreenMuted, fontSize: 12, height: 1.45),
        ),
      ],
    ),
  );
}

class _MonthToolbar extends StatelessWidget {
  const _MonthToolbar({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            '${_months[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        TextButton(onPressed: onToday, child: const Text('Today')),
      ],
    ),
  );
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.outside,
    required this.selected,
    required this.today,
    required this.events,
    required this.onTap,
    required this.onLongPress,
  });

  final DateTime date;
  final bool outside;
  final bool selected;
  final bool today;
  final List<StudentCalendarEvent> events;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? _calendarIndigo.withValues(alpha: 0.12)
            : outside
            ? appScreenSurfaceRaised.withValues(alpha: 0.45)
            : appScreenSurface,
        border: Border.all(
          color: selected ? _calendarIndigo : appScreenBorder,
          width: selected ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: today ? _calendarIndigo : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: today
                    ? Colors.white
                    : outside
                    ? appScreenMuted.withValues(alpha: 0.55)
                    : appScreenInk,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: events
                .take(4)
                .map(
                  (event) => Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _eventColor(event.type),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
                .toList(),
          ),
          if (events.length > 4)
            Text(
              '+${events.length - 4}',
              style: TextStyle(color: appScreenMuted, fontSize: 8),
            ),
        ],
      ),
    ),
  );
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 14,
      runSpacing: 7,
      children: const [
        _LegendItem(color: _calendarCoral, label: 'Exam'),
        _LegendItem(color: _calendarAmber, label: 'Deadline'),
        _LegendItem(color: _calendarGreen, label: 'Study session'),
        _LegendItem(color: _calendarIndigo, label: 'Personal'),
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: appScreenMuted, fontSize: 11)),
    ],
  );
}

class _Agenda extends StatelessWidget {
  const _Agenda({
    required this.date,
    required this.events,
    required this.onAdd,
    required this.onDelete,
  });

  final DateTime date;
  final List<StudentCalendarEvent> events;
  final VoidCallback onAdd;
  final ValueChanged<StudentCalendarEvent> onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: appScreenSurface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: appScreenBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED DAY',
                    style: TextStyle(
                      color: _calendarCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_weekdays[date.weekday % 7]}, ${_months[date.month - 1]} ${date.day}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Add event on selected day',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26),
            decoration: BoxDecoration(
              color: appScreenSurfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined, color: appScreenMuted),
                const SizedBox(height: 7),
                Text(
                  'No events on this day.',
                  style: TextStyle(color: appScreenMuted),
                ),
              ],
            ),
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _AgendaCard(event: event, onDelete: () => onDelete(event)),
            ),
          ),
      ],
    ),
  );
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({required this.event, required this.onDelete});

  final StudentCalendarEvent event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(event.type);
    return Opacity(
      opacity: event.completed ? 0.62 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sourceLabel(event),
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_time(event.startAt)}–${_time(event.endAt)}',
                    style: TextStyle(color: appScreenMuted, fontSize: 12),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      style: TextStyle(
                        color: appScreenMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (event.completed) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'COMPLETED',
                      style: TextStyle(
                        color: _calendarGreen,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (event.source != StudentCalendarEventSource.academic)
              IconButton(
                tooltip: 'Delete ${event.title}',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: _calendarCoral,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddCalendarEventDialog extends StatefulWidget {
  const _AddCalendarEventDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_AddCalendarEventDialog> createState() =>
      _AddCalendarEventDialogState();
}

class _AddCalendarEventDialogState extends State<_AddCalendarEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  int _duration = 60;
  StudentCalendarEventType _type = StudentCalendarEventType.studySession;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    Navigator.of(context).pop(
      StudentCalendarEvent(
        id: 'student:${DateTime.now().microsecondsSinceEpoch}',
        title: _title.text.trim(),
        description: _description.text.trim(),
        startAt: start,
        endAt: start.add(Duration(minutes: _duration)),
        type: _type,
        source: StudentCalendarEventSource.student,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add calendar event'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('calendar-event-title'),
                controller: _title,
                maxLength: 100,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Event title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an event title.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                maxLength: 400,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (value != null) setState(() => _date = value);
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(
                        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showTimePicker(
                          context: context,
                          initialTime: _time,
                        );
                        if (value != null) setState(() => _time = value);
                      },
                      icon: const Icon(Icons.schedule_outlined, size: 17),
                      label: Text(_time.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 90, child: Text('1.5 hours')),
                  DropdownMenuItem(value: 120, child: Text('2 hours')),
                ],
                onChanged: (value) => setState(() => _duration = value ?? 60),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<StudentCalendarEventType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Event type'),
                items: const [
                  DropdownMenuItem(
                    value: StudentCalendarEventType.studySession,
                    child: Text('Study session'),
                  ),
                  DropdownMenuItem(
                    value: StudentCalendarEventType.personal,
                    child: Text('Personal event'),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _type = value ?? StudentCalendarEventType.studySession,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Add to calendar')),
    ],
  );
}

class _CalendarError extends StatelessWidget {
  const _CalendarError({required this.message, required this.onRetry});

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

Color _eventColor(StudentCalendarEventType type) => switch (type) {
  StudentCalendarEventType.exam => _calendarCoral,
  StudentCalendarEventType.assignment => _calendarAmber,
  StudentCalendarEventType.studySession => _calendarGreen,
  StudentCalendarEventType.personal => _calendarIndigo,
};

String _sourceLabel(StudentCalendarEvent event) {
  if (event.source == StudentCalendarEventSource.ai) {
    return 'AI SCHEDULED · URGENT';
  }
  if (event.source == StudentCalendarEventSource.academic) {
    return 'ACADEMIC CALENDAR';
  }
  return 'MY EVENT';
}

String _time(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}
