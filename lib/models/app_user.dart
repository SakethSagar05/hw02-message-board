/// Roles are descriptive profile data only. They never grant access: the
/// security rules check uid ownership, not role.
const List<String> userRoles = ['student', 'instructor', 'guest'];

/// The private `users/{uid}` record required by the assignment.
class AppUser {
  const AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.registrationDateTime,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final String role;

  /// Null only while the server timestamp is pending.
  final DateTime? registrationDateTime;

  String get displayName => '$firstName $lastName'.trim();

  /// All five required fields are present and the timestamp has resolved.
  bool get isComplete =>
      uid.isNotEmpty &&
      firstName.isNotEmpty &&
      lastName.isNotEmpty &&
      role.isNotEmpty &&
      registrationDateTime != null;

  factory AppUser.fromMap(
    Map<String, dynamic> data, {
    required DateTime? Function(Object? value) toDate,
  }) {
    return AppUser(
      uid: (data['uid'] as String?) ?? '',
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      role: (data['role'] as String?) ?? '',
      registrationDateTime: toDate(data['registrationDateTime']),
    );
  }
}

/// Profile fields typed on the registration form, kept in memory until the
/// signed-in ProfileGate writes them (see UserService.stashDraft).
class ProfileDraft {
  const ProfileDraft({
    required this.firstName,
    required this.lastName,
    required this.role,
  });

  final String firstName;
  final String lastName;
  final String role;
}
