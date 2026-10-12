import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'student_home_screen.dart';

const _rememberStudentKey = 'remember_student_id';
const _rememberStudentEnabledKey = 'remember_student_enabled';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final ApiService apiService = ApiService();

  late final AnimationController _introController;
  late final AnimationController _loginController;
  bool _logoPrecacheRequested = false;
  bool _showLogin = false;
  bool isLoading = false;
  bool isTakingLonger = false;
  bool obscurePassword = true;
  bool rememberMe = false;
  String? errorMessage;
  Timer? slowLoginTimer;

  @override
  void initState() {
    super.initState();
    _introController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3800),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _showLogin = true);
            _loginController.forward();
          }
        });
    _loginController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _introController.forward();
    unawaited(_loadRememberedStudent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoPrecacheRequested) return;
    _logoPrecacheRequested = true;
    unawaited(
      precacheImage(
        const AssetImage('assets/branding/uni_track_mark.png'),
        context,
      ),
    );
  }

  Future<void> _loadRememberedStudent() async {
    final preferences = await SharedPreferences.getInstance();
    final enabled = preferences.getBool(_rememberStudentEnabledKey) ?? false;
    if (!mounted || !enabled) return;
    setState(() {
      rememberMe = true;
      studentIdController.text =
          preferences.getString(_rememberStudentKey) ?? '';
    });
  }

  Future<void> _saveRememberedStudent(String studentId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_rememberStudentEnabledKey, rememberMe);
    if (rememberMe) {
      await preferences.setString(_rememberStudentKey, studentId);
    } else {
      await preferences.remove(_rememberStudentKey);
    }
  }

  Future<void> login() async {
    FocusScope.of(context).unfocus();
    final studentId = studentIdController.text.trim();
    if (studentId.isEmpty) {
      setState(() => errorMessage = 'Enter your student ID.');
      return;
    }
    final password = passwordController.text;
    if (password.isEmpty) {
      setState(() => errorMessage = 'Enter your password.');
      return;
    }

    setState(() {
      isLoading = true;
      isTakingLonger = false;
      errorMessage = null;
    });
    slowLoginTimer?.cancel();
    slowLoginTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && isLoading) setState(() => isTakingLonger = true);
    });

    try {
      final student = await apiService.loginStudent(studentId, password);
      await _saveRememberedStudent(studentId);
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
      slowLoginTimer?.cancel();
      if (mounted) {
        setState(() {
          isLoading = false;
          isTakingLonger = false;
        });
      }
    }
  }

  @override
  void dispose() {
    slowLoginTimer?.cancel();
    _introController.dispose();
    _loginController.dispose();
    studentIdController.dispose();
    passwordController.dispose();
    apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: _showLogin
          ? _LoginExperience(
              key: const ValueKey('login-experience'),
              animation: _loginController,
              studentIdController: studentIdController,
              passwordController: passwordController,
              obscurePassword: obscurePassword,
              rememberMe: rememberMe,
              isLoading: isLoading,
              isTakingLonger: isTakingLonger,
              errorMessage: errorMessage,
              onTogglePassword: () =>
                  setState(() => obscurePassword = !obscurePassword),
              onRememberChanged: (value) =>
                  setState(() => rememberMe = value ?? false),
              onLogin: login,
            )
          : _IntroSplash(
              key: const ValueKey('intro-splash'),
              controller: _introController,
            ),
    ),
  );
}

class _IntroSplash extends StatelessWidget {
  const _IntroSplash({required this.controller, super.key});

  final AnimationController controller;

  static double _phase(double value, double start, double end, Curve curve) {
    final normalized = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF071421) : const Color(0xFFFBFDFF);
    return ColoredBox(
      color: background,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final value = controller.value;
          final mark = _phase(value, 0.04, 0.68, Curves.easeInOutCubic);
          final brand = _phase(value, 0.67, 0.83, Curves.easeOutCubic);
          final tagline = _phase(value, 0.81, 0.92, Curves.easeOutCubic);
          final outro = _phase(value, 0.94, 1, Curves.easeInCubic);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF071421), Color(0xFF0A1C2C)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF3F9FD)],
              ),
            ),
            child: Center(
              child: Opacity(
                opacity: 1 - outro,
                child: Transform.translate(
                  offset: Offset(0, -18 * outro),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BuildingLogo(progress: mark),
                      const SizedBox(height: 26),
                      Opacity(
                        opacity: brand,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - brand)),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'UNI ',
                                  style: TextStyle(
                                    color: dark
                                        ? const Color(0xFFEAF4FF)
                                        : uniTrackNavy,
                                  ),
                                ),
                                const TextSpan(
                                  text: 'TRACK',
                                  style: TextStyle(color: uniTrackBlue),
                                ),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: tagline,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - tagline)),
                          child: AppText(
                            'Guide. Track. Evolve.',
                            style: TextStyle(
                              color: dark
                                  ? const Color(0xFFAEC7DD)
                                  : const Color(0xFF70839A),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BuildingLogo extends StatelessWidget {
  const _BuildingLogo({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final uProgress = _piecePhase(value, 0, 0.7);
    final capProgress = _piecePhase(value, 0.74, 1);
    return SizedBox(
      width: 176,
      height: 176,
      child: Semantics(
        image: true,
        label: 'UNI Track logo',
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(
              clipper: _UDrawClipper(uProgress),
              child: Image.asset(
                'assets/branding/uni_track_mark.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            ClipPath(
              clipper: const _CapRegionClipper(),
              child: Opacity(
                opacity: capProgress,
                child: Transform.translate(
                  offset: Offset(0, -24 * (1 - capProgress)),
                  child: Image.asset(
                    'assets/branding/uni_track_mark.png',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _piecePhase(double value, double start, double end) {
    final normalized = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(normalized);
  }
}

class _UDrawClipper extends CustomClipper<Path> {
  const _UDrawClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final centerLine = Path()
      ..moveTo(size.width * 0.36, size.height * 0.42)
      ..lineTo(size.width * 0.36, size.height * 0.66)
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.88,
        size.width * 0.48,
        size.height * 0.94,
        size.width * 0.63,
        size.height * 0.91,
      )
      ..cubicTo(
        size.width * 0.79,
        size.height * 0.88,
        size.width * 0.82,
        size.height * 0.74,
        size.width * 0.82,
        size.height * 0.58,
      )
      ..lineTo(size.width * 0.82, size.height * 0.31);
    final metric = centerLine.computeMetrics().first;
    final revealedLength = metric.length * progress.clamp(0.0, 1.0);
    final reveal = Path();
    final radius = size.width * 0.09;
    for (var distance = 0.0; distance <= revealedLength; distance += 1.2) {
      final point = metric.getTangentForOffset(distance)?.position;
      if (point != null) {
        reveal.addOval(Rect.fromCircle(center: point, radius: radius));
      }
    }

    final uRegion = Path()
      ..addRect(Rect.fromLTRB(0, size.height * 0.41, size.width, size.height))
      ..addRect(
        Rect.fromLTRB(
          size.width * 0.72,
          size.height * 0.28,
          size.width,
          size.height,
        ),
      );
    return Path.combine(PathOperation.intersect, reveal, uRegion);
  }

  @override
  bool shouldReclip(covariant _UDrawClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _CapRegionClipper extends CustomClipper<Path> {
  const _CapRegionClipper();

  @override
  Path getClip(Size size) => Path()
    ..addRect(Rect.fromLTRB(0, 0, size.width * 0.73, size.height * 0.5))
    ..addRect(
      Rect.fromLTRB(
        size.width * 0.07,
        size.height * 0.34,
        size.width * 0.31,
        size.height * 0.66,
      ),
    );

  @override
  bool shouldReclip(covariant _CapRegionClipper oldClipper) => false;
}

class _LoginExperience extends StatelessWidget {
  const _LoginExperience({
    required this.animation,
    required this.studentIdController,
    required this.passwordController,
    required this.obscurePassword,
    required this.rememberMe,
    required this.isLoading,
    required this.isTakingLonger,
    required this.errorMessage,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onLogin,
    super.key,
  });

  final AnimationController animation;
  final TextEditingController studentIdController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool rememberMe;
  final bool isLoading;
  final bool isTakingLonger;
  final String? errorMessage;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool?> onRememberChanged;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF121927) : Colors.white;
    final headerColor = dark ? const Color(0xFF123765) : uniTrackBlue;
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: cardColor,
        systemNavigationBarDividerColor: cardColor,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ColoredBox(
        color: cardColor,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Continue the blue behind the rounded top corners of the white
              // sheet so only the sheet itself is white at the transition.
              height: topInset + 334,
              child: ColoredBox(color: headerColor),
            ),
            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        _LoginHero(animation: animation),
                        _StaggeredReveal(
                          animation: animation,
                          start: 0.1,
                          end: 0.42,
                          child: Container(
                            width: double.infinity,
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 300,
                            ),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(34),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: uniTrackNavy.withValues(alpha: 0.2),
                                  blurRadius: 28,
                                  offset: const Offset(0, -8),
                                ),
                              ],
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 480,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    18,
                                    22,
                                    26,
                                  ),
                                  child: AutofillGroup(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _StaggeredReveal(
                                          animation: animation,
                                          start: 0.2,
                                          end: 0.52,
                                          child: TextField(
                                            key: const Key('login-student-id'),
                                            controller: studentIdController,
                                            keyboardType: TextInputType.text,
                                            textInputAction:
                                                TextInputAction.next,
                                            autofillHints: const [
                                              AutofillHints.username,
                                            ],
                                            decoration: _fieldDecoration(
                                              colors: colors,
                                              dark: dark,
                                              label: tr('Student ID'),
                                              hint: '231003445',
                                              icon: Icons.badge_outlined,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        _StaggeredReveal(
                                          animation: animation,
                                          start: 0.3,
                                          end: 0.62,
                                          child: TextField(
                                            key: const Key('login-password'),
                                            controller: passwordController,
                                            obscureText: obscurePassword,
                                            textInputAction:
                                                TextInputAction.done,
                                            autofillHints: const [
                                              AutofillHints.password,
                                            ],
                                            onSubmitted: isLoading
                                                ? null
                                                : (_) => onLogin(),
                                            decoration: _fieldDecoration(
                                              colors: colors,
                                              dark: dark,
                                              label: tr('Password'),
                                              icon: Icons.lock_outline,
                                              suffixIcon: IconButton(
                                                tooltip: obscurePassword
                                                    ? tr('Show password')
                                                    : tr('Hide password'),
                                                onPressed: onTogglePassword,
                                                icon: Icon(
                                                  obscurePassword
                                                      ? Icons
                                                            .visibility_outlined
                                                      : Icons
                                                            .visibility_off_outlined,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _StaggeredReveal(
                                          animation: animation,
                                          start: 0.4,
                                          end: 0.72,
                                          child: InkWell(
                                            onTap: isLoading
                                                ? null
                                                : () => onRememberChanged(
                                                    !rememberMe,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  key: const Key(
                                                    'login-remember-me',
                                                  ),
                                                  value: rememberMe,
                                                  onChanged: isLoading
                                                      ? null
                                                      : onRememberChanged,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                Expanded(
                                                  child: AppText(
                                                    'Remember me',
                                                    style: TextStyle(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                AppText(
                                                  'Student ID only',
                                                  style: TextStyle(
                                                    color: colors.primary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (errorMessage != null) ...[
                                          const SizedBox(height: 10),
                                          Semantics(
                                            liveRegion: true,
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: colors.errorContainer
                                                    .withValues(alpha: 0.58),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: AppText(
                                                errorMessage!,
                                                style: TextStyle(
                                                  color:
                                                      colors.onErrorContainer,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        _StaggeredReveal(
                                          animation: animation,
                                          start: 0.5,
                                          end: 0.86,
                                          child: _GradientLoginButton(
                                            isLoading: isLoading,
                                            onPressed: onLogin,
                                          ),
                                        ),
                                        if (isTakingLonger) ...[
                                          const SizedBox(height: 12),
                                          AppText(
                                            'Still signing you in securely. The university service is taking longer than usual…',
                                            key: const Key(
                                              'login-slow-message',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: colors.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 22),
                                        _StaggeredReveal(
                                          animation: animation,
                                          start: 0.66,
                                          end: 1,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.verified_user_outlined,
                                                size: 17,
                                                color: colors.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: AppText(
                                                  'Secure connection to UNI Track',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required ColorScheme colors,
    required bool dark,
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: dark ? const Color(0xFF1B2B40) : const Color(0xFFF1F6FF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: 0.4),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: colors.primary, width: 1.7),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: colors.error),
    ),
  );
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: Stack(
      children: [
        const Positioned(top: 8, right: 14, child: ThemeModeToggleButton()),
        Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StaggeredReveal(
                  animation: animation,
                  start: 0,
                  end: 0.3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Image.asset(
                          'assets/branding/uni_track_mark.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'UNI '),
                            TextSpan(
                              text: 'TRACK',
                              style: TextStyle(color: uniTrackSky),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _StaggeredReveal(
                  animation: animation,
                  start: 0.06,
                  end: 0.38,
                  child: const AppText(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                _StaggeredReveal(
                  animation: animation,
                  start: 0.12,
                  end: 0.44,
                  child: AppText(
                    'Guide. Track. Evolve.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _GradientLoginButton extends StatelessWidget {
  const _GradientLoginButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [uniTrackNavy, uniTrackBlue, uniTrackSky],
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: uniTrackBlue.withValues(alpha: 0.24),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: SizedBox(
      height: 56,
      child: FilledButton.icon(
        key: const Key('login-submit'),
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
            : const Icon(Icons.arrow_forward_rounded),
        label: const AppText(
          'Sign in',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );
}

class _StaggeredReveal extends StatelessWidget {
  const _StaggeredReveal({
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final normalized = ((animation.value - start) / (end - start)).clamp(
        0.0,
        1.0,
      );
      final value = Curves.easeOutCubic.transform(normalized);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - value)),
          child: child,
        ),
      );
    },
  );
}
