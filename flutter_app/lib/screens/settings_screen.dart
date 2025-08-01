import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3ECDE),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'SFProDisplay',
            fontSize: 20,
            color: Colors.black,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: const Center(
        child: Text(
          'Settings page content goes here',
          style: TextStyle(
            fontFamily: 'SFProDisplay',
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
