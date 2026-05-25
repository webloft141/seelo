import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'bluetooth_service.dart' as ble;

class QuickPairingScreen extends StatefulWidget {
  const QuickPairingScreen({super.key});

  @override
  State<QuickPairingScreen> createState() => _QuickPairingScreenState();
}

class _QuickPairingScreenState extends State<QuickPairingScreen>
    with TickerProviderStateMixin {
  final _bleService = ble.SeeloBleService();
  List<ble.SeeloBLEDevice> _devices = [];
  ble.BleState _bleState = ble.BleState.initial;
  String _error = '';
  StreamSubscription? _stateSub;
  StreamSubscription? _deviceSub;
  bool _scanComplete = false;
  int? _selectedIndex;
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _stateSub = _bleService.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _bleState = s);
      if (s == ble.BleState.idle) {
        _scanComplete = true;
        if (mounted && _devices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Scan complete — no devices found'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
    _startScan();
  }

  Future<void> _startScan() async {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scanning for Seelo devices...'),
        duration: Duration(seconds: 2),
      ),
    );
    final avail = await _bleService.checkAvailability();
    if (!mounted) return;
    if (avail == ble.BleState.bluetoothOff) {
      setState(() => _error = 'Turn on Bluetooth to discover devices');
      return;
    }
    if (avail == ble.BleState.unavailable) {
      setState(() => _error = 'Bluetooth not available on this device');
      return;
    }
    _deviceSub = _bleService.discoveredDevices.listen((devices) {
      if (!mounted) return;
      final prevCount = _devices.length;
      setState(() => _devices = devices);
      if (devices.length > prevCount) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${devices.length} device${devices.length == 1 ? '' : 's'} found'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    final err = await _bleService.startScan();
    if (!mounted) return;
    if (err.isNotEmpty) {
      setState(() => _error = err);
      if (err.toLowerCase().contains('permission')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permission required — tap "Grant Permission" to continue'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    _stateSub?.cancel();
    _deviceSub?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  int _signalBars(int rssi) {
    if (rssi > -60) return 4;
    if (rssi > -70) return 3;
    if (rssi > -85) return 2;
    return 1;
  }

  void _connectSelected() {
    if (_selectedIndex == null || _selectedIndex! >= _devices.length) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connecting...'),
        duration: Duration(seconds: 1),
      ),
    );
    Navigator.pop(context, _devices[_selectedIndex!].toConnectionPayload());
  }

  void _manualSetup() {
    HapticFeedback.mediumImpact();
    Navigator.pop(context, {'mode': 'manual'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9F9),
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SEELO',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: Color(0xFF000000),
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error.isNotEmpty) {
      return _buildEmpty(_error);
    }
    if (_bleState == ble.BleState.unavailable) {
      return _buildEmpty('Bluetooth not available');
    }
    if (_bleState == ble.BleState.bluetoothOff) {
      return _buildEmpty('Bluetooth is off');
    }
    if (_bleState == ble.BleState.permissionDenied) {
      return _buildEmpty(_error.isNotEmpty ? _error : 'Permission denied');
    }
    if (_bleState == ble.BleState.scanning && _devices.isEmpty) {
      return _buildScanning();
    }
    if (_devices.isNotEmpty) {
      return _buildDeviceList();
    }
    if (_scanComplete && _devices.isEmpty) {
      return _buildEmpty('No devices found');
    }
    return _buildScanning();
  }

  Widget _buildScanning() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Container(
                width: 80 + _pulseAnim.value * 20,
                height: 80 + _pulseAnim.value * 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF000000,
                  ).withValues(alpha: 0.05 * (1 - _pulseAnim.value * 0.5)),
                ),
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF000000).withValues(alpha: 0.08),
                    ),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Scanning for devices...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your desktop app is\nrunning and discoverable',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF626262),
              height: 1.4,
            ),
          ),
          if (_devices.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '${_devices.length} device${_devices.length == 1 ? '' : 's'} found',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openBluetoothSettings() async {
    final url = Uri.parse('android.settings://application_details?id=com.seelopro.app');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Settings. Please grant Bluetooth permission manually.')),
      );
    }
  }

  Widget _buildEmpty(String message) {
    final isPermissionDenied = _bleState == ble.BleState.permissionDenied ||
        message.toLowerCase().contains('permission');
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPermissionDenied ? Icons.shield_rounded : Icons.search_off_rounded,
            size: 64,
            color: const Color(0xFF848484),
          ),
          const SizedBox(height: 24),
          Text(
            _error.isNotEmpty ? _error : message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF1A1C1C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPermissionDenied
                ? 'Bluetooth permission is required to discover nearby devices.\nTap "Grant Permission" to allow it.'
                : 'Ensure your desktop is nearby,\nrunning Seelo, and Bluetooth is on',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF626262),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          if (isPermissionDenied)
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                _openBluetoothSettings();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  border: Border.all(color: const Color(0xFF000000)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'GRANT PERMISSION',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFFFFF),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _restartScan();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isPermissionDenied ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
                border: Border.all(color: isPermissionDenied ? const Color(0xFF000000) : const Color(0xFF000000)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isPermissionDenied ? 'RETRY' : 'SCAN AGAIN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPermissionDenied ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restartScan() async {
    setState(() {
      _error = '';
      _scanComplete = false;
      _selectedIndex = null;
      _devices = [];
    });
    await _bleService.stopScan();
    await _startScan();
  }

  Widget _buildDeviceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text(
                'Available Devices',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_devices.length} found',
                style: const TextStyle(fontSize: 13, color: Color(0xFF626262)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final device = _devices[i];
              final bars = _signalBars(device.rssi);
              final isSelected = _selectedIndex == i;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedIndex = i);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF000000)
                        : const Color(0xFFFFFFFF),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF000000)
                          : const Color(0xFFEEEEEE),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFFFFF).withValues(alpha: 0.1)
                              : const Color(0xFFF5F5F5),
                        ),
                        child: Icon(
                          Icons.router_rounded,
                          color: isSelected
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0xFF1A1C1C),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${device.ip}:${device.port}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? const Color(
                                        0xFFFFFFFF,
                                      ).withValues(alpha: 0.6)
                                    : const Color(0xFF626262),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: List.generate(
                          4,
                          (j) => Container(
                            width: 4,
                            height: j < bars ? 14 : 8,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(
                              color: j < bars
                                  ? (isSelected
                                        ? const Color(0xFFFFFFFF)
                                        : const Color(0xFF000000))
                                  : const Color(0xFFEEEEEE),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFF848484),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F9F9),
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _selectedIndex != null ? _connectSelected : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _selectedIndex != null
                      ? const Color(0xFF000000)
                      : const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'CONNECT NOW',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: _selectedIndex != null
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFF848484),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _manualSetup,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  border: Border.all(color: const Color(0xFF000000)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'MANUAL SETUP',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
