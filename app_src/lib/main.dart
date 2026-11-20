import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'firebase_options_web.dart';
import 'prefs.dart';
import 'reminders.dart';
import 'firebase_options.dart';
import 'screens/auth_screens.dart';
import 'screens/hub_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: kIsWeb ? WebFirebaseOptions.options : DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: !kIsWeb, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  await loadPrefs();
  runApp(const App());
}

final navKey = GlobalKey<NavigatorState>();

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Expiry tracker & shopping list',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5E3A), brightness: Brightness.dark), useMaterial3: true),
        navigatorKey: navKey,
        builder: (c, w) => ValueListenableBuilder<double>(valueListenable: fontScale, builder: (c, v, _) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(v)), child: w!)),
        home: const SessionWatcher(child: Gate()),
      );
}

/// Logs this device out when the password was changed or the account was deleted on another device.
class SessionWatcher extends StatefulWidget {
  final Widget child;
  const SessionWatcher({super.key, required this.child});
  @override
  State<SessionWatcher> createState() => _SwState();
}

class _SwState extends State<SessionWatcher> with WidgetsBindingObserver {
  Timer? _t;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _t = Timer.periodic(const Duration(minutes: 2), (_) => _check()); }
  @override
  void dispose() { _t?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) _check(); }
  Future<void> _check() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try { await u.reload(); await u.getIdToken(true); }
    on FirebaseAuthException catch (e) {
      if (const ['user-token-expired', 'user-not-found', 'user-disabled', 'invalid-user-token'].contains(e.code)) {
        await FirebaseAuth.instance.signOut();
        navKey.currentState?.popUntil((r) => r.isFirst);
      }
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Decides the screen from the auth state: S1 / S5 / S6.
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (c, s) {
          final u = s.data ?? FirebaseAuth.instance.currentUser;
          if (u == null) Reminders.stop();
          if (u == null) return s.connectionState == ConnectionState.waiting ? const Scaffold(body: Center(child: CircularProgressIndicator())) : const StartScreen();
          if (!u.emailVerified) return const VerifyScreen();
          return const HubScreen();
        },
      );
}
