import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // <-- 1. We added this
import 'network_state.dart'; // <-- 2. And this

class NetworkViewScreen extends StatefulWidget {
  const NetworkViewScreen({Key? key}) : super(key: key);

  @override
  State<NetworkViewScreen> createState() => _NetworkViewScreenState();
}

class _NetworkViewScreenState extends State<NetworkViewScreen> {
  String _simulationStatus = "Waiting for signal...";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Network View (Fake Sim)"),
        backgroundColor: Colors.green[800],
      ),
      // --- 3. We wrap the body in a Consumer ---
      body: Consumer<NetworkState>(
        builder: (context, networkState, child) {
          // --- 4. This is the "magic" ---
          // If the state says a signal was just sent...
          if (networkState.justSent) {
            // ...update our text!
            // This is where your teammate will trigger his animation
            _simulationStatus = "SOS Signal Received! Playing animation...";
            print("NETWORK_VIEW: I heard the signal!");
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "THIS IS TEAMMATE 2'S SCREEN",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 40),
                  Text(
                    "Simulation Status:",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 10),
                  // --- 5. This text will now update! ---
                  Text(
                    _simulationStatus,
                    style: TextStyle(fontSize: 16, color: Colors.yellow),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
