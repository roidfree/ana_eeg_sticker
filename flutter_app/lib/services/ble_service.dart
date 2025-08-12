// lib/services/ble_service.dart

// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  BluetoothDevice? _device;
  late BluetoothCharacteristic _txChar;
  late BluetoothCharacteristic _rxChar;
  final _eegController = StreamController<List<double>>.broadcast();

  /// Stream of 4-channel EEG samples (~26 Hz)
  Stream<List<double>> get eegStream => _eegController.stream;

  // Nordic UART Service & Characteristics UUIDs
  static final Guid _svcUuid = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
  static final Guid _txUuid  = Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
  static final Guid _rxUuid  = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");

  /// Scan for [timeout] and return all unique ScanResults.
  Future<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 5)}) async {
    final Map<String, ScanResult> results = {};

    // 1) Start scanning for any device
    FlutterBluePlus.startScan(timeout: timeout);

    // 2) Collect results (deduplicated by device ID)
    final sub = FlutterBluePlus.scanResults.listen((rList) {
      for (final r in rList) {
        results[r.device.id.id] = r;
      }
    });

    // 3) Wait for scan to finish then stop
    await Future.delayed(timeout);
    FlutterBluePlus.stopScan();
    await sub.cancel();

    return results.values.toList();
  }

  /// Connects to [device], subscribes to UART TX, writes start byte to RX.
  Future<bool> connectDevice(BluetoothDevice device) async {
    try {
      // 1) Connect
      await device.connect(autoConnect: false);
      _device = device;

      // 2) Discover services
      final svcs = await device.discoverServices();
      final uartService = svcs.firstWhere((s) => s.uuid == _svcUuid);

      // 3) Locate TX & RX characteristics
      _txChar = uartService.characteristics.firstWhere((c) => c.uuid == _txUuid);
      _rxChar = uartService.characteristics.firstWhere((c) => c.uuid == _rxUuid);

      // 4) Enable notifications on TX
      await _txChar.setNotifyValue(true);
      _txChar.value.listen(_handleData);

      // 5) Send “start streaming” command to RX
      await _rxChar.write([0x01], withoutResponse: false);

      return true;
    } catch (e) {
      print("BLE connectDevice error: $e");
      return false;
    }
  }

  /// Parses each 8-byte notification into four 16-bit LE samples → doubles.
  void _handleData(List<int> raw) {
    if (raw.length < 8) return;
    final bd = ByteData.sublistView(Uint8List.fromList(raw));
    final sample = List<double>.generate(4, (i) {
      return bd.getInt16(i * 2, Endian.little).toDouble();
    });
    _eegController.add(sample);
  }

  /// Disconnects from device and closes the stream.
  Future<void> disconnect() async {
    if (_device != null) {
      await _txChar.setNotifyValue(false);
      await _device!.disconnect();
    }
    await _eegController.close();
  }
}
