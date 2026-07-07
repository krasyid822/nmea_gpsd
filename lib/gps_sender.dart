import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GpsSender {
  RawDatagramSocket? _udpSocket;
  Socket? _tcpSocket;
  bool _isStreaming = false;

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  bool get isStreaming => _isStreaming;

  Future<void> start({
    required String host,
    required int port,
    required bool useUdp,
  }) async {
    if (_isStreaming) return;
    try {
      if (useUdp) {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _logController.add("UDP Socket bound to local port ${_udpSocket!.port}");
      } else {
        _tcpSocket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
        _logController.add("TCP Connected to $host:$port");
      }
      _isStreaming = true;
    } catch (e) {
      _logController.add("Error connecting/binding: $e");
      stop();
      rethrow;
    }
  }

  void sendSentence(String sentence, String host, int port, bool useUdp) {
    if (!_isStreaming) return;

    final formattedSentence = '$sentence\r\n';
    final data = utf8.encode(formattedSentence);

    try {
      if (useUdp && _udpSocket != null) {
        final address = InternetAddress(host);
        _udpSocket!.send(data, address, port);
        _logController.add("[UDP] Sent: ${sentence.trim()}");
      } else if (!useUdp && _tcpSocket != null) {
        _tcpSocket!.add(data);
        _logController.add("[TCP] Sent: ${sentence.trim()}");
      }
    } catch (e) {
      _logController.add("Error sending: $e");
    }
  }

  void stop() {
    _isStreaming = false;
    _udpSocket?.close();
    _udpSocket = null;
    _tcpSocket?.destroy();
    _tcpSocket = null;
    _logController.add("Streaming stopped.");
  }

  void dispose() {
    stop();
    _logController.close();
  }
}
