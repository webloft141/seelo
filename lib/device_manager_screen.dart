import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchDevices());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('$_relayUrl/api/devices'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _deviceList = List<Map<String, dynamic>>.from(data['devices'] ?? []);
          _totalViewers = data['totalDevices'] ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: const Text('Device Manager', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161616),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
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
                      const Icon(Icons.devices, color: Color(0xFF6366F1), size: 24),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active Devices', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('$_totalViewers / ${widget.maxViewers} used', style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _totalViewers < widget.maxViewers ? const Color(0x2222C55E) : const Color(0x22FF4757),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _totalViewers < widget.maxViewers ? 'Available' : 'Full',
                          style: TextStyle(
                            color: _totalViewers < widget.maxViewers ? const Color(0xFF22C55E) : const Color(0xFFFF4757),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Connected Viewers', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_deviceList.isEmpty || _totalViewers == 0)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      _totalViewers > 0
                        ? '$_totalViewers viewer(s) connected'
                        : 'No viewers connected',
                      style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 13),
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
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161616),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2C2C2C)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.phone_android, color: Color(0xFFA6A6A6), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${d['viewerCount'] ?? 0} viewer(s)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    Text('Session: ${(d['sessionId'] as String?)?.substring(0, 8) ?? '?'}...', style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF22C55E)),
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
                        Icon(Icons.lock_outline, size: 16, color: Color(0xFF6366F1)),
                        SizedBox(width: 8),
                        Expanded(child: Text('Upgrade to Pro for multi-device support', style: TextStyle(color: Color(0xFFA6A6A6), fontSize: 12))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}
