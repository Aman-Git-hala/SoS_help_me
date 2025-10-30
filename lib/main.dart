import 'package:emergency_mesh_app/local_alerts_screen.dart';
import 'package:flutter/material.dart';

void main() {
  // No more Provider. We just run the app.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Mesh',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF121212), // Darker background
        colorScheme: ColorScheme.dark(
          primary: Colors.blue[300]!,
          secondary: Colors.red[400]!, // SOS color
        ),
      ),
      // Point directly to your screen
      home: const LocalAlertsScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
