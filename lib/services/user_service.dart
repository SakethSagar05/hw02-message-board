import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'app_exception.dart';

/// The private users/{uid} record. Written once, by the client, when the
/// account is created; read only by its owner (see firestore.rules).
class UserRecordSnapshot {
  const UserRecordSnapshot({required this.record, required this.pending});

  /// Null when the document does not exist.
  final AppUser? record;

  /// True while a local write has not been confirmed by the server.
  final bool pending;

  bool get isReady => record != null && record!.isComplete && !pending;
}

class UserService {
  UserService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  /// Registration signs the user in before the profile write can run, and
  /// the auth gate replaces the registration form at that moment. The form
  /// therefore leaves its fields here, keyed by email, and ProfileGate (which
  /// stays mounted) performs the write.
  static final Map<String, ProfileDraft> _drafts = {};

  static void stashDraft(String email, ProfileDraft draft) =>
      _drafts[email.trim().toLowerCase()] = draft;

  static void discardDraft(String email) =>
      _drafts.remove(email.trim().toLowerCase());

  static ProfileDraft? takeDraft(String? email) =>
      email == null ? null : _drafts.remove(email.trim().toLowerCase());

  Stream<UserRecordSnapshot> watchRecord(String uid) {
    return _doc(uid).snapshots(includeMetadataChanges: true).map((snap) {
      final data = snap.data();
      return UserRecordSnapshot(
        record: data == null ? null : AppUser.fromMap(data, toDate: _toDate),
        pending: snap.metadata.hasPendingWrites,
      );
    });
  }

  /// Creates users/{uid} with exactly the five required fields. Called only
  /// when the record is missing, never on every login (that would reset the
  /// registration timestamp, and the rules would reject it anyway).
  Future<void> saveUserRecord({
    required String uid,
    required ProfileDraft draft,
  }) async {
    try {
      await _doc(uid).set({
        'uid': uid,
        'firstName': draft.firstName.trim(),
        'lastName': draft.lastName.trim(),
        'role': draft.role,
        'registrationDateTime': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AppException(
        'Account created, profile not saved. ${friendlyFirestoreError(e.code)}',
        code: e.code,
      );
    }
  }

  static DateTime? _toDate(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}
