import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bluetooth_service.dart' as ble;

class BluetoothDiscoveryScreen extends StatefulWidget {
  const BluetoothDiscoveryScreen({super.key});

  @override
  State<BluetoothDiscoveryScreen> createState() => _BluetoothDiscoveryScreenState();
}

class _BluetoothDiscoveryScreenState extends State<BluetoothDiscoveryScreen> {
  final _ble = ble.SeeloBleService();
  List<ble.SeeloBLEDevice> _devices = [];
  ble.BleState _bleState = ble.BleState.initial;
  String _error = '';
  StreamSubscription? _stateSub;
  StreamSubscription? _deviceSub;
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    _stateSub = _ble.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _bleState = s);
    });
    _init();
  }

  Future<void> _init() async {
    final available = await FlutterBluePlus.isSupported;
    if (!mounted) return;

    if (!available) {
      setState(() {
        _bleState = ble.BleState.unavailable;
        _error = 'Bluetooth not available on this device';
        _initDone = true;
      });
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;

    if (adapterState != BluetoothAdapterState.on) {
      setState(() {
        _bleState = ble.BleState.bluetoothOff;
        _initDone = true;
      });
      return;
    }

    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _initDone = true);
    _deviceSub = _ble.discoveredDevices.listen((devices) {
      if (!mounted) return;
      setState(() => _devices = devices);
    });

    final err = await _ble.startScan();
    if (!mounted) return;
    if (err.isNotEmpty) {
      setState(() => _error = err);
    }

    // After scan completes (timeout), if no devices found
    if (_ble.state != ble.BleState.permissionDenied && _ble.state != ble.BleState.bluetoothOff && mounted) {
      setState(() {
        if (_error.isEmpty && _devices.isEmpty) {
          _error = 'No Seelo devices found nearby.\nMake sure your desktop is running with Bluetooth enabled.';
        }
      });
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _deviceSub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0D12),
        title: const Text('Bluetooth Discovery', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_initDone) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)));
    }

    switch (_bleState) {
      case ble.BleState.unavailable:
        return _errorState(Icons.bluetooth_disabled, 'Bluetooth Not Available',
            'This device does not support Bluetooth LE scanning.', null);
      case ble.BleState.permissionDenied:
        return _errorState(
          Icons.block,
          'Permission Required',
          _error.isNotEmpty ? _error : 'Bluetooth permission is needed to discover nearby Seelo devices.',
          () => _retry(),
        );
      case ble.BleState.bluetoothOff:
        return _errorState(
          Icons.bluetooth_disabled,
          'Bluetooth is Off',
          'Turn on Bluetooth to discover nearby Seelo desktop devices.',
          () => _retry(),
        );
      case ble.BleState.scanning:
        return _buildScanning();
      case ble.BleState.error:
        return _errorState(
          Icons.error_outline,
          'Something Went Wrong',
          _error.isNotEmpty ? _error : 'An unexpected error occurred.',
          () => _retry(),
        );
      case ble.BleState.initial:
      case ble.BleState.idle:
        return _devices.isEmpty ? _buildEmpty() : _buildDeviceList();
    }
  }

  Widget _errorState(IconData icon, String title, String message, VoidCallback? onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: const Color(0xFF52525B)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanning() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scanning for Seelo devices...',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure your desktop is running\nand Bluetooth is enabled',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('${_devices.length} device${_devices.length == 1 ? '' : 's'} found so far',
                  style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13)),
            ],
            const SizedBox(height: 24),
            TextButton(
              onPressed: _cancelScan,
              child: const Text('Cancel Scan', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, size: 64, color: const Color(0xFF333333)),
            const SizedBox(height: 16),
            Text(
              _error.isNotEmpty ? _error : 'No Seelo devices found',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ensure your desktop is nearby,\nrunning Seelo, and Bluetooth is on',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF52525B), fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Scan Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final device = _devices[i];
        final signalBars = device.rssi > -60
            ? 4
            : device.rssi > -70
            ? 3
            : device.rssi > -85
            ? 2
            : 1;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C0D12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1F28)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.pop(context, device.toConnectionPayload()),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bluetooth, color: Color(0xFF6366F1), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('${device.ip}:${device.port}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Row(
                          children: List.generate(4, (j) => Container(
                            width: 4, height: 10,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(
                              color: j < signalBars ? const Color(0xFF22C55E) : const Color(0xFF2D2E3A),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )),
                        ),
                        const SizedBox(height: 4),
                        Text('${device.rssi} dBm', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Color(0xFF52525B), size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _cancelScan() {
    _ble.stopScan();
    setState(() {
      if (_devices.isEmpty) {
        _error = 'Scan cancelled';
      }
    });
  }

  Future<void> _retry() async {
    setState(() {
      _error = '';
      _devices = [];
    });
    await _ble.stopScan();
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) {
      _startScan();
    } else {
      setState(() => _bleState = ble.BleState.bluetoothOff);
    }
  }
}
