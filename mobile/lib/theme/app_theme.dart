import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

bool get isDarkModeEnabled => appThemeMode.value == ThemeMode.dark;

Color get appScreenSurface =>
    isDarkModeEnabled ? const Color(0xFF131E31) : Colors.white;
Color get appScreenSurfaceRaised =>
    isDarkModeEnabled ? const Color(0xFF19263B) : const Color(0xFFF7F9FC);
Color get appScreenInk =>
    isDarkModeEnabled ? const Color(0xFFF4F7FC) : const Color(0xFF101D39);
Color get appScreenMuted =>
    isDarkModeEnabled ? const Color(0xFFA8B4C7) : const Color(0xFF667085);
Color get appScreenBorder =>
    isDarkModeEnabled ? const Color(0xFF2A3952) : const Color(0xFFDDE4EF);

void toggleAppTheme() {
  appThemeMode.value = appThemeMode.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
}

class ThemeModeToggleButton extends StatelessWidget {
  const ThemeModeToggleButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: appThemeMode,
    builder: (context, mode, _) {
      final dark = mode == ThemeMode.dark;
      return IconButton.filledTonal(
        key: const Key('theme-mode-toggle'),
        tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: toggleAppTheme,
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        icon: Icon(dark ? Icons.wb_sunny_rounded : Icons.nightlight_round),
      );
    },
  );
}
