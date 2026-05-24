import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _relayUrl = 'https://seelo-relay.onrender.com';

class AnalyticsScreen extends StatefulWidget {
  final String plan;
  const AnalyticsScreen({super.key, this.plan = 'free'});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _totalSessions = 0;
  int _totalPreviews = 0;
  int _activeConnections = 0;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchAnalytics());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAnalytics({bool retried = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('$_relayUrl/api/analytics'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 401 && !retried) {
        await user.getIdToken(true);
        return _fetchAnalytics(retried: true);
      }
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _totalSessions = data['totalSessions'] ?? 0;
          _totalPreviews = data['totalPreviews'] ?? 0;
          _activeConnections = data['activeConnections'] ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeam = widget.plan.contains('team');

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161616),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
        : isTeam ? _buildAnalytics() : _buildLocked(),
    );
  }

  Widget _buildAnalytics() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session Stats', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard('Total Sessions', '$_totalSessions', Icons.bar_chart, const Color(0xFF6366F1))),
              const SizedBox(width: 10),
              Expanded(child: _statCard('Active Now', '$_activeConnections', Icons.wifi, const Color(0xFF22C55E))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _statCard('Previews Sent', '$_totalPreviews', Icons.remove_red_eye, const Color(0xFFF59E0B))),
              const SizedBox(width: 10),
              Expanded(child: _statCard('Devices', '$_activeConnections', Icons.devices, const Color(0xFFEC4899))),
            ],
          ),
          const SizedBox(height: 20),
          Text('Recent Activity', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text(
              _totalSessions > 0
                ? 'Session data is updated in real-time as you use Seelo'
                : 'No sessions yet — connect a device to get started',
              style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: const Color(0x1E6366F1), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.analytics_outlined, color: Color(0xFF6366F1), size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Analytics Locked', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Upgrade to Team plan to view usage analytics across your sessions.', style: TextStyle(color: Color(0xFFA6A6A6), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Upgrade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
        ],
      ),
    );
  }
}
