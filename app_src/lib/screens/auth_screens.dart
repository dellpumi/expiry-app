import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../exit_guard.dart';
import '../firestore_paths.dart';
import '../net.dart';
import '../strings.dart';
import '../validators.dart';

final _auth = FirebaseAuth.instance;

String _msg(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'email-already-in-use': return S.authInUse;
      case 'wrong-password': case 'invalid-credential': case 'user-not-found': case 'invalid-email': return S.authWrong;
      case 'too-many-requests': return S.authMany;
      case 'network-request-failed': return S.net;
    }
  }
  return S.generic;
}

Widget _page(String title, List<Widget> kids, {bool back = true}) => Scaffold(
    appBar: AppBar(title: Text(title), automaticallyImplyLeading: back),
    body: ListView(padding: const EdgeInsets.all(16), children: kids));

Future<void> askLogout(BuildContext c) async {
  final ok = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(title: const Text('Log out'), content: const Text('Do you want to log out?'), actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
          ]));
  if (ok == true) await _auth.signOut();
}

/// Creates users/{uid} if missing (spec §5 ensureUserDoc).
Future<void> ensureUserDoc(User u) async {
  final ref = FirebaseFirestore.instance.doc(P.user(u.uid));
  if ((await ref.get()).exists) return;
  await ref.set({'email': u.email!.toLowerCase(), 'displayName': u.displayName ?? '', 'defaultListId': null, 'createdAt': FieldValue.serverTimestamp()});
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});
  Future<void> _go(BuildContext c, String m) async {
    if (!await requireOnline(c) || !c.mounted) return;
    Navigator.push(c, MaterialPageRoute(builder: (_) => AuthForm(mode: m)));
  }
  @override
  Widget build(BuildContext c) => ExitGuard(child: _page('Inventory & Shopping', [
        FilledButton(onPressed: () => _go(c, 'register'), child: const Text('Register')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _go(c, 'login'), child: const Text('Login')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _go(c, 'forgot'), child: const Text('Forgotten password')),
      ], back: false));
}

class AuthForm extends StatefulWidget {
  final String mode; // register | login | forgot
  const AuthForm({super.key, required this.mode});
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _e = TextEditingController(), _p = TextEditingController(), _p2 = TextEditingController(), _n = TextEditingController();
  String _err = '';
  bool _busy = false;

  Future<void> _submit() async {
    final m = widget.mode, e = _e.text.trim().toLowerCase(), p = _p.text, n = normName(_n.text);
    String? v = checkEmail(e);
    if (v == null && m == 'register') {
      v = checkPassword(p) ?? (p != _p2.text ? S.pwMismatch : null) ?? ((n.isEmpty || n.length > 15) ? S.vdn : null);
    }
    if (v == null && m == 'login' && p.isEmpty) v = S.enterPw;
    if (v != null) return setState(() => _err = v!);
    setState(() { _busy = true; _err = ''; });
    try {
      if (m == 'register') {
        final cred = await _auth.createUserWithEmailAndPassword(email: e, password: p);
        await cred.user!.updateDisplayName(n);
        await cred.user!.sendEmailVerification();
      } else if (m == 'login') {
        await _auth.signInWithEmailAndPassword(email: e, password: p);
      } else {
        try { await _auth.sendPasswordResetEmail(email: e); } on FirebaseAuthException catch (x) { if (x.code != 'user-not-found') rethrow; }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.resetSent), duration: Duration(seconds: 7)));
        await Future.delayed(const Duration(seconds: 7));
      }
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (x) {
      if (mounted) setState(() { _busy = false; _err = _msg(x); });
    }
  }

  @override
  Widget build(BuildContext c) {
    final m = widget.mode;
    return _page(m == 'register' ? 'Register' : m == 'login' ? 'Login' : 'Forgotten password', [
      TextField(controller: _e, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail address')),
      if (m != 'forgot') TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      if (m == 'register') TextField(controller: _p2, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
      if (m == 'register') TextField(controller: _n, decoration: const InputDecoration(labelText: 'Your display name')),
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_err, style: const TextStyle(color: Colors.redAccent))),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Please wait…' : m == 'register' ? 'Register and login' : m == 'login' ? 'Login' : 'Send password recovery link')),
      OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
    ]);
  }
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyState();
}

class _VerifyState extends State<VerifyScreen> {
  Timer? _t;
  String _err = '';
  int _cd = 0;
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds: 5), (_) => _check(false)); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _check(bool manual) async {
    if (manual && !await requireOnline(context)) return;
    try {
      await _auth.currentUser?.reload();
      await _auth.currentUser?.getIdToken(true); // rules read email_verified from the token
      if (_auth.currentUser?.emailVerified != true && manual && mounted) setState(() => _err = S.verifyNot);
    } catch (_) { if (manual && mounted) setState(() => _err = S.net); }
  }

  Future<void> _resend() async {
    if (_cd > 0 || !await requireOnline(context)) return;
    try { await _auth.currentUser?.sendEmailVerification(); } catch (_) {}
    setState(() => _cd = 60);
    Timer.periodic(const Duration(seconds: 1), (t) { if (!mounted || _cd == 0) { t.cancel(); return; } setState(() => _cd--); });
  }

  @override
  Widget build(BuildContext c) => ExitGuard(child: _page('Verify email', [
        Text('We sent a verification email to ${_auth.currentUser?.email}. Open the link in it, then come back. Check your spam folder.'),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_err, style: const TextStyle(color: Colors.redAccent))),
        FilledButton(onPressed: () => _check(true), child: const Text("I've verified")),
        OutlinedButton(onPressed: _cd > 0 ? null : _resend, child: Text(_cd > 0 ? 'Resend email (${_cd}s)' : 'Resend email')),
        OutlinedButton(onPressed: () => askLogout(c), child: const Text('Log out')),
      ], back: false));
}
