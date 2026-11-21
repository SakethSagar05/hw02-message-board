/// Form validators shared by the screens. They mirror the security rules
/// (rules are still the real gate; these give fast, friendly feedback).
class Validators {
  Validators._();

  static const int maxMessageLength = 500;
  static const int maxNameLength = 50;
  static const int minPasswordLength = 6;

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _name = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ' .-]+$");

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email.';
    if (!_email.hasMatch(v)) return 'Enter a valid email, like ada@example.com.';
    return null;
  }

  /// Sign-in only needs a non-empty password; registration applies the policy.
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a password.';
    if (v.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  static String? name(String? value, {String label = 'name'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your $label.';
    if (v.length > maxNameLength) return 'Keep it under $maxNameLength characters.';
    if (!_name.hasMatch(v)) return 'Use letters, spaces, apostrophes or hyphens.';
    return null;
  }

  static String? message(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Write something first.';
    if (v.length > maxMessageLength) {
      return 'Keep messages under $maxMessageLength characters (${v.length} now).';
    }
    return null;
  }
}
