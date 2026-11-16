import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/auth_screens.dart';
import 'screens/hub_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Inventory & Shopping',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5E3A), brightness: Brightness.dark), useMaterial3: true),
        home: const Gate(),
      );
}

/// Decides the screen from the auth state: S1 / S5 / S6.
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (c, s) {
          final u = s.data ?? FirebaseAuth.instance.currentUser;
          if (u == null) return s.connectionState == ConnectionState.waiting ? const Scaffold(body: Center(child: CircularProgressIndicator())) : const StartScreen();
          if (!u.emailVerified) return const VerifyScreen();
          return const HubScreen();
        },
      );
}
