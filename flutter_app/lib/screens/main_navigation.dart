// lib/screens/main_navigation.dart

import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'analytics_screen.dart';
import 'meditation_screen.dart';
import 'timings.dart';
import '../services/ble_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  final BLEService _bleService = BLEService();

  late final List<Widget> _pages = [
    const HomeScreen(),
    AnalyticsScreen(eegStream: _bleService.eegStream),
    const MeditationScreen(),
    const TimingsScreen(),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFFF3ECDE),
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        iconSize: 28,
        items: [
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/Home.png',
              color: _selectedIndex == 0 ? Colors.black : Colors.grey,
              height: 28,
            ),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/analytics.png',
              color: _selectedIndex == 1 ? Colors.black : Colors.grey,
              height: 28,
            ),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/lotus_widget.png',
              color: _selectedIndex == 2 ? Colors.black : Colors.grey,
              height: 36,
            ),
            label: 'Meditate',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              'assets/Clock.png',
              color: _selectedIndex == 3 ? Colors.black : Colors.grey,
              height: 28,
            ),
            label: 'Timing',
          ),
        ],
      ),
    );
  }
}
