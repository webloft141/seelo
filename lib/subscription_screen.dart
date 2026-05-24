import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'premium.dart';
import 'device_manager_screen.dart';
import 'team_workspace_screen.dart';
import 'analytics_screen.dart';

const _relayUrl = 'https://seelo-relay.onrender.com';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _currentPlan = 'free';
  String? _expiresAt;
  bool _loading = true;
  bool _activating = false;
  bool _cancelling = false;
  final _keyController = TextEditingController();
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) => _loadPlan());
    _loadPlan();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadPlan() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _currentPlan = 'free'; _expiresAt = null; _loading = false; });
      return;
    }
    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('$_relayUrl/api/user'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _currentPlan = data['plan'] ?? 'free';
          _expiresAt = data['expiresAt'];
        });
        PremiumManager.setPlanFromString(_currentPlan);
      } else {
        setState(() => _currentPlan = 'free');
        PremiumManager.setPlan(Plan.free);
        _showSnack('Could not load plan — server unreachable');
      }
    } catch (e) {
      if (_loading) setState(() => _currentPlan = 'free');
      _showSnack('Network error — check your connection');
    }
    setState(() => _loading = false);
  }

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;
  bool get _isOnPaidPlan => _currentPlan.contains('pro') || _currentPlan.contains('team');
  String get _userEmail => FirebaseAuth.instance.currentUser?.email ?? 'Not signed in';

  Future<void> _activateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) { _showSnack('Enter a license key'); return; }
    if (!_isLoggedIn) { _showSnack('Please sign in first'); return; }

    setState(() => _activating = true);
    final user = FirebaseAuth.instance.currentUser!;
    final token = await user.getIdToken();

    try {
      final res = await http.post(
        Uri.parse('$_relayUrl/api/activate-key'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'key': key}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await _loadPlan();
        _keyController.clear();
        _showSnack('Activated ${_planName(data['plan'])}!');
      } else {
        _showSnack(data['error'] ?? 'Invalid key');
      }
    } catch (e) {
      _showSnack('Activation failed — check connection');
    }
    setState(() => _activating = false);
  }

  Future<void> _cancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1B23),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Subscription?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('You will lose Pro/Team features immediately. Current plan access will end now.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Plan', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      await http.post(
        Uri.parse('$_relayUrl/api/cancel-subscription'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await _loadPlan();
      _showSnack('Plan cancelled');
    } catch (_) {
      _showSnack('Failed to cancel');
    }
    setState(() => _cancelling = false);
  }

  String _planName(String planId) {
    if (planId.contains('team')) return 'Team';
    if (planId.contains('pro')) return 'Pro';
    return 'Free';
  }

  Color _planColor(String planId) {
    if (planId.contains('team')) return const Color(0xFF22C55E);
    if (planId.contains('pro')) return const Color(0xFF6366F1);
    return const Color(0xFF94A3B8);
  }

  String _planDeviceCount(String planId) {
    if (planId.contains('team')) return 'Unlimited';
    if (planId.contains('pro')) return '5 devices';
    return '1 device';
  }

  int _planMaxViewers(String planId) {
    if (planId.contains('team')) return 999;
    if (planId.contains('pro')) return 5;
    return 1;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1A1B23)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050508),
        title: const Text('Plans', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _planColor(_currentPlan).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _planName(_currentPlan).toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _planColor(_currentPlan)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? _buildSkeleton()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildUserCard(),
                const SizedBox(height: 20),
                if (_isOnPaidPlan) _buildCurrentPlanCard(),
                if (_isOnPaidPlan) const SizedBox(height: 16),
                _buildKeyEntryCard(),
                const SizedBox(height: 20),
                _buildPlanCard('pro'),
                const SizedBox(height: 12),
                _buildPlanCard('team'),
                if (_isOnPaidPlan) ...[
                  const SizedBox(height: 20),
                  _buildCancelButton(),
                ],
                const SizedBox(height: 28),
                const Text('Feature Comparison', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _buildComparisonTable(),
                if (_currentPlan.contains('team')) ...[
                  const SizedBox(height: 20),
                  const Text('Team Features', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _featureButton(Icons.group, 'Team Workspace', () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamWorkspaceScreen(plan: _currentPlan)))),
                  const SizedBox(height: 8),
                  _featureButton(Icons.analytics, 'Analytics', () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnalyticsScreen(plan: _currentPlan)))),
                  const SizedBox(height: 8),
                  _featureButton(Icons.devices, 'Device Manager', () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceManagerScreen(isPro: _isOnPaidPlan, currentViewers: 0, maxViewers: _planMaxViewers(_currentPlan))))),
                ] else ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0D12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E1F28)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.devices, color: const Color(0xFF6366F1), size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Multi-device, Team Workspace, Analytics & Device Manager are available on Pro/Team', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(4, (_) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D2E3A))),
      )),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1F28)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF6366F1), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userEmail, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Current plan: ${_planName(_currentPlan)}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyEntryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1F28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key_rounded, size: 18, color: const Color(0xFF6366F1).withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              const Text('Activate License Key', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Enter the key you received from Seelo to unlock Pro or Team features.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: 'SEELO-XXXXXXXX-XXXXXXXX',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13, letterSpacing: 1),
              filled: true,
              fillColor: const Color(0xFF050508),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1E1F28)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1E1F28)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF6366F1)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _activating ? null : _activateKey,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1E1F28),
                disabledForegroundColor: const Color(0xFF64748B),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _activating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Activate', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
    final isTeam = _currentPlan.contains('team');
    final color = isTeam ? const Color(0xFF22C55E) : const Color(0xFF6366F1);
    final planLabel = isTeam ? 'Team' : 'Pro';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.08), const Color(0xFF0C0D12)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text('ACTIVE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('$planLabel Plan', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (_expiresAt != null) ...[
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('Expires: ${_formatDate(_expiresAt!)}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              const Icon(Icons.devices_rounded, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(_planDeviceCount(_currentPlan), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String base) {
    final isCurrent = _currentPlan.startsWith(base) && base != 'free';
    final planColor = _planColor(base);
    final devices = _planDeviceCount(base);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCurrent ? planColor : const Color(0xFF1E1F28), width: isCurrent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: planColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(base == 'team' ? 'TEAM' : 'PRO', style: TextStyle(color: planColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: planColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text('CURRENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: planColor)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('License Key', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$devices — contact Seelo to purchase', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    if (_cancelling) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)));
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _cancelSubscription,
        icon: const Icon(Icons.cancel_outlined, size: 16),
        label: const Text('Cancel Subscription'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEF4444),
          side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildComparisonTable() {
    final allFeatures = [
      ('QR Preview', true, true, true),
      ('Fullscreen Preview', true, true, true),
      ('Active Devices', '1', '5', 'Unlimited'),
      ('Overflow Detection', true, true, true),
      ('Safe Area Overlay', true, true, true),
      ('Grid Overlay', true, true, true),
      ('Hide/Show Bars', true, true, true),
      ('Overlay Compare', false, true, true),
      ('Smart Validation', false, true, true),
      ('Rulers & Measurements', false, true, true),
      ('Screenshot Export', false, true, true),
      ('Session History', false, true, true),
      ('Multi-device', false, true, true),
      ('Custom Device Presets', false, true, true),
      ('Landscape Mode', false, true, true),
      ('Tablet Support', false, true, true),
      ('Team Workspace', false, false, true),
      ('Analytics', false, false, true),
      ('Device Manager', false, false, true),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1F28)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.5),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF0C0D12)),
              children: [
                _tableCell('Feature', isHeader: true),
                _tableCell('Free', isHeader: true, color: const Color(0xFF666666)),
                _tableCell('Pro', isHeader: true, color: const Color(0xFF6366F1)),
                _tableCell('Team', isHeader: true, color: const Color(0xFF22C55E)),
              ],
            ),
            ...allFeatures.asMap().entries.map((entry) {
              final i = entry.key;
              final f = entry.value;
              final isEven = i.isEven;
              return TableRow(
                decoration: BoxDecoration(
                  color: isEven ? const Color(0xFF08080D) : const Color(0xFF0C0D12),
                ),
                children: [
                  _tableCell(f.$1),
                  _tableCell(_formatCell(f.$2)),
                  _tableCell(_formatCell(f.$3)),
                  _tableCell(_formatCell(f.$4)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: isHeader
          ? Text(text, style: TextStyle(color: color ?? Colors.white, fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)
          : Text(text, style: TextStyle(
              color: text == '✓'
                  ? const Color(0xFF22C55E)
                  : text == '—'
                      ? const Color(0xFF64748B)
                      : const Color(0xFFD1D5DB),
              fontSize: 11,
            ), textAlign: TextAlign.center),
    );
  }

  String _formatCell(dynamic val) {
    if (val == true) return '✓';
    if (val == false) return '—';
    return val.toString();
  }

  Widget _featureButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFF0C0D12),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF1E1F28)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF22C55E)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
