// Unit tests that need no Firebase connection: form validation (which
// mirrors the security rules) and the document -> model mapping.
// Firebase behaviour itself is tested by rules-tests/ against the emulator
// and by the Rules Lab screen against the real project.
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/models/app_user.dart';
import 'package:message_board/models/message.dart';
import 'package:message_board/services/app_exception.dart';
import 'package:message_board/services/validators.dart';

DateTime? _toDate(Object? v) => v is DateTime ? v : null;

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email(' ada@example.com '), isNull);
    });

    test('registration password needs 6+ characters, sign-in only non-empty', () {
      expect(Validators.newPassword('12345'), isNotNull);
      expect(Validators.newPassword('123456'), isNull);
      expect(Validators.loginPassword(''), isNotNull);
      expect(Validators.loginPassword('x'), isNull);
    });

    test('names', () {
      expect(Validators.name('  '), isNotNull);
      expect(Validators.name("O'Neil-Smith"), isNull);
      expect(Validators.name('Ada1'), isNotNull);
      expect(Validators.name('a' * 51), isNotNull);
    });

    test('message text: trimmed, 1..500 characters', () {
      expect(Validators.message('   '), isNotNull);
      expect(Validators.message('Hello, board!'), isNull);
      expect(Validators.message('x' * 500), isNull);
      expect(Validators.message('x' * 501), isNotNull);
    });
  });

  group('Message.fromMap', () {
    test('maps a confirmed document', () {
      final t = DateTime.utc(2026, 11, 21, 15);
      final m = Message.fromMap('msg_1', {
        'text': 'Hi',
        'authorUid': 'u1',
        'authorName': 'Ada Lovelace',
        'createdAt': t,
      }, toDate: _toDate);
      expect(m.id, 'msg_1');
      expect(m.isPending, isFalse);
      expect(m.isEdited, isFalse);
      expect(m.isOwnedBy('u1'), isTrue);
      expect(m.isOwnedBy('u2'), isFalse);
      expect(m.isOwnedBy(null), isFalse);
    });

    test('a pending server timestamp maps to null (shown as Sending…)', () {
      final m = Message.fromMap('x', {'text': 'Hi', 'authorUid': 'u1'},
          toDate: _toDate);
      expect(m.isPending, isTrue);
      expect(m.authorName, 'Unknown author');
    });

    test('copyWith keeps ownership', () {
      final m = Message.fromMap('x', {'text': 'a', 'authorUid': 'u1'},
          toDate: _toDate);
      final e = m.copyWith(text: 'b', editedAt: DateTime(2026));
      expect(e.text, 'b');
      expect(e.authorUid, 'u1');
      expect(e.isEdited, isTrue);
    });
  });

  group('AppUser', () {
    test('complete only with all five fields and a resolved timestamp', () {
      final data = {
        'uid': 'u1',
        'firstName': 'Ada',
        'lastName': 'Lovelace',
        'role': 'student',
        'registrationDateTime': DateTime(2026, 11, 21),
      };
      expect(AppUser.fromMap(data, toDate: _toDate).isComplete, isTrue);
      expect(AppUser.fromMap({...data, 'registrationDateTime': null},
              toDate: _toDate)
          .isComplete, isFalse);
      expect(AppUser.fromMap({...data, 'role': ''}, toDate: _toDate).isComplete,
          isFalse);
      expect(AppUser.fromMap(data, toDate: _toDate).displayName, 'Ada Lovelace');
    });

    test('roles are descriptive values only', () {
      expect(userRoles, containsAll(['student', 'instructor', 'guest']));
      expect(userRoles, isNot(contains('admin')));
    });
  });

  group('Friendly errors never expose raw codes alone', () {
    test('auth', () {
      expect(friendlyAuthError('email-already-in-use'), contains('already exists'));
      expect(friendlyAuthError('invalid-credential'), contains('incorrect'));
    });
    test('firestore', () {
      expect(friendlyFirestoreError('permission-denied'), contains('rules'));
      expect(friendlyFirestoreError('unavailable'), contains('offline'));
    });
  });
}
