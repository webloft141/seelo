import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum BleState { initial, unavailable, permissionDenied, bluetoothOff, scanning, idle, error }

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

class SeeloBleService {
  static const int _seeloCompanyId = 0xFFFF;
  static const String _seeloNamePrefix = 'Seelo';

  final _devices = <String, SeeloBLEDevice>{};
  final _deviceController = StreamController<List<SeeloBLEDevice>>.broadcast();
  final _stateController = StreamController<BleState>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  BleState _state = BleState.initial;

  Stream<List<SeeloBLEDevice>> get discoveredDevices => _deviceController.stream;
  Stream<BleState> get stateStream => _stateController.stream;
  BleState get state => _state;
  bool get isScanning => _state == BleState.scanning;

  SeeloBleService() {
    FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.off) {
        _updateState(BleState.bluetoothOff);
      } else if (s == BluetoothAdapterState.on && _state == BleState.bluetoothOff) {
        _updateState(BleState.idle);
      }
    });
  }

  void _updateState(BleState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  Future<BleState> checkAvailability() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        _updateState(BleState.unavailable);
        return BleState.unavailable;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _updateState(BleState.bluetoothOff);
        return BleState.bluetoothOff;
      }

      _updateState(BleState.idle);
      return BleState.idle;
    } catch (_) {
      _updateState(BleState.error);
      return BleState.error;
    }
  }

  Future<String> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_state == BleState.scanning) return '';
    _devices.clear();
    _updateState(BleState.scanning);

    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _updateState(BleState.bluetoothOff);
        return 'Turn on Bluetooth to scan for devices';
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

      return '';
    } on FlutterBluePlusException catch (e) {
      final msg = e.description ?? '';
      if (msg.toLowerCase().contains('permission') || msg.toLowerCase().contains('denied') || msg.toLowerCase().contains('not granted')) {
        _updateState(BleState.permissionDenied);
        if (msg.contains('nearby')) {
          return 'Bluetooth permission denied. Go to Settings > Apps > Seelo > Permissions and grant "Nearby devices".';
        }
        return 'Bluetooth permission denied. Please grant Bluetooth access in Settings.';
      }
      _updateState(BleState.error);
      return 'Bluetooth scan failed: ${e.description ?? 'Unknown error'}';
    } catch (e) {
      _updateState(BleState.error);
      return 'Bluetooth error: $e';
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
    if (_state == BleState.scanning) {
      _updateState(BleState.idle);
    }
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void dispose() {
    stopScan();
    _deviceController.close();
    _stateController.close();
  }
}
