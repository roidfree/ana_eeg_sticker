import 'package:flutter/material.dart';

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
                  Image.asset('assets/sidebar.png', height: 30),
                  const Text(
                    'ANA Home Page',
                    style: TextStyle(
                      fontFamily: 'KronaOne',
                      fontSize: 20,
                      color: Colors.black,
                    ),
                  ),
                  Image.asset('assets/Settings.png', height: 30),
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
                    fontFamily: 'KronaOne',
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
                            fontFamily: 'KronaOne',
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

            // Bottom Nav
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  navIcon('assets/Home.png'),
                  navIcon('assets/analytics.png'),
                  navIcon('assets/lotus_widget.png'),
                  navIcon('assets/Clock.png'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget navIcon(String assetPath) {
    return GestureDetector(
      onTap: () {
        // TODO: Handle nav routing here
      },
      child: Image.asset(assetPath, height: 36),
    );
  }
}
