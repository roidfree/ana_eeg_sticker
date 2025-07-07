// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const ANAApp());
}

class ANAApp extends StatelessWidget {
  const ANAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ANA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3ECDE),
        fontFamily: 'SFProDisplay',
      ),
      home: const WelcomeScreen(),
    );
  }
}
