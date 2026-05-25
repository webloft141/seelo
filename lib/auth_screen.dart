import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_safe.dart';
import 'logger.dart';

class AuthService {
  final FirebaseAuth? _auth;

  AuthService() : _auth = safeAuth();

  User? get user => _auth?.currentUser;
  Stream<User?> get authState =>
      _auth?.authStateChanges() ?? const Stream.empty();

  Future<String?> signIn(String email, String password) async {
    if (_auth == null) return 'Firebase not available';
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No account found with this email';
        case 'invalid-credential':
          return 'Invalid email or password';
        case 'wrong-password':
          return 'Wrong password';
        default:
          return e.message ?? 'Login failed';
      }
    } catch (e, st) {
      logError(e, st);
      return 'Connection error. Check your internet.';
    }
  }

  Future<String?> signUp(String email, String password) async {
    if (_auth == null) return 'Firebase not available';
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Email already registered';
        case 'weak-password':
          return 'Password must be at least 6 characters';
        case 'invalid-email':
          return 'Invalid email address';
        default:
          return e.message ?? 'Registration failed';
      }
    } catch (e, st) {
      logError(e, st);
      return 'Connection error. Check your internet.';
    }
  }

  Future<void> signOut() async {
    await _auth?.signOut();
    await GoogleSignIn().signOut();
  }

  Future<String?> signInWithGoogle() async {
    if (_auth == null) return 'Firebase not available';
    try {
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      if (gUser == null) return null;
      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Google sign-in failed';
    } catch (e, st) {
      logError(e, st);
      return 'Connection error. Check your internet.';
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    if (_auth == null) return 'Firebase not available';
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Reset failed';
    } catch (e, st) {
      logError(e, st);
      return 'Connection error. Check your internet.';
    }
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: const AuthForm(),
      ),
    );
  }
}

class AuthForm extends StatefulWidget {
  final VoidCallback? onSuccess;
  const AuthForm({super.key, this.onSuccess});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm>
    with SingleTickerProviderStateMixin {
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
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Fill all fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final err = _tab.index == 0
        ? await _auth.signIn(email, pass)
        : await _auth.signUp(email, pass);
    if (mounted) {
      setState(() {
        _loading = false;
        _error = err ?? '';
      });
      if (err == null) widget.onSuccess?.call();
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final err = await _auth.signInWithGoogle();
    if (mounted) {
      setState(() {
        _loading = false;
        _error = err ?? '';
      });
      if (err == null) widget.onSuccess?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.design_services,
                size: 56,
                color: Color(0xFF000000),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seelo',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Design preview tool',
                style: TextStyle(color: Color(0xFF626262), fontSize: 14),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F3F3),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TabBar(
                        controller: _tab,
                        indicator: BoxDecoration(
                          color: const Color(0xFF000000),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: const Color(0xFFFFFFFF),
                        unselectedLabelColor: const Color(0xFF626262),
                        tabs: const [
                          Tab(
                            child: Text(
                              'Login',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Tab(
                            child: Text(
                              'Register',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: _input('Email'),
                      style: const TextStyle(color: Color(0xFF1A1C1C)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: _input('Password'),
                      style: const TextStyle(color: Color(0xFF1A1C1C)),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error,
                        style: const TextStyle(
                          color: Color(0xFFBA1A1A),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF000000),
                          foregroundColor: const Color(0xFFFFFFFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _tab.index == 0 ? 'Login' : 'Create Account',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: Color(0xFF626262),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _signInWithGoogle,
                        icon: Image.network(
                          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                          width: 20,
                          height: 20,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.g_mobiledata,
                            color: Color(0xFF1A1C1C),
                            size: 24,
                          ),
                        ),
                        label: const Text(
                          'Sign in with Google',
                          style: TextStyle(
                            color: Color(0xFF1A1C1C),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEEEEEE)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (_tab.index == 0) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          final e = _emailCtrl.text.trim();
                          if (e.isEmpty) {
                            setState(() => _error = 'Enter email first');
                            return;
                          }
                          final err = await _auth.sendPasswordReset(e);
                          setState(
                            () =>
                                _error = err ?? 'Reset link sent (if email exists)',
                          );
                        },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Color(0xFF626262),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () =>
                        _openUrl('https://seelo-relay.onrender.com/terms'),
                    child: const Text(
                      'Terms',
                      style: TextStyle(
                        color: Color(0xFF626262),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Text(
                    '\u00B7',
                    style: TextStyle(color: Color(0xFF626262), fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () =>
                        _openUrl('https://seelo-relay.onrender.com/privacy'),
                    child: const Text(
                      'Privacy',
                      style: TextStyle(
                        color: Color(0xFF626262),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUrl(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF626262)),
    filled: true,
    fillColor: const Color(0xFFFFFFFF),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF000000)),
    ),
  );
}

void showAuthSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF9F9F9),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: AuthForm(
        onSuccess: () => Navigator.of(ctx).pop(),
      ),
    ),
  );
}
