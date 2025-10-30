import 'dart:async'; // For StreamSubscription
import 'dart:typed_data'; // <-- THIS IS CRITICAL for Uint8List
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // The "Ears"
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart'; // The "Mouth"
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'network_state.dart'; // The import is correct

class LocalAlertsScreen extends StatefulWidget {
  const LocalAlertsScreen({Key? key}) : super(key: key);

  @override
  State<LocalAlertsScreen> createState() => _LocalAlertsScreenState();
}

class Alert {
  final String text;
  final DateTime timestamp;
  Alert({required this.text, required this.timestamp});
}

class _LocalAlertsScreenState extends State<LocalAlertsScreen> {
  bool _permissionsGranted = false;
  String _permissionStatus = "Initializing...";
  bool _canOpenSettings = false;

  // --- THIS IS THE "EARS" SECRET CODE ---
  // We use this for *reading* packets
  final int _companyId = 0x1234;
  // --- END EARS ---

  // --- THIS IS THE "MOUTH" SECRET CODE ---
  // We put this *inside* the data we send
  final List<int> _companyIdBytes = [0x12, 0x34]; // e.g., 2 bytes for our ID
  // --- END MOUTH ---

  final Set<String> _seenPacketIds = {};
  final List<Alert> _receivedAlerts = [];

  bool _isBroadcasting = false;
  final Uuid _uuid = Uuid();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    if (_isBroadcasting) {
      _peripheral.stop();
    }
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    if (!await FlutterBluePlus.isAvailable) {
      if (mounted)
        setState(() =>
            _permissionStatus = "Bluetooth not supported on this device.");
      return;
    }

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        if (state == BluetoothAdapterState.on) {
          _requestPermissions();
        } else {
          setState(() {
            _permissionsGranted = false;
            _permissionStatus = "Bluetooth is off. Please turn it on.";
          });
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    bool allGranted = true;
    String statusMessage = "All permissions granted. Scanning...";
    bool canOpenSettings = false;

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          statusMessage =
              "Permissions permanently denied. Please enable in settings.";
          canOpenSettings = true;
        } else {
          statusMessage = "Permissions denied. App cannot function.";
        }
      }
    });

    if (mounted) {
      setState(() {
        _permissionsGranted = allGranted;
        _permissionStatus = statusMessage;
        _canOpenSettings = canOpenSettings;
      });
    }

    if (allGranted) {
      startScanning();
    }
  }

  Future<void> startScanning() async {
    if (FlutterBluePlus.isScanningNow) return;

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final now = DateTime.now();
      for (ScanResult r in results) {
        // --- THIS IS THE CORRECT "EARS" CODE ---
        // We look for the Company ID in the 'manufacturerData' map
        if (r.advertisementData.manufacturerData.containsKey(_companyId)) {
          // This packet is for us! Get the data.
          List<int> data = r.advertisementData.manufacturerData[_companyId]!;
          // --- END "EARS" FIX ---

          if (data.isEmpty) continue;

          // Our packet structure (from the "Mouth" code):
          // Byte 0: Type (0x01 = SOS)
          // Byte 1+: Packet ID
          int type = data[0];
          String packetId = String.fromCharCodes(data.sublist(1));

          if (type == 0x01 && !_seenPacketIds.contains(packetId)) {
            if (mounted) {
              setState(() {
                _seenPacketIds.add(packetId);
                _receivedAlerts.insert(
                    0,
                    Alert(
                      text: "SOS Received! ID: ${packetId.substring(0, 6)}...",
                      timestamp: now,
                    ));
              });
            }
          }
        }
      }
    });

    await FlutterBluePlus.startScan();
  }

  // This is the background hardware function
  Future<void> broadcastSOS() async {
    await FlutterBluePlus.stopScan();

    String packetId = _uuid.v4();
    List<int> typeBytes = [0x01]; // 0x01 = SOS code
    List<int> idBytes = packetId.codeUnits;

    // --- THIS IS THE CORRECT "MOUTH" CODE ---
    // 1. Create our data list
    List<int> finalPacket = [
      ...typeBytes,
      ...idBytes,
    ];

    // 2. Convert that list to the Uint8List the package needs
    Uint8List dataAsUint8List = Uint8List.fromList(finalPacket);

    // 3. Pass that SINGLE Uint8List to manufacturerData,
    //    and our Company ID to manufacturerId.
    final advData = AdvertiseData(
      includeDeviceName: false,
      manufacturerId: _companyId, // <-- This is the ID
      manufacturerData: dataAsUint8List, // <-- This is the data (Uint8List)
    );
    // --- END "MOUTH" FIX ---

    try {
      await _peripheral.start(advertiseData: advData);
    } catch (e) {
      print("Error starting advertising: $e");
      rethrow;
    }

    await Future.delayed(Duration(seconds: 10));

    try {
      await _peripheral.stop();
    } catch (e) {
      print("Error stopping advertising: $e");
    }

    await startScanning();
  }

  Future<void> _onSosPressed() async {
    if (_isBroadcasting) return;

    final now = DateTime.now();

    setState(() {
      _isBroadcasting = true;
      _receivedAlerts.insert(
          0,
          Alert(
            text: "MY SOS: Broadcasting now...",
            timestamp: now,
          ));
    });

    final networkState = Provider.of<NetworkState>(context, listen: false);
    networkState.iJustSentSOS();

    try {
      await broadcastSOS();
    } catch (e) {
      print("Error during broadcast: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error broadcasting: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBroadcasting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Local Alerts (Helper / Help Me)"),
        backgroundColor: Colors.blue[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _isBroadcasting ? Colors.grey : Colors.red,
                  minimumSize: Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              onPressed: _permissionsGranted ? _onSosPressed : null,
              child: Text(
                _isBroadcasting ? "Broadcasting SOS..." : "BROADCAST SOS",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
            SizedBox(height: 10),
            Text(
              _permissionStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _permissionsGranted ? Colors.green : Colors.yellow),
            ),
            if (_canOpenSettings)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: OutlinedButton(
                  child: Text("Open App Settings"),
                  onPressed: openAppSettings,
                ),
              ),
            SizedBox(height: 20),
            Divider(),
            Text("Received Alerts",
                style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 10),
            Expanded(
              child: _receivedAlerts.isEmpty
                  ? Center(
                      child: Text("Listening... No alerts received yet."),
                    )
                  : ListView.builder(
                      itemCount: _receivedAlerts.length,
                      itemBuilder: (context, index) {
                        final alert = _receivedAlerts[index];
                        final alertText = alert.text;
                        final isSelfTest = alertText.startsWith("MY SOS");

                        return Card(
                          color: isSelfTest ? Colors.blue[900] : null,
                          child: ListTile(
                            leading: Icon(
                              isSelfTest ? Icons.upload : Icons.warning,
                              color: isSelfTest ? Colors.white : Colors.red,
                            ),
                            title: Text(alertText),
                            subtitle: Text(
                                "Received: ${alert.timestamp.toIso8601String().substring(11, 19)}"),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
