import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'analytics_screen.dart';
import 'meditation_screen.dart';
import 'timings.dart';
import 'settings_screen.dart';
import 'sidebar_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _outerController;
  late AnimationController _middleController;
  late AnimationController _innerController;

  final PageController _pageController = PageController();

  final List<Map<String, String>> stats = [
    {'title': 'Focus', 'value': '🎯 Average 76% during sessions'},
    {'title': 'Stress', 'value': '😣 6.2 / 10'},
    {'title': 'Mood', 'value': '🙂 Mostly positive'},
  ];

  @override
  void initState() {
    super.initState();

    _outerController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);

    _middleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _innerController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _outerController.dispose();
    _middleController.dispose();
    _innerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _startSession() async {
    print('Start session tapped!');

    // Request permissions
    final bluetoothPermission = await Permission.bluetoothConnect.request();
    final locationPermission = await Permission.locationWhenInUse.request();

    if (bluetoothPermission.isGranted && locationPermission.isGranted) {
      final isOn = await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

      if (!isOn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable Bluetooth manually.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bluetooth is already ON!")),
        );
        // You can also trigger device scanning or navigation here
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth or location permission not granted.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                    GestureDetector(
                      onTap: () => _navigateTo(const SettingsScreen()),
                      child: Image.asset('assets/Settings.png', height: 30),
                    ),
                  ],
                ),
              ),

              // Circular Animated "Start Session" Button
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.1).animate(
                        CurvedAnimation(parent: _outerController, curve: Curves.easeInOut),
                      ),
                      child: SvgPicture.asset('assets/circle_outer.svg', height: 340),
                    ),
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.15).animate(
                        CurvedAnimation(parent: _middleController, curve: Curves.easeInOut),
                      ),
                      child: SvgPicture.asset('assets/circle_middle.svg', height: 300),
                    ),
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.2).animate(
                        CurvedAnimation(parent: _innerController, curve: Curves.easeInOut),
                      ),
                      child: SvgPicture.asset('assets/circle_inner.svg', height: 260),
                    ),
                    GestureDetector(
                      onTap: _startSession,
                      child: SvgPicture.asset('assets/start_text.svg', height: 80),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'So far this week...',
                    style: TextStyle(
                      fontFamily: 'SFProDisplay',
                      fontSize: 22,
                      letterSpacing: -1,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 300,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: stats.length,
                  itemBuilder: (context, index) {
                    final stat = stats[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFBD9F72),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            stat['value']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'SFProDisplay',
                              fontSize: 22,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
