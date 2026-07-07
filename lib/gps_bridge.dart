import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GpsBridge {
  RawDatagramSocket? _udpListener;
  ServerSocket? _tcpServer;
  Socket? _gpsdSocket;
  bool _isServerRunning = false;

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  bool get isServerRunning => _isServerRunning;
  bool get isGpsdConnected => _gpsdSocket != null;

  Future<void> start({
    required int udpListenPort,
    required int tcpBridgePort,
  }) async {
    if (_isServerRunning) return;

    try {
      // 1. Start TCP Server for gpsd to connect to
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, tcpBridgePort);
      _logController.add("[Bridge] TCP Server listening on port $tcpBridgePort (Waiting for gpsd...)");

      _tcpServer!.listen((Socket clientSocket) {
        _logController.add("[Bridge] gpsd connected from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}");
        // Close previous socket if any
        _gpsdSocket?.destroy();
        _gpsdSocket = clientSocket;

        _gpsdSocket!.done.then((_) {
          _logController.add("[Bridge] gpsd disconnected.");
          _gpsdSocket = null;
        });
      }, onError: (e) {
        _logController.add("[Bridge] TCP Server error: $e");
      });

      // 2. Start UDP Listener to receive from Android
      _udpListener = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpListenPort);
      _logController.add("[Bridge] UDP Listener running on port $udpListenPort (Waiting for Android...)");

      _udpListener!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpListener!.receive();
          if (datagram != null) {
            final sentence = utf8.decode(datagram.data).trim();
            _logController.add("[Received] $sentence");
            
            // Forward to gpsd if connected
            if (_gpsdSocket != null) {
              try {
                _gpsdSocket!.write('$sentence\r\n');
                _logController.add("[Forwarded] Sent to gpsd");
              } catch (e) {
                _logController.add("[Error] Failed to forward to gpsd: $e");
              }
            } else {
              _logController.add("[Warning] gpsd not connected. Sentence discarded.");
            }
          }
        }
      });

      _isServerRunning = true;
    } catch (e) {
      _logController.add("[Error] Failed to start bridge: $e");
      stop();
      rethrow;
    }
  }

  void stop() {
    _isServerRunning = false;
    _udpListener?.close();
    _udpListener = null;
    _gpsdSocket?.destroy();
    _gpsdSocket = null;
    _tcpServer?.close();
    _tcpServer = null;
    _logController.add("[Bridge] Bridge stopped.");
  }

  void dispose() {
    stop();
    _logController.close();
  }
}
