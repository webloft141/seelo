import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_safe.dart';
import 'logger.dart';

const _relayUrl = 'https://seelo-relay.onrender.com';

class DeviceManagerScreen extends StatefulWidget {
  final bool isPro;
  final int currentViewers;
  final int maxViewers;
  const DeviceManagerScreen({
    super.key,
    required this.isPro,
    required this.currentViewers,
    required this.maxViewers,
  });

  @override
  State<DeviceManagerScreen> createState() => _DeviceManagerScreenState();
}

class _DeviceManagerScreenState extends State<DeviceManagerScreen> {
  List<Map<String, dynamic>> _deviceList = [];
  int _totalViewers = 0;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  Timer? _loadingWatchdog;
  static const Duration _requestTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _loadingWatchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Taking too long to load devices. Please tap refresh.';
      });
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchDevices(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _loadingWatchdog?.cancel();
    super.dispose();
  }

  Future<void> _fetchDevices({bool retried = false}) async {
    final user = safeCurrentUser();
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in required to view connected devices.';
        });
      }
      return;
    }
    try {
      final token = await user.getIdToken().timeout(_requestTimeout);
      final res = await http
          .get(
            Uri.parse('$_relayUrl/api/devices'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_requestTimeout);
      if (res.statusCode == 401 && !retried) {
        await user.getIdToken(true);
        return _fetchDevices(retried: true);
      }
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _deviceList = List<Map<String, dynamic>>.from(data['devices'] ?? []);
          _totalViewers = data['totalDevices'] ?? 0;
          _loading = false;
          _error = null;
        });
      } else if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load device data right now.';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Server timeout. Check internet or relay server status.';
        });
      }
    } catch (e, st) {
      logError(e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Network error while loading devices.';
        });
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: const Text(
          'Device Manager',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF161616),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadingWatchdog?.cancel();
              _loadingWatchdog = Timer(const Duration(seconds: 15), () {
                if (!mounted || !_loading) return;
                setState(() {
                  _loading = false;
                  _error = 'Taking too long to load devices. Please try again.';
                });
              });
              _fetchDevices();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6366F1),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.devices,
                          color: Color(0xFF6366F1),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Devices',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_totalViewers / ${widget.maxViewers} used',
                              style: const TextStyle(
                                color: Color(0xFFA6A6A6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _totalViewers < widget.maxViewers
                                ? const Color(0x2222C55E)
                                : const Color(0x22FF4757),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _totalViewers < widget.maxViewers
                                ? 'Available'
                                : 'Full',
                            style: TextStyle(
                              color: _totalViewers < widget.maxViewers
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFFF4757),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Connected Devices',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFA6A6A6),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_deviceList.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Text(
                        'No laptop/desktop connected',
                        style: const TextStyle(
                          color: Color(0xFFA6A6A6),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _deviceList.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final d = _deviceList[i];
                          final viewers = d['viewerCount'] ?? 0;
                          final desktopConnected =
                              d['desktopConnected'] == true;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161616),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF2C2C2C),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  desktopConnected
                                      ? Icons.laptop_mac
                                      : Icons.desktop_windows_outlined,
                                  color: desktopConnected
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFA6A6A6),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        desktopConnected
                                            ? 'Laptop/Desktop connected'
                                            : 'Desktop disconnected',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$viewers mobile viewer(s)',
                                        style: const TextStyle(
                                          color: Color(0xFFA6A6A6),
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        'Session: ${(d['sessionId'] as String?)?.substring(0, 8) ?? '?'}...',
                                        style: const TextStyle(
                                          color: Color(0xFFA6A6A6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: desktopConnected
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFFF8A00),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Spacer(),
                  if (!widget.isPro)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x1E6366F1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x336366F1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Color(0xFF6366F1),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Upgrade to Pro for multi-device support',
                              style: TextStyle(
                                color: Color(0xFFA6A6A6),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
