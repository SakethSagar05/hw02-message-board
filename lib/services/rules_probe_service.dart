import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import 'board_service.dart';

/// Outcome of one deliberate rules probe.
class ProbeOutcome {
  const ProbeOutcome({required this.allowed, required this.code, this.detail = ''});

  final bool allowed;

  /// 'ok' when the write/read went through, otherwise the Firestore code,
  /// for example 'permission-denied'.
  final String code;
  final String detail;
}

/// Calls that deliberately bypass the UI's own checks, so the Rules Lab
/// screen can show that the DATABASE (not hidden buttons) denies them.
/// Every probe goes to the server; nothing is answered from the cache.
class RulesProbeService {
  RulesProbeService({FirebaseFirestore? db, BoardService? board})
      : _db = db ?? FirebaseFirestore.instance,
        _board = board ?? BoardService(db: db);

  final FirebaseFirestore _db;
  final BoardService _board;

  static const _server = GetOptions(source: Source.server);

  CollectionReference<Map<String, dynamic>> get _messages =>
      _db.collection('messages');

  Future<ProbeOutcome> _probe(Future<void> Function() op) async {
    try {
      await op();
      return const ProbeOutcome(allowed: true, code: 'ok');
    } on FirebaseException catch (e) {
      return ProbeOutcome(allowed: false, code: e.code, detail: e.message ?? '');
    }
  }

  /// Run while signed out: read the board straight from the server.
  Future<ProbeOutcome> signedOutRead() =>
      _probe(() => _messages.limit(1).get(_server));

  /// The newest message written by somebody other than [myUid], if any.
  Future<Message?> findOtherAuthorsMessage(String myUid) async {
    final snap = await _messages
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get(_server);
    for (final d in snap.docs) {
      if (d.data()['authorUid'] != myUid) {
        return Message.fromMap(d.id, d.data(), toDate: BoardService.toDate);
      }
    }
    return null;
  }

  /// The newest message written by [myUid], if any.
  Future<Message?> findMyMessage(String myUid) async {
    final snap = await _messages
        .where('authorUid', isEqualTo: myUid)
        .limit(1)
        .get(_server);
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return Message.fromMap(d.id, d.data(), toDate: BoardService.toDate);
  }

  Future<ProbeOutcome> crossUserEdit(String messageId) => _probe(() => _messages
      .doc(messageId)
      .update({'text': 'Edited by an intruder', 'editedAt': FieldValue.serverTimestamp()}));

  Future<ProbeOutcome> crossUserDelete(String messageId) =>
      _probe(() => _messages.doc(messageId).delete());

  /// Create a message that claims somebody else wrote it.
  Future<ProbeOutcome> forgedAuthorCreate() => _probe(() => _messages.doc().set({
        'text': 'Forged message',
        'authorUid': 'someone-else-uid',
        'authorName': 'Forged Name',
        'createdAt': FieldValue.serverTimestamp(),
      }));

  /// The owner tries to hand their own message to another uid.
  Future<ProbeOutcome> changeOwner(String myMessageId) => _probe(() => _messages
      .doc(myMessageId)
      .update({'authorUid': 'someone-else-uid'}));

  /// Create with a device clock instead of the server timestamp.
  Future<ProbeOutcome> deviceClockCreate(String myUid, String myName) =>
      _probe(() => _messages.doc().set({
            'text': 'Back-dated message',
            'authorUid': myUid,
            'authorName': myName,
            'createdAt': Timestamp.fromDate(DateTime(2001, 1, 1)),
          }));

  /// Read another user's private users/{uid} record.
  Future<ProbeOutcome> readOtherUserRecord(String otherUid) =>
      _probe(() => _db.collection('users').doc(otherUid).get(_server));

  /// Double submit: call postMessage twice at once with the same draft id,
  /// then count how many documents hold that unique text.
  Future<({List<PostResult> results, int documents})> doubleSubmit({
    required String uid,
    required String name,
  }) async {
    final id = _board.newMessageId();
    final text = 'Double-submit test ${DateTime.now().millisecondsSinceEpoch}';
    Future<PostResult> post() => _board.postMessage(
        messageId: id, authorUid: uid, authorName: name, text: text);
    final results = await Future.wait([post(), post()]);
    final again = await post(); // a later retry of the same draft
    final copies =
        await _messages.where('text', isEqualTo: text).get(_server);
    return (results: [...results, again], documents: copies.docs.length);
  }
}
