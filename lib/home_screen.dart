import 'package:emergency_mesh_app/local_alerts_screen.dart';
import 'package:emergency_mesh_app/network_view_screen.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    LocalAlertsScreen(), // Your tab
    NetworkViewScreen(), // Teammate 2's tab
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.satellite_alt),
            label: "Local Alerts",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub),
            label: "Network View",
          ),
        ],
      ),
    );
  }
}
