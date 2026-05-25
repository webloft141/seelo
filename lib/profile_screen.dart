import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_safe.dart';
import 'auth_screen.dart';
import 'premium.dart';
import 'subscription_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  Plan _plan = Plan.free;

  @override
  void initState() {
    super.initState();
    _user = safeCurrentUser();
    _plan = PremiumManager.plan;
    PremiumManager.planNotifier.addListener(_onPlanChanged);
  }

  @override
  void dispose() {
    PremiumManager.planNotifier.removeListener(_onPlanChanged);
    super.dispose();
  }

  void _onPlanChanged() {
    if (mounted) setState(() => _plan = PremiumManager.plan);
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
  }

  String get _planLabel {
    switch (_plan) {
      case Plan.pro:
        return 'Pro';
      case Plan.team:
        return 'Team';
      default:
        return 'Free';
    }
  }

  Color get _planColor {
    switch (_plan) {
      case Plan.pro:
        return const Color(0xFF000000);
      case Plan.team:
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF626262);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9F9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1C1C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFF1A1C1C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFFEEEEEE),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF1A1C1C),
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _user?.displayName ?? 'User',
              style: const TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_user?.email != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                _user!.email!,
                style: const TextStyle(
                  color: Color(0xFF626262),
                  fontSize: 14,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildInfoCard(),
          const SizedBox(height: 12),
          _buildPlanCard(),
          const SizedBox(height: 12),
          _buildSignOutButton(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account Info',
            style: TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.email_outlined, 'Email', _user?.email ?? '--'),
          const SizedBox(height: 12),
          _infoRow(Icons.person_outline, 'Name', _user?.displayName ?? '--'),
          const SizedBox(height: 12),
          _infoRow(Icons.tag, 'User ID', _user?.uid ?? '--'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF626262)),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF626262),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                size: 18,
                color: Color(0xFF1A1C1C),
              ),
              const SizedBox(width: 8),
              const Text(
                'Plan',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _planColor.withValues(alpha: 0.08),
                  border: Border.all(color: _planColor.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _planLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _planColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF3F3F3),
                foregroundColor: const Color(0xFF1A1C1C),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Manage Plans',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout, size: 16),
        label: const Text('Sign Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFBA1A1A),
          side: const BorderSide(color: Color(0xFFFFDAD6)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
