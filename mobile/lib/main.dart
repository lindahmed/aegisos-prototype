import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const AdvisorAIApp());
}

class AdvisorAIApp extends StatelessWidget {
  const AdvisorAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AegisOS Advisor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F7780),
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
