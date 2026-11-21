/// What services throw to widgets: a safe, human message plus the original
/// Firebase error code (kept for evidence and tests, never shown raw alone).
class AppException implements Exception {
  const AppException(this.message, {this.code = 'unknown'});

  final String message;
  final String code;

  bool get isPermissionDenied => code == 'permission-denied';

  @override
  String toString() => message;
}

/// Firebase Auth error codes -> helpful text. Never show raw exception text.
String friendlyAuthError(String code) {
  switch (code) {
    case 'invalid-email':
      return 'That email address is not valid.';
    case 'weak-password':
      return 'That password is too weak. Use at least 6 characters.';
    case 'email-already-in-use':
      return 'An account already exists for that email. Sign in instead.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
    case 'INVALID_LOGIN_CREDENTIALS':
      return 'Email or password is incorrect.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a minute and try again.';
    case 'network-request-failed':
      return 'Check your connection and try again.';
    case 'operation-not-allowed':
      return 'Email/Password sign-in is not enabled for this Firebase project.';
    default:
      return 'Something went wrong ($code). Try again.';
  }
}

/// Firestore error codes -> helpful text.
String friendlyFirestoreError(String code) {
  switch (code) {
    case 'permission-denied':
      return 'Not allowed: the database rules blocked this action.';
    case 'unavailable':
      return 'You appear to be offline. Try again when connected.';
    case 'deadline-exceeded':
      return 'The server took too long. Try again.';
    case 'not-found':
      return 'That message no longer exists.';
    case 'failed-precondition':
      return 'The database is not ready for this query yet.';
    case 'unauthenticated':
      return 'Sign in first.';
    default:
      return 'Something went wrong ($code). Try again.';
  }
}
