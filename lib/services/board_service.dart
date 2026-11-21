import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import 'app_exception.dart';

/// Opaque paging cursor. Widgets hold it but cannot see the Firestore
/// snapshot inside, so they never depend on the Firestore API.
class PageCursor {
  const PageCursor._(this._snap);
  final DocumentSnapshot<Map<String, dynamic>> _snap;
}

/// The live part of the board: every message from the newest down to the
/// oldest message of the first page. New posts, edits and deletes in this
/// window arrive through snapshots() without any refresh.
class BoardWindow {
  const BoardWindow({required this.messages, required this.olderCursor});

  /// Newest first.
  final List<Message> messages;

  /// Where older (one-shot) pages start, or null if there are none.
  final PageCursor? olderCursor;
}

/// One page of older messages fetched with a cursor (Extra Spice #6).
class BoardPage {
  const BoardPage({required this.messages, required this.next});
  final List<Message> messages;
  final PageCursor? next;
}

enum PostResult { created, alreadyPosted }

/// Every Firestore call for messages/{msgId} lives here, behind typed methods.
class BoardService {
  BoardService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int pageSize = 20;

  CollectionReference<Map<String, dynamic>> get _messages =>
      _db.collection('messages');

  Query<Map<String, dynamic>> get _newestFirst =>
      _messages.orderBy('createdAt', descending: true);

  /// A fresh document id for the composer's current draft. Re-using the same
  /// id for every retry of one draft is what makes posting idempotent.
  String newMessageId() => _messages.doc().id;

  // ---------------------------------------------------------------- CREATE

  /// Creates messages/{messageId} exactly once (Extra Spice #4).
  /// A transaction reads the document first; if a double tap, a retry after a
  /// timeout, or a second call already created it, nothing is written again.
  /// Trade-off: transactions need a connection, so posting fails fast while
  /// offline instead of queueing (and possibly duplicating) the write.
  Future<PostResult> postMessage({
    required String messageId,
    required String authorUid,
    required String authorName,
    required String text,
  }) async {
    final ref = _messages.doc(messageId);
    try {
      return await _db.runTransaction<PostResult>((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) return PostResult.alreadyPosted;
        tx.set(ref, {
          'text': text.trim(),
          'authorUid': authorUid,
          'authorName': authorName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return PostResult.created;
      });
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  // ------------------------------------------------------------------ READ

  /// The live board (Read with snapshots()). The first page is fetched once
  /// to find an anchor; the listener then covers everything from the newest
  /// message down to that anchor, so a new post never pushes an older message
  /// out of view. Cancelling the subscription (StreamBuilder does it on
  /// dispose) also cancels the Firestore listener.
  Stream<BoardWindow> liveWindow() async* {
    final QuerySnapshot<Map<String, dynamic>> first;
    try {
      first = await _newestFirst.limit(pageSize).get();
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
    var live = _newestFirst;
    PageCursor? cursor;
    if (first.docs.length == pageSize) {
      live = live.endAtDocument(first.docs.last);
      cursor = PageCursor._(first.docs.last);
    }
    yield* live
        .snapshots()
        .handleError((Object e) {
          if (e is FirebaseException) {
            throw AppException(friendlyFirestoreError(e.code), code: e.code);
          }
          throw e;
        })
        .map((snap) => BoardWindow(
              messages: snap.docs.map(_toMessage).toList(),
              olderCursor: cursor,
            ));
  }

  /// Older history, one page at a time, with startAfterDocument (Spice #6).
  /// These pages are one-shot get() reads: they do not live-update.
  Future<BoardPage> loadOlder(PageCursor after) async {
    try {
      final snap =
          await _newestFirst.startAfterDocument(after._snap).limit(pageSize).get();
      return BoardPage(
        messages: snap.docs.map(_toMessage).toList(),
        next: snap.docs.length == pageSize ? PageCursor._(snap.docs.last) : null,
      );
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  // ---------------------------------------------------------------- UPDATE

  /// Changes only text and editedAt; the rules reject any other field change
  /// and any writer who is not the stored authorUid.
  Future<void> editMessage({
    required String messageId,
    required String newText,
  }) async {
    try {
      await _messages.doc(messageId).update({
        'text': newText.trim(),
        'editedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  // ---------------------------------------------------------------- DELETE

  Future<void> deleteMessage({required String messageId}) async {
    try {
      await _messages.doc(messageId).delete();
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  /// Deletes all of the caller's own messages in one atomic batched write
  /// (Spice #6). A batch holds at most 500 operations, so a user with more
  /// than 450 messages is cleared in several batches.
  Future<int> deleteAllMine(String uid) async {
    try {
      final mine = await _messages
          .where('authorUid', isEqualTo: uid)
          .get(const GetOptions(source: Source.server));
      final docs = mine.docs;
      for (var i = 0; i < docs.length; i += 450) {
        final batch = _db.batch();
        for (final d in docs.skip(i).take(450)) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      return docs.length;
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  /// Seeds [count] numbered messages for the pagination test (Spice #6).
  /// Written one at a time so each gets its own server timestamp.
  Future<void> seedMessages({
    required String authorUid,
    required String authorName,
    int count = 120,
    void Function(int done)? onProgress,
  }) async {
    final width = count.toString().length;
    try {
      for (var i = 1; i <= count; i++) {
        await _messages.doc().set({
          'text': 'Seed message #${i.toString().padLeft(width, '0')} of $count',
          'authorUid': authorUid,
          'authorName': authorName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        onProgress?.call(i);
      }
    } on FirebaseException catch (e) {
      throw AppException(friendlyFirestoreError(e.code), code: e.code);
    }
  }

  static Message _toMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      Message.fromMap(doc.id, doc.data(), toDate: toDate);

  static DateTime? toDate(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}
