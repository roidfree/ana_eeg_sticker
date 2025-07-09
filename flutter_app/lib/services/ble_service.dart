// lib/services/simple_cyton_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class SimpleCytonService {
  static final SimpleCytonService _instance = SimpleCytonService._internal();
  factory SimpleCytonService() => _instance;
  SimpleCytonService._internal();

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;

  // Simple data stream - just raw values
  final StreamController<String> _dataStreamController =
      StreamController<String>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  Stream<String> get dataStream => _dataStreamController.stream;
  Stream<String> get statusStream => _statusController.stream;

  bool _isConnected = false;
  bool _isStreaming = false;

  /// Find and connect to Cyton board
  Future<bool> connectToCyton() async {
    try {
      _updateStatus('Scanning for Cyton board...');

      // Look for bonded devices
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance
          .getBondedDevices();

      // Find Cyton board (usually shows as "OpenBCI-XXXX" or similar)
      BluetoothDevice? cytonDevice = devices.firstWhere(
        (device) =>
            device.name?.toLowerCase().contains('openbci') == true ||
            device.name?.toLowerCase().contains('cyton') == true,
        orElse: () => null,
      );

      if (cytonDevice == null) {
        _updateStatus('No Cyton board found. Make sure it\'s paired.');
        return false;
      }

      _updateStatus('Connecting to ${cytonDevice.name}...');

      // Connect
      _connection = await BluetoothConnection.toAddress(cytonDevice.address);
      _isConnected = true;

      // Start listening for data
      _startListening();

      _updateStatus('Connected to ${cytonDevice.name}');
      return true;
    } catch (e) {
      _updateStatus('Connection failed: $e');
      return false;
    }
  }

  /// Start listening for incoming data
  void _startListening() {
    if (_connection == null) return;

    _dataSubscription = _connection!.input!.listen(
      (Uint8List data) {
        // Convert bytes to string and broadcast
        String dataString = String.fromCharCodes(data);
        _dataStreamController.add(dataString);
      },
      onError: (error) {
        _updateStatus('Data error: $error');
      },
      onDone: () {
        _updateStatus('Connection closed');
        _isConnected = false;
        _isStreaming = false;
      },
    );
  }

  /// Send command to Cyton board
  Future<void> sendCommand(String command) async {
    if (!_isConnected || _connection == null) {
      _updateStatus('Not connected');
      return;
    }

    try {
      _connection!.output.add(Uint8List.fromList(command.codeUnits));
      await _connection!.output.allSent;
      _updateStatus('Sent: $command');
    } catch (e) {
      _updateStatus('Send error: $e');
    }
  }

  /// Start streaming data
  Future<void> startStreaming() async {
    await sendCommand('b'); // 'b' starts streaming
    _isStreaming = true;
    _updateStatus('Streaming started');
  }

  /// Stop streaming data
  Future<void> stopStreaming() async {
    await sendCommand('s'); // 's' stops streaming
    _isStreaming = false;
    _updateStatus('Streaming stopped');
  }

  /// Reset the board
  Future<void> resetBoard() async {
    await sendCommand('v'); // 'v' resets the board
    _updateStatus('Board reset');
  }

  /// Update status
  void _updateStatus(String status) {
    print('Cyton: $status');
    _statusController.add(status);
  }

  /// Get connection status
  bool get isConnected => _isConnected;
  bool get isStreaming => _isStreaming;

  /// Disconnect
  Future<void> disconnect() async {
    try {
      if (_isStreaming) {
        await stopStreaming();
      }

      _dataSubscription?.cancel();
      await _connection?.close();

      _isConnected = false;
      _isStreaming = false;

      _updateStatus('Disconnected');
    } catch (e) {
      _updateStatus('Disconnect error: $e');
    }
  }

  /// Clean up
  void dispose() {
    _dataStreamController.close();
    _statusController.close();
    _dataSubscription?.cancel();
    _connection?.close();
  }
}
