import 'package:flutter/material.dart';

// This class is your entire integration.
class NetworkState with ChangeNotifier {
  // A "flag" for Teammate 2 to check.
  bool _justSent = false;
  bool get justSent => _justSent;

  // You call this. Teammate 2 listens for it.
  void iJustSentSOS() {
    print("NETWORK_STATE: SOS Sent!"); // For debugging
    _justSent = true;
    notifyListeners(); // This tells Teammate 2's screen to update
    _justSent = false; // Reset the flag immediately
  }
}
