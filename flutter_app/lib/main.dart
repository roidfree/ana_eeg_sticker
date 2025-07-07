import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';


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
        fontFamily: 'KronaOne',
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 120,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'ANA',
                    style: TextStyle(
                      fontSize: 60,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Know yourself. Change your world.',
                    style: TextStyle(
                      fontSize: 20,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                height: 63,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HomePage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBD9F72),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Log in',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Welcome to the ANA Home Page')),
    );
  }
}
