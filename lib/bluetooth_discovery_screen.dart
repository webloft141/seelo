import 'dart:async';
import 'package:flutter/material.dart';
import 'bluetooth_service.dart';

class BluetoothDiscoveryScreen extends StatefulWidget {
  const BluetoothDiscoveryScreen({super.key});

  @override
  State<BluetoothDiscoveryScreen> createState() => _BluetoothDiscoveryScreenState();
}

class _BluetoothDiscoveryScreenState extends State<BluetoothDiscoveryScreen> {
  final _ble = BluetoothService();
  List<SeeloBLEDevice> _devices = [];
  bool _loading = true;
  String _status = 'Initializing Bluetooth...';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await _ble.isBluetoothAvailable;
    if (!mounted) return;
    if (!available) {
      setState(() {
        _loading = false;
        _status = 'Bluetooth not available on this device';
      });
      return;
    }

    final on = await _ble.isBluetoothOn;
    if (!mounted) return;
    if (!on) {
      setState(() {
        _loading = false;
        _status = 'Turn on Bluetooth to discover devices';
      });
      return;
    }

    setState(() => _status = 'Scanning for Seelo devices...');

    _sub = _ble.discoveredDevices.listen((devices) {
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
        _status = devices.isEmpty
            ? 'No Seelo devices found nearby'
            : '${devices.length} device${devices.length == 1 ? '' : 's'} found';
      });
    });

    await _ble.startScan(timeout: const Duration(seconds: 15));

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (_devices.isEmpty) {
        _status = 'No Seelo devices found. Make sure your desktop is nearby with Bluetooth on.';
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
          : _devices.isEmpty
              ? _buildEmptyState()
              : _buildDeviceList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: const Color(0xFF333333)),
            const SizedBox(height: 16),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _status = 'Scanning...';
                });
                _init();
              },
              icon: const Icon(Icons.refresh),
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
                          if (device.roomSecret.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Secrets: ${device.roomSecret.substring(0, 8)}...', style: const TextStyle(color: Color(0xFF52525B), fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Row(
                          children: List.generate(4, (j) => Container(
                            width: 4,
                            height: 10,
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
}
