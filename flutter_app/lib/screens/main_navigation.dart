// lib/screens/main_navigation.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'analytics_screen.dart';
import 'meditation_screen.dart';
import 'timings.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    AnalyticsScreen(),
    MeditationScreen(),
    TimingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      body: SafeArea(child: _pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        backgroundColor: const Color(0xFFF3ECDE),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Image.asset('assets/Home.png', height: 28),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Image.asset('assets/analytics.png', height: 28),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Image.asset('assets/lotus_widget.png', height: 50, width: 50),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Image.asset('assets/Clock.png', height: 28),
            label: '',
          ),
        ],
      ),
    );
  }
}
