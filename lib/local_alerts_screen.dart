import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart';

// --- NEW DATA MODEL ---
// We now store the packet 'type' to know what alert it was
class Alert {
  final int type; // 0x01=SOS, 0x02=Medical, 0x03=Rescue
  final String packetId;
  final DateTime timestamp;
  final int rssi; // Signal Strength

  Alert({
    required this.type,
    required this.packetId,
    required this.timestamp,
    required this.rssi,
  });
}

// --- NEW HELPER CLASS ---
// This holds the "authentic" info for each alert type
class AlertType {
  final String title;
  final IconData icon;
  final Color color;
  final int packetCode; // The byte we send

  AlertType({
    required this.title,
    required this.icon,
    required this.color,
    required this.packetCode,
  });
}
// --- END NEW ---

class LocalAlertsScreen extends StatefulWidget {
  const LocalAlertsScreen({Key? key}) : super(key: key);

  @override
  State<LocalAlertsScreen> createState() => _LocalAlertsScreenState();
}

class _LocalAlertsScreenState extends State<LocalAlertsScreen> {
  bool _permissionsGranted = false;
  String _permissionStatus = "Initializing...";
  bool _canOpenSettings = false;

  final int _companyId = 0x1234;
  final Set<String> _seenPacketIds = {};
  final List<Alert> _receivedAlerts = []; // Now a List<Alert>

  bool _isBroadcasting = false;
  final Uuid _uuid = Uuid();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  // --- NEW: Map of our alert types ---
  final Map<int, AlertType> _alertTypes = {
    0x01: AlertType(
        title: "SOS / General",
        icon: Icons.warning_amber_rounded,
        color: Colors.red[400]!,
        packetCode: 0x01),
    0x02: AlertType(
        title: "Medical Aid",
        icon: Icons.medical_services,
        color: Colors.blue[300]!,
        packetCode: 0x02),
    0x03: AlertType(
        title: "Trapped / Rescue",
        icon: Icons.people_outline,
        color: Colors.orange[400]!,
        packetCode: 0x03),
  };
  // --- END NEW ---

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
        if (r.advertisementData.manufacturerData.containsKey(_companyId)) {
          List<int> data = r.advertisementData.manufacturerData[_companyId]!;

          // --- NEW: Packet decoding ---
          // Our new packet: [PacketType(1 byte)] + [UUID(string)]
          if (data.isEmpty) continue;

          int type = data[0]; // Get the type (0x01, 0x02, or 0x03)
          String packetId = String.fromCharCodes(data.sublist(1));

          // Check if we support this type and haven't seen it
          if (_alertTypes.containsKey(type) &&
              !_seenPacketIds.contains(packetId)) {
            if (mounted) {
              setState(() {
                _seenPacketIds.add(packetId);
                _receivedAlerts.insert(
                    0,
                    Alert(
                      type: type,
                      packetId: packetId,
                      timestamp: now,
                      rssi: r.rssi,
                    ));
              });
            }
          }
          // --- END NEW ---
        }
      }
    });

    await FlutterBluePlus.startScan();
  }

  // --- NEW: broadcastSOS now takes a 'type' ---
  Future<void> broadcastSOS(int type) async {
    await FlutterBluePlus.stopScan();

    String packetId = _uuid.v4();
    List<int> data = [
      type, // Use the type we passed in
      ...packetId.codeUnits,
    ];
    Uint8List dataAsUint8List = Uint8List.fromList(data);

    final advData = AdvertiseData(
      includeDeviceName: false,
      manufacturerId: _companyId,
      manufacturerData: dataAsUint8List,
    );

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
  // --- END NEW ---

  // --- NEW: _onSosPressed now takes an AlertType ---
  Future<void> _onSosPressed(AlertType alertType) async {
    if (_isBroadcasting) return;

    final now = DateTime.now();
    final String tempPacketId = "SELF-TEST";

    setState(() {
      _isBroadcasting = true;
      // Add the self-test message
      _receivedAlerts.insert(
          0,
          Alert(
            type: alertType.packetCode,
            packetId: tempPacketId,
            timestamp: now,
            rssi: -50, // Fake strong signal
          ));
    });

    // No more "glue". Just do the real work.
    try {
      await broadcastSOS(alertType.packetCode);
    } catch (e) {
      print("Error during broadcast: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error broadcasting: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBroadcasting = false;
        });
      }
    }
  }
  // --- END NEW ---

  // --- THIS IS THE FULLY POLISHED UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Emergency Mesh Beacon"),
        backgroundColor: Color(0xFF1F1F1F),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            // --- NEW: Alert Buttons ---
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Broadcast Alert",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16),
                  _buildAlertButton(_alertTypes[0x01]!), // SOS
                  SizedBox(height: 12),
                  _buildAlertButton(_alertTypes[0x02]!), // Medical
                  SizedBox(height: 12),
                  _buildAlertButton(_alertTypes[0x03]!), // Trapped
                ],
              ),
            ),
            // --- END NEW ---

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                _permissionsGranted
                    ? "Scanning for alerts..."
                    : _permissionStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _permissionsGranted ? Colors.green : Colors.yellow),
              ),
            ),

            if (_canOpenSettings)
              OutlinedButton(
                child: Text("Open App Settings"),
                onPressed: openAppSettings,
              ),

            Divider(),

            Text("Received Alerts",
                style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 10),

            // --- NEW: Polished ListView ---
            Expanded(
              child: _receivedAlerts.isEmpty
                  ? Center(
                      child: Text("Listening... No alerts received yet."),
                    )
                  : ListView.builder(
                      itemCount: _receivedAlerts.length,
                      itemBuilder: (context, index) {
                        final alert = _receivedAlerts[index];
                        final alertInfo = _alertTypes[alert.type] ??
                            AlertType(
                                title: "Unknown",
                                icon: Icons.question_mark,
                                color: Colors.grey,
                                packetCode: 0x00);
                        final isSelfTest = alert.packetId == "SELF-TEST";

                        return Card(
                          color: Color(0xFF2A2A2A),
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ExpansionTile(
                            leading: Icon(alertInfo.icon,
                                color:
                                    isSelfTest ? Colors.white : alertInfo.color,
                                size: 36),
                            title: Text(
                              isSelfTest
                                  ? "MY SOS: ${alertInfo.title}"
                                  : alertInfo.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    isSelfTest ? Colors.white : alertInfo.color,
                              ),
                            ),
                            subtitle: Text("Signal: ${alert.rssi} dBm"),
                            children: [
                              ListTile(
                                title: Text("Time Received"),
                                subtitle: Text(alert.timestamp
                                    .toIso8601String()
                                    .substring(0, 19)
                                    .replaceFirst('T', ' ')),
                              ),
                              ListTile(
                                title: Text("Unique Packet ID"),
                                subtitle: Text(isSelfTest
                                    ? "N/A (Self-Test)"
                                    : alert.packetId.substring(0, 13) + "..."),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // --- END NEW ---
          ],
        ),
      ),
    );
  }

  // --- NEW: Helper widget for buttons ---
  Widget _buildAlertButton(AlertType alertType) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _isBroadcasting ? Colors.grey[700] : alertType.color,
        minimumSize: Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(alertType.icon, color: Colors.white),
      label: Text(
        alertType.title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      onPressed: _permissionsGranted && !_isBroadcasting
          ? () => _onSosPressed(alertType)
          : null,
    );
  }
  // --- END NEW ---
}
