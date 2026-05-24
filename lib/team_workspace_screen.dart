import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _relayUrl = 'https://seelo-relay.onrender.com';

class TeamWorkspaceScreen extends StatefulWidget {
  final String plan;
  const TeamWorkspaceScreen({super.key, this.plan = 'free'});

  @override
  State<TeamWorkspaceScreen> createState() => _TeamWorkspaceScreenState();
}

class _TeamWorkspaceScreenState extends State<TeamWorkspaceScreen> {
  String _teamName = 'My Team';
  String _memberCount = '1';
  int _maxMembers = 1;
  List<String> _features = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTeam();
  }

  Future<void> _fetchTeam() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('$_relayUrl/api/team'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _teamName = data['teamName'] ?? 'My Team';
          _memberCount = '${data['memberCount'] ?? 1}';
          _maxMembers = data['maxMembers'] ?? 1;
          _features = List<String>.from(data['features'] ?? []);
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
        title: const Text('Team Workspace', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: isTeam ? const Color(0xFF22C55E) : const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.group, color: isTeam ? Colors.black : const Color(0xFFA6A6A6), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_teamName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('$_memberCount / $_maxMembers members', style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isTeam ? const Color(0x2222C55E) : const Color(0x22FF4757),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isTeam ? 'Active' : 'Free',
                          style: TextStyle(
                            color: isTeam ? const Color(0xFF22C55E) : const Color(0xFFFF4757),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (isTeam) ...[
                  Text('Team Features', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  if (_features.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: const Text('Team features will appear here', style: TextStyle(color: Color(0xFFA6A6A6), fontSize: 13)),
                    )
                  else
                    ...(_features.map((f) => _featureTile(Icons.check_circle, f, 'Available on your Team plan'))),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0x1E6366F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x336366F1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.rocket_launch_outlined, size: 18, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Text('Upgrade to Team', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Get unlimited devices, shared sessions, and admin controls for your entire team.', style: TextStyle(color: Color(0xFFA6A6A6), fontSize: 12)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Contact Sales', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
  }

  Widget _featureTile(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                Text(desc, style: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
