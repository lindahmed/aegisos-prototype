import 'dart:async';

import 'package:flutter/material.dart';

import '../models/student.dart';
import '../models/student_notification.dart';
import '../services/api_service.dart';
import 'advisor_screen.dart';
import 'login_screen.dart';
import 'results_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({required this.student, this.apiService, super.key});

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
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
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
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const Key('open-results'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.assessment_outlined),
              ),
              title: const Text(
                'Results',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'View live grades from the shared AAST portal database',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ResultsScreen(student: student, apiService: apiService),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Current courses',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
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
      const Duration(minutes: 1),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}
