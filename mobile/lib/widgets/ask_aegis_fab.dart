import 'package:flutter/material.dart';

import '../models/student.dart';
import '../screens/advisor_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AskAegisFab extends StatelessWidget {
  const AskAegisFab({required this.onPressed, this.mini = false, super.key});

  final VoidCallback onPressed;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      elevation: 7,
      shadowColor: colors.primary.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [uniTrackBlue, uniTrackSky]),
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: InkWell(
          key: const Key('ask-ai-button'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: mini ? 14 : 18,
              vertical: 13,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                if (!mini) ...[
                  const SizedBox(width: 9),
                  const AppText(
                    'Ask AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openAskAegis(
  BuildContext context, {
  required Student student,
  required ApiService apiService,
  required String prompt,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => AdvisorScreen(
      student: student,
      apiService: apiService,
      initialMessage: prompt,
    ),
  ),
);
