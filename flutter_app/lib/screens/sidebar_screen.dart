import 'package:flutter/material.dart';

class SidebarScreen extends StatelessWidget {
  const SidebarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3ECDE),
        elevation: 0,
        title: const Text(
          'Menu',
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
          'Sidebar dropdown menu options go here.',
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
