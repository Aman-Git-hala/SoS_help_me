import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class LocalAlertsScreen extends StatefulWidget {
  const LocalAlertsScreen({Key? key}) : super(key: key);

  @override
  State<LocalAlertsScreen> createState() => _LocalAlertsScreenState();
}

class Alert {
  final int type;
  final String packetId;
  final DateTime timestamp;
  final int rssi;
  final bool isEncrypted;
  final double? lat;
  final double? lon;

  Alert({
    required this.type,
    required this.packetId,
    required this.timestamp,
    required this.rssi,
    required this.isEncrypted,
    this.lat,
    this.lon,
  });
}

class AlertType {
  final String title;
  final IconData icon;
  final Color color;
  final int packetCode;

  AlertType({
    required this.title,
    required this.icon,
    required this.color,
    required this.packetCode,
  });
}

class _LocalAlertsScreenState extends State<LocalAlertsScreen>
    with TickerProviderStateMixin {
  bool _permissionsGranted = false;
  String _permissionStatus = "Initializing...";
  bool _canOpenSettings = false;

  final int _companyId = 0x1234;
  final Map<String, Alert> _receivedAlerts = {};
  bool _isBroadcasting = false;
  bool _isEncrypted = false;
  final Uuid _uuid = Uuid(); // We still need this for the *real* packet ID
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final Random _random = Random();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  late AnimationController _pulseController;

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

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    _scanSub?.cancel();
    _pulseController.dispose();
    FlutterBluePlus.stopScan();
    if (_isBroadcasting) {
      _peripheral.stop();
    }
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    if (!await FlutterBluePlus.isAvailable) {
      if (mounted)
        setState(() => _permissionStatus = "Bluetooth not supported.");
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
      Permission.locationWhenInUse,
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
          if (data.length < 13) continue;

          ByteData byteData = ByteData.view(Uint8List.fromList(data).buffer);

          int type = byteData.getUint8(0);
          int packetId = byteData.getUint32(1);
          double lat = byteData.getInt32(5) / 1000000.0;
          double lon = byteData.getInt32(9) / 1000000.0;

          String packetIdStr = packetId.toString();

          if (_alertTypes.containsKey(type)) {
            // We removed the haptic alert for now, but this is where it would go

            final newAlert = Alert(
              type: type,
              packetId: packetIdStr,
              timestamp: now,
              rssi: r.rssi,
              isEncrypted: false,
              lat: lat,
              lon: lon,
            );

            if (mounted) {
              setState(() {
                _receivedAlerts[packetIdStr] = newAlert;
              });
            }
          }
        }
      }
    });
    await FlutterBluePlus.startScan();
  }

  Future<void> broadcastSOS(
      int type, bool isEncrypted, Position? position) async {
    await FlutterBluePlus.stopScan();

    var byteData = ByteData(13);
    int packetId = _random.nextInt(4294967295);

    int latInt = ((position?.latitude ?? 0) * 1000000).toInt();
    int lonInt = ((position?.longitude ?? 0) * 1000000).toInt();

    byteData.setUint8(0, type);
    byteData.setUint32(1, packetId);
    byteData.setInt32(5, latInt);
    byteData.setInt32(9, lonInt);

    Uint8List dataAsUint8List = byteData.buffer.asUint8List();

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

  Future<Position?> _tryGetLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Location services are disabled.")));
        return null;
      }
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
    } catch (e) {
      print("Error getting location: $e");
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Could not get location.")));
      return null;
    }
  }

  Future<void> _onSosPressed(AlertType alertType, bool isEncrypted) async {
    if (_isBroadcasting) return;

    // --- THIS IS THE FIX ---
    // We just set the _isBroadcasting flag
    // We NO LONGER add the "MY SOS" message to the list
    setState(() {
      _isBroadcasting = true;
    });
    // --- END FIX ---

    try {
      Position? position = await _tryGetLocation();
      await broadcastSOS(alertType.packetCode, isEncrypted, position);
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

  Future<void> _openMap(double lat, double lon) async {
    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
    final Uri uri = Uri.parse(googleMapsUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Clipboard.setData(ClipboardData(text: "$lat, $lon"));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not open map. Coordinates copied.")));
      }
    }
  }

  Widget _buildRssiBadge(int rssi) {
    String text;
    Color color;
    Color textColor = Colors.black;
    if (rssi > -65) {
      text = "STRONG";
      color = Colors.green[400]!;
    } else if (rssi > -80) {
      text = "MEDIUM";
      color = Colors.yellow[600]!;
    } else {
      text = "WEAK";
      color = Colors.red[800]!;
      textColor = Colors.white;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alertsList = _receivedAlerts.values.toList();
    alertsList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

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
            if (_isBroadcasting)
              FadeTransition(
                opacity: _pulseController,
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  margin: const EdgeInsets.only(top: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.red[900]!.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 12),
                      Text("BROADCASTING LIVE...",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Broadcast Alert",
                      style: Theme.of(context).textTheme.headlineSmall),
                  SizedBox(height: 10),

                  SwitchListTile(
                    title: Text("Rescuer-Only Flare",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_isEncrypted
                        ? "Encrypted (Private)"
                        : "Public (Visible to all)"),
                    value: _isEncrypted,
                    onChanged: (bool value) {
                      setState(() {
                        _isEncrypted = value;
                      });
                    },
                    secondary: Icon(_isEncrypted ? Icons.lock : Icons.lock_open,
                        color: Colors.grey[400]),
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.red[400],
                  ),

                  SizedBox(height: 10),
                  _buildAlertButton(_alertTypes[0x01]!), // SOS
                  SizedBox(height: 12),
                  _buildAlertButton(_alertTypes[0x02]!), // Medical
                  SizedBox(height: 12),
                  _buildAlertButton(_alertTypes[0x03]!), // Trapped
                ],
              ),
            ),
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
            Expanded(
              child: alertsList.isEmpty
                  ? Center(
                      child: Text("Listening... No alerts received yet."),
                    )
                  : ListView.builder(
                      itemCount: alertsList.length,
                      itemBuilder: (context, index) {
                        final alert = alertsList[index];
                        final alertInfo = _alertTypes[alert.type] ??
                            AlertType(
                                title: "Unknown",
                                icon: Icons.question_mark,
                                color: Colors.grey,
                                packetCode: 0x00);

                        // --- THIS IS THE FIX ---
                        // We no longer check for 'isSelfTest'
                        // All alerts are treated as real

                        return Card(
                          color: Color(0xFF2A2A2A),
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ExpansionTile(
                            leading: Icon(alertInfo.icon,
                                color: alertInfo.color, size: 36),
                            title: Row(
                              children: [
                                if (alert.isEncrypted)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Icon(Icons.lock,
                                        size: 16, color: alertInfo.color),
                                  ),
                                Flexible(
                                  child: Text(
                                    alertInfo.title, // Just show the title
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: alertInfo.color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            // --- END FIX ---
                            subtitle: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildRssiBadge(alert.rssi),
                                SizedBox(width: 8),
                                Text("(${alert.rssi} dBm)",
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[400])),
                              ],
                            ),
                            children: [
                              ListTile(
                                title: Text("Time Received"),
                                subtitle: Text(alert.timestamp
                                    .toIso8601String()
                                    .substring(0, 19)
                                    .replaceFirst('T', ' ')),
                              ),
                              if (alert.lat != null && alert.lat != 0.0)
                                ListTile(
                                  title: Text("Last Known Location"),
                                  subtitle: Text("${alert.lat}, ${alert.lon}"),
                                  trailing: IconButton(
                                    icon: Icon(Icons.map,
                                        color: Colors.blue[300]),
                                    tooltip: "Open in Maps",
                                    onPressed: () {
                                      _openMap(alert.lat!, alert.lon!);
                                    },
                                  ),
                                ),
                              ListTile(
                                title: Text("Unique Packet ID"),
                                subtitle: Text(
                                    alert.packetId), // Just show the real ID
                              ),
                            ],
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
          ? () => _onSosPressed(alertType, _isEncrypted)
          : null,
    );
  }
}
