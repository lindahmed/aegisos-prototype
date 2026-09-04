import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'student_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController studentIdController = TextEditingController();
  final ApiService apiService = ApiService();

  bool isLoading = false;
  String? errorMessage;

  Future<void> login() async {
    FocusScope.of(context).unfocus();
    final studentId = studentIdController.text.trim();
    if (studentId.isEmpty) {
      setState(() => errorMessage = 'Enter your student ID.');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final student = await apiService.getStudent(studentId);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => StudentHomeScreen(student: student),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => errorMessage = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    studentIdController.dispose();
    apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brandInk = dark ? const Color(0xFFB8E5FF) : uniTrackNavy;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height - 72,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/branding/uni_track_mark.png',
                        width: 116,
                        height: 116,
                        fit: BoxFit.contain,
                        semanticLabel: 'UNI Track logo',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'UNI ',
                            style: TextStyle(color: brandInk),
                          ),
                          TextSpan(
                            text: 'TRACK',
                            style: TextStyle(color: uniTrackBlue),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Guide. Track. Evolve.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: brandInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF101D39)
                                .withValues(alpha: 0.05),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Student access',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Use the same ID as your university portal.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: studentIdController,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.username],
                            onSubmitted: isLoading ? null : (_) => login(),
                            decoration: InputDecoration(
                              labelText: 'Student ID',
                              hintText: 'STU001',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              filled: true,
                              fillColor: colors.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: isLoading ? null : login,
                              style: FilledButton.styleFrom(
                                backgroundColor: uniTrackBlue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                ),
                              ),
                              icon: isLoading
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward),
                              label: const Text(
                                'Sign in',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 17,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Secure connection to UNI Track',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'API: ${ApiService.defaultBaseUrl}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(top: 8, right: 8, child: ThemeModeToggleButton()),
          ],
        ),
      ),
    );
  }
}
