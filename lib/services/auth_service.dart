import 'package:firebase_auth/firebase_auth.dart';

import 'app_exception.dart';

/// Every Firebase Authentication call in the app lives here.
/// Construct it only after Firebase.initializeApp() has finished.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// One stable stream, created once, so rebuilds never resubscribe.
  late final Stream<User?> authState = _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User> register({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AppException(
          'Registration did not return a user. Try signing in.',
          code: 'no-user',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AppException(friendlyAuthError(e.code), code: e.code);
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AppException(friendlyAuthError(e.code), code: e.code);
    }
  }

  Future<void> signOut() => _auth.signOut();
}
