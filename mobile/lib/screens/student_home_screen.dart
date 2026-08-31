import 'package:flutter/material.dart';

import '../models/student.dart';
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
