import 'package:emergency_mesh_app/home_screen.dart'; // <-- FIXED!
import 'package:emergency_mesh_app/network_state.dart'; // <-- FIXED!
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    // This "Provider" makes the NetworkState available to all screens
    ChangeNotifierProvider(
      create: (context) => NetworkState(),
      child: const MyApp(),
    ),
  );
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
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue[300]!,
          secondary: Colors.green[300]!,
        ),
      ),
      home: const HomeScreen(), // This points to your new 2-tab screen
      debugShowCheckedModeBanner: false,
    );
  }
}
