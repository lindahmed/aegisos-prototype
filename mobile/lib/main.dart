import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appLanguageController.load();
  runApp(const UniTrackApp());
}

class UniTrackApp extends StatelessWidget {
  const UniTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLanguageController,
      builder: (context, locale, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, themeMode, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'UNI Track',
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const LoginScreen(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final seeded = ColorScheme.fromSeed(
      seedColor: uniTrackBlue,
      brightness: brightness,
      surface: dark ? const Color(0xFF151C2F) : Colors.white,
    );
    final colors = seeded.copyWith(
      primary: dark ? const Color(0xFF7CB8FF) : uniTrackBlue,
      secondary: dark ? const Color(0xFF60A5FA) : uniTrackBlueMid,
      tertiary: dark ? const Color(0xFF67D4FF) : uniTrackSky,
      surfaceContainerHighest: dark
          ? const Color(0xFF202D43)
          : const Color(0xFFF0F4F9),
      outlineVariant: dark ? const Color(0xFF33435C) : const Color(0xFFDCE4EE),
    );
    final baseTypography = dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    return ThemeData(
      colorScheme: colors,
      brightness: brightness,
      fontFamily: 'Roboto',
      textTheme: baseTypography
          .apply(fontFamily: 'Roboto')
          .copyWith(
            headlineSmall: baseTypography.headlineSmall?.copyWith(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
            titleLarge: baseTypography.titleLarge?.copyWith(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
              letterSpacing: -0.25,
            ),
            titleMedium: baseTypography.titleMedium?.copyWith(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
            ),
            bodyMedium: baseTypography.bodyMedium?.copyWith(
              fontFamily: 'Roboto',
              height: 1.4,
            ),
          ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF071421)
          : const Color(0xFFF5F9FF),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF091221) : Colors.white,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontFamily: 'Roboto',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF202A42) : const Color(0xFFF4F7FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          side: BorderSide(color: colors.outlineVariant),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainerHighest,
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        labelStyle: TextStyle(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 4,
        shape: const StadiumBorder(),
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primary.withValues(alpha: 0.12),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF26364D)
            : const Color(0xFF14243E),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      useMaterial3: true,
    );
  }
}
