import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'nmea_generator.dart';
import 'gps_sender.dart';
import 'gps_bridge.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NMEA GPSD Tool',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12141C),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E2130),
          elevation: 4,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Common state
  final List<String> _consoleLogs = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLinux = false;

  // Sender state (Android)
  final GpsSender _gpsSender = GpsSender();
  StreamSubscription<String>? _senderLogSubscription;
  StreamSubscription<Position>? _geolocatorSubscription;
  final _hostController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '9999');
  bool _useUdp = true;
  Position? _currentPosition;
  String _gpsStatus = "Idle";

  // Receiver state (Linux)
  final GpsBridge _gpsBridge = GpsBridge();
  StreamSubscription<String>? _bridgeLogSubscription;
  final _udpListenPortController = TextEditingController(text: '9999');
  final _tcpBridgePortController = TextEditingController(text: '8888');
  Timer? _linuxStatusTimer;

  @override
  void initState() {
    super.initState();
    _isLinux = Platform.isLinux;
    
    if (_isLinux) {
      _initLinuxBridge();
    } else {
      _initAndroidSender();
    }
  }

  void _initAndroidSender() {
    _senderLogSubscription = _gpsSender.logStream.listen((log) {
      _addLog(log);
    });
  }

  void _initLinuxBridge() {
    _bridgeLogSubscription = _gpsBridge.logStream.listen((log) {
      _addLog(log);
    });
    // Periodically refresh UI to show gpsd connection status
    _linuxStatusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _gpsBridge.isServerRunning) {
        setState(() {});
      }
    });
  }

  void _addLog(String log) {
    if (!mounted) return;
    setState(() {
      if (_consoleLogs.length > 100) {
        _consoleLogs.removeAt(0);
      }
      _consoleLogs.add(log);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _senderLogSubscription?.cancel();
    _geolocatorSubscription?.cancel();
    _bridgeLogSubscription?.cancel();
    _linuxStatusTimer?.cancel();
    _gpsSender.dispose();
    _gpsBridge.dispose();
    _hostController.dispose();
    _portController.dispose();
    _udpListenPortController.dispose();
    _tcpBridgePortController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Sender Logic (Android) ---

  Future<void> _toggleStreaming() async {
    if (_gpsSender.isStreaming) {
      _stopStreaming();
    } else {
      await _startStreaming();
    }
  }

  Future<void> _startStreaming() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9999;

    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Host IP')),
      );
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsStatus = "Location services disabled");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _gpsStatus = "Location permissions denied");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = "Location permissions permanently denied");
        return;
      }

      setState(() => _gpsStatus = "Acquiring Fix...");
      
      await _gpsSender.start(
        host: host,
        port: port,
        useUdp: _useUdp,
      );

      _geolocatorSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((Position position) {
        setState(() {
          _currentPosition = position;
          _gpsStatus = "Fix: Accuracy ${position.accuracy.toStringAsFixed(1)}m";
        });

        if (_gpsSender.isStreaming) {
          _sendPositionData(
            lat: position.latitude,
            lon: position.longitude,
            alt: position.altitude,
            speedKph: position.speed * 3.6,
            heading: position.heading,
            accuracy: position.accuracy,
            time: position.timestamp,
          );
        }
      });

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start: $e')),
      );
      _stopStreaming();
    }
  }

  void _stopStreaming() {
    _gpsSender.stop();
    _geolocatorSubscription?.cancel();
    setState(() {
      _gpsStatus = "Idle";
    });
  }

  void _sendPositionData({
    required double lat,
    required double lon,
    required double alt,
    required double speedKph,
    required double heading,
    required double accuracy,
    required DateTime time,
  }) {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9999;

    final rmc = NmeaGenerator.generateRmc(
      latitude: lat,
      longitude: lon,
      speedKph: speedKph,
      heading: heading,
      time: time,
    );

    final gga = NmeaGenerator.generateGga(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      accuracy: accuracy,
      time: time,
    );

    _gpsSender.sendSentence(rmc, host, port, _useUdp);
    _gpsSender.sendSentence(gga, host, port, _useUdp);
  }

  // --- Bridge Logic (Linux) ---

  Future<void> _toggleBridge() async {
    if (_gpsBridge.isServerRunning) {
      _gpsBridge.stop();
      setState(() {});
    } else {
      final udpPort = int.tryParse(_udpListenPortController.text.trim()) ?? 9999;
      final tcpPort = int.tryParse(_tcpBridgePortController.text.trim()) ?? 8888;
      
      try {
        await _gpsBridge.start(
          udpListenPort: udpPort,
          tcpBridgePort: tcpPort,
        );
        setState(() {});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start bridge: $e')),
        );
      }
    }
  }

  // --- BUILD METHODS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLinux ? 'NMEA GPSD Bridge (Linux)' : 'NMEA GPSD Sender (Android)'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E2130),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (_isLinux) ...[
                    _buildLinuxConfigCard(),
                    const SizedBox(height: 16),
                    _buildLinuxInstructionCard(),
                  ] else ...[
                    _buildAndroidConnectionCard(),
                    const SizedBox(height: 16),
                    _buildAndroidGpsCard(),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildTerminalCard(),
            const SizedBox(height: 16),
            _buildActionButton(),
          ],
        ),
      ),
    );
  }

  // --- Linux widgets ---

  Widget _buildLinuxConfigCard() {
    final isRunning = _gpsBridge.isServerRunning;
    final isGpsdConnected = _gpsBridge.isGpsdConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Bridge Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    _buildStatusChip(
                      label: isRunning ? 'BRIDGE UP' : 'BRIDGE DOWN',
                      isActive: isRunning,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      label: isGpsdConnected ? 'GPSD CONNECTED' : 'GPSD WAITING',
                      isActive: isGpsdConnected,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _udpListenPortController,
                    enabled: !isRunning,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'UDP Listen Port (from Android)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.download),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _tcpBridgePortController,
                    enabled: !isRunning,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'TCP Bridge Port (to gpsd)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.upload),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinuxInstructionCard() {
    final tcpPort = _tcpBridgePortController.text.trim();
    final command = 'sudo gpsd -N -n tcp://127.0.0.1:$tcpPort';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How to connect gpsd on CachyOS:',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 8),
            const Text(
              'Run this command in your terminal to link the gpsd service to this local bridge:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      command,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: command));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Command copied to clipboard!')),
                      );
                    },
                    tooltip: 'Copy command',
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({required String label, required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? Colors.green : Colors.red,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.greenAccent : Colors.redAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --- Android widgets ---

  Widget _buildAndroidConnectionCard() {
    final isStreaming = _gpsSender.isStreaming;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Target Destination',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                _buildStatusChip(
                  label: isStreaming ? 'ACTIVE' : 'OFFLINE',
                  isActive: isStreaming,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostController,
                    enabled: !isStreaming,
                    decoration: const InputDecoration(
                      labelText: 'Linux Host IP',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.computer),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portController,
                    enabled: !isStreaming,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.settings_ethernet),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Protocol:'),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('UDP'),
                      selected: _useUdp,
                      onSelected: isStreaming ? null : (selected) {
                        setState(() => _useUdp = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('TCP'),
                      selected: !_useUdp,
                      onSelected: isStreaming ? null : (selected) {
                        setState(() => _useUdp = false);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidGpsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Real GPS Device Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Status: $_gpsStatus', style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            if (_currentPosition != null) ...[
              Text('Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}°'),
              Text('Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}°'),
              Text('Altitude: ${_currentPosition!.altitude.toStringAsFixed(1)}m'),
              Text('Speed: ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h'),
              Text('Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m'),
            ] else
              const Text('No GPS data yet. Start streaming to query sensors.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // --- Common widgets ---

  Widget _buildTerminalCard() {
    return Expanded(
      child: Card(
        color: const Color(0xFF0A0C10),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isLinux ? 'NMEA Bridge Traffic' : 'Outgoing NMEA Stream Log',
                    style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(color: Colors.cyan),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _consoleLogs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      _consoleLogs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (_isLinux) {
      final isRunning = _gpsBridge.isServerRunning;
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _toggleBridge,
          icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
          label: Text(
            isRunning ? 'STOP BRIDGE SERVER' : 'START BRIDGE SERVER',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isRunning ? Colors.redAccent : Colors.cyan,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    } else {
      final isStreaming = _gpsSender.isStreaming;
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _toggleStreaming,
          icon: Icon(isStreaming ? Icons.stop : Icons.play_arrow),
          label: Text(
            isStreaming ? 'STOP STREAMING' : 'START STREAMING',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isStreaming ? Colors.redAccent : Colors.cyan,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
  }
}
