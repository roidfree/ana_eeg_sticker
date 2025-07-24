import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  static const String cytonBoardName = "OpenBCI-Cyton"; // Adjust this if your board shows a different name

  Future<BluetoothDevice?> scanAndConnectToCyton() async {
    print("[BLE] Starting scan...");

    // Disconnect any previously connected devices
    List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedDevices;
    for (var device in connectedDevices) {
      await device.disconnect();
    }

    final Completer<BluetoothDevice?> completer = Completer();
    late StreamSubscription<List<ScanResult>> subscription;

    subscription = FlutterBluePlus.scanResults.listen((List<ScanResult> results) async {
      for (ScanResult result in results) {
        if (result.device.platformName.contains(cytonBoardName)) {
          print("[BLE] Found Cyton Board: ${result.device.platformName}");

          await FlutterBluePlus.stopScan();
          await subscription.cancel();

          try {
            await result.device.connect(autoConnect: false);
            print("[BLE] Connected to ${result.device.platformName}");

            List<BluetoothService> services = await result.device.discoverServices();
            for (var service in services) {
              print('Service: ${service.uuid}');
              for (var characteristic in service.characteristics) {
                print('  Characteristic: ${characteristic.uuid}');

                if (characteristic.properties.notify) {
                  print("[BLE] Subscribing to characteristic ${characteristic.uuid}");

                  await characteristic.setNotifyValue(true);
                  characteristic.lastValueStream.listen((value) {
                    print("[EEG STREAM] Raw bytes: $value");
                  });
                }
              }
            }

            completer.complete(result.device);
          } catch (e) {
            print("[BLE] Failed to connect or subscribe: $e");
            completer.complete(null);
          }

          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    final BluetoothDevice? connectedDevice = await completer.future;

    if (!completer.isCompleted) {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }

    return connectedDevice;
  }
}
