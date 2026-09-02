import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_notification.dart';
import '../services/api_service.dart';
import 'advisor_screen.dart';
import 'login_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({
    required this.student,
    this.apiService,
    super.key,
  });

  final Student student;
  final ApiService? apiService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My academic profile'),
        actions: [
          _NotificationButton(
            studentId: student.studentId,
            apiService: apiService,
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      _initials(student.name),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    student.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(student.major),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoChip(
                        icon: Icons.badge_outlined,
                        label: student.studentId,
                      ),
                      _InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: 'Level ${student.year}',
                      ),
                      _InfoChip(
                        icon: Icons.trending_up,
                        label: student.gpa == null
                            ? 'GPA unavailable'
                            : 'GPA ${student.gpa!.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _AcademicProgress(studentId: student.studentId),
          const SizedBox(height: 24),
          Text(
            'Current courses',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          if (student.courses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No current courses were found.'),
              ),
            )
          else
            ...student.courses.map(
              (course) => Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(course),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('open-advisor'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdvisorScreen(student: student),
                ),
              );
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Ask Advisor AI'),
            ),
          ),
        ],
      ),
    );
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

class _NotificationButton extends StatefulWidget {
  const _NotificationButton({
    required this.studentId,
    this.apiService,
  });

  final String studentId;
  final ApiService? apiService;

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
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
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
    unawaited(_loadNotifications());
    _pollTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_loadNotifications()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_ownsApiService) _apiService.close();
    super.dispose();
  }

  Future<void> _loadNotifications({bool showError = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final notifications = await _apiService.getStudentNotifications(
        widget.studentId,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _openNotifications() async {
    if (_opening) return;
    _opening = true;
    await _loadNotifications(showError: true);
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
  late List<StudentNotification> _notifications;
  String? _error;
  bool _updating = false;

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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
            Expanded(
              child: _notifications.isEmpty
                  ? const Center(child: Text('You are all caught up.'))
                  : ListView.separated(
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
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
                              child: Icon(
                                notification.type == 'grade'
                                    ? Icons.school_outlined
                                    : Icons.event_outlined,
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
                              child: Text(
                                '${notification.body}\n${notification.timestamp}',
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
                                : () => _setRead(
                                      [notification.id],
                                      !notification.read,
                                    ),
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
}

class _AcademicProgress extends StatelessWidget {
  const _AcademicProgress({required this.studentId});
  final String studentId;
  Color _color(double h) => h >= 70 ? Colors.green : (h >= 60 ? Colors.amber : Colors.red);

  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService().getStudentAcademics(studentId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Card(child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()));
        final data = snapshot.data!;
        final courses = data["courses"] as List<dynamic>? ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Academic progress · Week " + data["current_week"].toString(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...courses.map((raw) {
            final course = raw as Map<String, dynamic>;
            final metrics = course["metrics"] as Map<String, dynamic>;
            final health = (metrics["course_health"] as num?)?.toDouble();
            final assessments = course["assessments"] as List<dynamic>? ?? const [];
            final marks = assessments.where((a) => a["mark"] != null).map((a) => a["name"].toString() + ": " + a["mark"].toString() + "/" + a["max_marks"].toString()).join(" · ");
            final color = _color(health ?? 0);
            return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(course["course_name"] as String, style: const TextStyle(fontWeight: FontWeight.bold))), if (health != null) Chip(label: Text(health.toStringAsFixed(1) + "%"), backgroundColor: color.withValues(alpha: 0.16), side: BorderSide(color: color))]),
              Text(marks.isEmpty ? "No marks posted yet" : marks),
            ])));
          }),
        ]);
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
