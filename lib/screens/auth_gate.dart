import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'profile_gate.dart';

/// Routes by auth state: signed-out users see the sign-in/registration
/// screen, signed-in users go through ProfileGate to the board.
/// This is UX routing only; the Firestore rules are the real security.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  String? _lastUid;
  bool _first = true;

  /// When the signed-in user changes, close any screen pushed on top
  /// (for example the Rules Lab) so nobody is left on a stale page.
  void _onUserChanged(String? uid) {
    if (_first) {
      _first = false;
      _lastUid = uid;
      return;
    }
    if (uid == _lastUid) return;
    _lastUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authState,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Cannot read sign-in state. Restart and retry.'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        _onUserChanged(user?.uid);
        if (user == null) return AuthScreen(auth: _auth);
        return ProfileGate(key: ValueKey(user.uid), user: user, auth: _auth);
      },
    );
  }
}
