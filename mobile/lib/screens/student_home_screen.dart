import 'package:flutter/material.dart';

import '../models/student.dart';
import '../services/api_service.dart';
import 'advisor_screen.dart';
import 'login_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({required this.student, super.key});

  final Student student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My academic profile'),
        actions: [
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
