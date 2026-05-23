import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get user => _auth.currentUser;
  Stream<User?> get authState => _auth.authStateChanges();

  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found': return 'No account found with this email';
        case 'invalid-credential': return 'Invalid email or password';
        case 'wrong-password': return 'Wrong password';
        default: return e.message ?? 'Login failed';
      }
    } catch (_) {
      return 'Connection error. Check your internet.';
    }
  }

  Future<String?> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use': return 'Email already registered';
        case 'weak-password': return 'Password must be at least 6 characters';
        case 'invalid-email': return 'Invalid email address';
        default: return e.message ?? 'Registration failed';
      }
    } catch (_) {
      return 'Connection error. Check your internet.';
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Reset failed';
    } catch (_) {
      return 'Connection error. Check your internet.';
    }
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  late final TabController _tab;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _error = ''));
  }

  @override
  void dispose() {
    _tab.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) { setState(() => _error = 'Fill all fields'); return; }
    setState(() { _loading = true; _error = ''; });
    final err = _tab.index == 0
        ? await _auth.signIn(email, pass)
        : await _auth.signUp(email, pass);
    if (mounted) setState(() { _loading = false; _error = err ?? ''; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.design_services, size: 56, color: Colors.white),
                const SizedBox(height: 8),
                const Text('Seelo', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Design preview tool', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                const SizedBox(height: 48),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: const Color(0xFF888888),
                    tabs: const [
                      Tab(child: Text('Login', style: TextStyle(fontWeight: FontWeight.w600))),
                      Tab(child: Text('Register', style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _input('Email'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: _input('Password'),
                  style: const TextStyle(color: Colors.white),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: const TextStyle(color: Color(0xFFFF4757), fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_tab.index == 0 ? 'Login' : 'Create Account', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                if (_tab.index == 0) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      final e = _emailCtrl.text.trim();
                      if (e.isEmpty) { setState(() => _error = 'Enter email first'); return; }
                      final err = await _auth.sendPasswordReset(e);
                      setState(() => _error = err ?? 'Reset link sent (if email exists)');
                    },
                    child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF888888)),
    filled: true,
    fillColor: const Color(0xFF1C1C1E),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
  );
}
