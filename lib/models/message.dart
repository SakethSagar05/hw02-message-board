/// One board message, mapped from a `messages/{msgId}` document.
///
/// [createdAt] is null while the server timestamp is still pending (the
/// write has not reached the server yet); the UI shows "Sending…" then.
class Message {
  const Message({
    required this.id,
    required this.text,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    this.editedAt,
  });

  final String id;
  final String text;
  final String authorUid;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? editedAt;

  bool get isPending => createdAt == null;
  bool get isEdited => editedAt != null;
  bool isOwnedBy(String? uid) => uid != null && uid == authorUid;

  /// [toDate] converts a Firestore Timestamp (or anything with toDate())
  /// to DateTime; kept as a parameter so this model has no Firestore import
  /// and can be unit-tested with plain maps.
  factory Message.fromMap(
    String id,
    Map<String, dynamic> data, {
    required DateTime? Function(Object? value) toDate,
  }) {
    return Message(
      id: id,
      text: (data['text'] as String?) ?? '',
      authorUid: (data['authorUid'] as String?) ?? '',
      authorName: (data['authorName'] as String?)?.trim().isNotEmpty == true
          ? data['authorName'] as String
          : 'Unknown author',
      createdAt: toDate(data['createdAt']),
      editedAt: toDate(data['editedAt']),
    );
  }

  Message copyWith({String? text, DateTime? editedAt}) => Message(
        id: id,
        text: text ?? this.text,
        authorUid: authorUid,
        authorName: authorName,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
      );
}
