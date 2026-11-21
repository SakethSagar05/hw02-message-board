import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../firebase_options.dart';
import 'auth_gate.dart';

/// Shows while Firebase initializes, then hands over to the AuthGate.
/// A failure shows a Retry button instead of a blank screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Kept outside build() so rebuilds never restart initialization.
  late Future<void> _initialization;
  static bool _emulatorsConnected = false;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([
      _initFirebase(),
      // Keep the splash up long enough to be seen (and screenshotted).
      Future<void>.delayed(const Duration(milliseconds: 1400)),
    ]);
  }

  Future<void> _initFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (useEmulator && !_emulatorsConnected) {
      // Must happen once, before any Auth or Firestore request.
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      _emulatorsConnected = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SplashFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Firebase could not start. Check your connection and setup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() => _initialization = _initialize());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashFrame(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFFFC58A),
              ),
            ),
          );
        }
        return const AuthGate();
      },
    );
  }
}

class _SplashFrame extends StatelessWidget {
  const _SplashFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B2416), Color(0xFF8A4B22), Color(0xFFD9772B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: const Color(0xFFFFC58A), width: 2),
                  ),
                  child: const Icon(Icons.forum_rounded,
                      size: 64, color: Color(0xFFFFE3C4)),
                ),
                const SizedBox(height: 28),
                const Text(
                  appName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chatboards for the new age',
                  style: TextStyle(color: Color(0xFFFFE3C4), fontSize: 16),
                ),
                const SizedBox(height: 40),
                child,
                const SizedBox(height: 40),
                Text(
                  useEmulator
                      ? 'HW-02 · CSC 4360 · EMULATOR MODE'
                      : 'HW-02 · CSC 4360',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
