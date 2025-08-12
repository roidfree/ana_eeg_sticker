// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ble_service.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';
import 'sidebar_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final BLEService _bleService = BLEService();

  late AnimationController _outerController,
      _middleController,
      _innerController;
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
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _middleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _innerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
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
    // 1. Request BLE permissions
    final perms = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (perms.values.any((p) => !p.isGranted)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Bluetooth permissions required"),
          action: SnackBarAction(
            label: "Settings",
            onPressed: openAppSettings,
          ),
        ),
      );
      return;
    }

    // 2. Ensure Bluetooth is ON
    if (await FlutterBluePlus.adapterState.first !=
        BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable Bluetooth manually.")),
        );
        return;
      }
    }

    // 3. Scan
    final devices = await _bleService.scan(timeout: const Duration(seconds: 5));
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No BLE devices found.")),
      );
      return;
    }

    // 4. Let user pick one
    final pick = await showDialog<ScanResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Bluetooth Device"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: devices.map((r) {
              final name = r.device.name.isNotEmpty
                  ? r.device.name
                  : r.advertisementData.localName.isNotEmpty
                      ? r.advertisementData.localName
                      : r.device.id.id;
              return ListTile(
                title: Text(name),
                subtitle: Text(r.device.id.id),
                onTap: () => Navigator.pop(context, r),
              );
            }).toList(),
          ),
        ),
      ),
    );
    if (pick == null) return;

    // 5. Connect
    final ok = await _bleService.connectDevice(pick.device);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Connection failed.")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Connected! Streaming…")),
    );

    // 6. Navigate
    _navigateTo(AnalyticsScreen(eegStream: _bleService.eegStream));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ─── Header ─────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PopupMenuButton(
                      icon: Image.asset('assets/sidebar.png',
                          height: 24, width: 30),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          child: const Text("Menu"),
                          onTap: () => _navigateTo(const SidebarScreen()),
                        )
                      ],
                    ),
                    const Text(
                      'ANA Home Page',
                      style: TextStyle(
                          fontFamily: 'SFProDisplay',
                          fontSize: 20,
                          color: Colors.black),
                    ),
                    GestureDetector(
                      onTap: () => _navigateTo(const SettingsScreen()),
                      child: Image.asset('assets/Settings.png',
                          height: 30),
                    ),
                  ],
                ),
              ),

              // ─── Start Button ───────────────────────────
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.1).animate(
                          CurvedAnimation(
                              parent: _outerController,
                              curve: Curves.easeInOut)),
                      child: SvgPicture.asset('assets/circle_outer.svg',
                          height: 340),
                    ),
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.15).animate(
                          CurvedAnimation(
                              parent: _middleController,
                              curve: Curves.easeInOut)),
                      child: SvgPicture.asset('assets/circle_middle.svg',
                          height: 300),
                    ),
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.2).animate(
                          CurvedAnimation(
                              parent: _innerController,
                              curve: Curves.easeInOut)),
                      child: SvgPicture.asset('assets/circle_inner.svg',
                          height: 260),
                    ),
                    GestureDetector(
                      onTap: _startSession,
                      child:
                          SvgPicture.asset('assets/start_text.svg',
                              height: 80),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Weekly Stats ──────────────────────────
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
                  itemBuilder: (ctx, i) {
                    final stat = stats[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      child: Container(
                        decoration: BoxDecoration(
                            color: const Color(0xFFBD9F72),
                            borderRadius: BorderRadius.circular(40)),
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            stat['value']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'SFProDisplay',
                                fontSize: 22,
                                color: Colors.black),
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
