import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SeeloBLEDevice {
  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final String roomSecret;
  final int rssi;

  SeeloBLEDevice({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.roomSecret,
    required this.rssi,
  });

  Map<String, dynamic> toConnectionPayload() => {
    'mode': 'local',
    'ip': ip,
    'port': port,
    'roomId': 'seelo-desktop',
    'roomSecret': roomSecret,
  };
}

class BluetoothService {
  static const int _seeloCompanyId = 0xFFFF;
  static const String _seeloNamePrefix = 'Seelo';

  final _devices = <String, SeeloBLEDevice>{};
  final _deviceController = StreamController<List<SeeloBLEDevice>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  Stream<List<SeeloBLEDevice>> get discoveredDevices => _deviceController.stream;
  bool get isScanning => _isScanning;

  Future<bool> get isBluetoothAvailable async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isBluetoothOn async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) return;
    _isScanning = true;
    _devices.clear();

    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }

      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _processScanResult(result);
        }
        _deviceController.add(_devices.values.toList());
      });
    } catch (_) {
      _isScanning = false;
    }
  }

  void _processScanResult(ScanResult result) {
    try {
      final adv = result.advertisementData;
      final name = adv.advName.isNotEmpty ? adv.advName : result.device.platformName;
      if (!name.contains(_seeloNamePrefix)) return;

      final mfg = adv.manufacturerData;
      final data = mfg[_seeloCompanyId];
      if (data == null || data.length < 8) return;

      final port = (data[0] << 8) | data[1];
      final ip = '${data[2]}.${data[3]}.${data[4]}.${data[5]}';

      String roomSecret = '';
      if (data.length >= 22) {
        roomSecret = data.sublist(6, 22)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      } else if (data.length > 6) {
        roomSecret = data.sublist(6)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }

      final deviceId = result.device.remoteId.str;
      _devices[deviceId] = SeeloBLEDevice(
        deviceId: deviceId,
        name: name,
        ip: ip,
        port: port,
        roomSecret: roomSecret,
        rssi: result.rssi,
      );
    } catch (_) {}
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void dispose() {
    stopScan();
    _deviceController.close();
  }
}
