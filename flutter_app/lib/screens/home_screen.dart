import 'package:flutter/material.dart';
import 'settings_screen.dart';
import 'sidebar_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();

  final List<Map<String, String>> stats = [
    {'title': 'Focus', 'value': 'Focus \n\n\n 🎯 Average 76% during sessions'},
    {'title': 'Stress', 'value': 'Stress \n\n\n 😣 6.2 / 10'},
    {'title': 'Mood', 'value': 'Mood \n\n\n 🙂 Mostly positive'},
  ];

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Sidebar button with dropdown menu
                  PopupMenuButton(
                    icon: Image.asset('assets/sidebar.png', height: 24, width: 30),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text("Menu Option"),
                        onTap: () => _navigateTo(const SidebarScreen()),
                      ),
                    ],
                  ),
                  const Text(
                    'ANA Home Page',
                    style: TextStyle(
                      fontFamily: 'SFProDisplay',
                      fontSize: 20,
                      color: Colors.black,
                    ),
                  ),
                  // Settings button
                  GestureDetector(
                    onTap: () => _navigateTo(const SettingsScreen()),
                    child: Image.asset('assets/Settings.png', height: 30),
                  ),
                ],
              ),
            ),

            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'So far this week...',
                  style: TextStyle(
                    fontFamily: 'SFProDisplay',
                    fontSize: 20,
                    letterSpacing: -1,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            // Swipable cards
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: stats.length,
                itemBuilder: (context, index) {
                  final stat = stats[index];
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFBD9F72),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Center(
                        child: Text(
                          stat['value']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'SFProDisplay',
                            fontSize: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
