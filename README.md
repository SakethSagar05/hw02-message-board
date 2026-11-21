# Vault Board: HW-02 Message Board (CSC 4360)

A Flutter message board backed by Firebase. It opens with a styled splash screen while
Firebase initializes, registers and signs in users with **Firebase Authentication
(Email/Password)**, writes a private **Cloud Firestore user record** for every
registration, and gives signed-in users full **create / read / update / delete** on
messages. The board is read through a live `snapshots()` stream, and Firestore
**security rules** enforce ownership.

Student: Saketh Sagar Kokkireni · Pathway: undergraduate · Due 11/21/2026

---

## 1. Run it

Requirements: Flutter (tested with 3.47 / Dart 3.13), Android SDK + an emulator,
Node.js, Firebase CLI (`npm i -g firebase-tools`), Java 17+ (only for the rules emulator tests).

**Easiest:** double-click `Run HW02.command` in Finder. It runs setup, Firebase
configuration (first run), deploys the rules, runs all checks, builds the release APK
and installs that exact APK on an Android emulator. Every output is saved in
`docs/evidence/`.

**By hand:**

```bash
bash tools/setup.sh                 # android/ + web/, packages, minSdk 23, INTERNET permission
bash tools/firebase_setup.sh        # first run: project, Firestore, Email/Password, flutterfire configure
firebase deploy --only firestore:rules --project "$(cat .firebase_project)"
flutter analyze && flutter test
(cd rules-tests && npm install && npm test)   # automated rules tests on the emulator
flutter build apk --release         # build/app/outputs/flutter-apk/app-release.apk
flutter run -d chrome               # a second "window" for the live-update test
```

### Required Firebase configuration

1. A Firebase project with **Email/Password** sign-in enabled.
2. A **Cloud Firestore** database (default database, production mode).
3. `flutterfire configure --platforms=android,web` generates `lib/firebase_options.dart`
   and `android/app/google-services.json`. These are client configuration, not secrets,
   and were not hand-written. Security comes from the rules, not from hiding them.
4. Deploy `firestore.rules`.
5. `android/app/src/main/AndroidManifest.xml` declares `android.permission.INTERNET`,
   so the **release** APK can reach Firebase (`tools/setup.sh` adds it).

---

## 2. Architecture

```
lib/
  main.dart                 MaterialApp -> SplashScreen
  config.dart               emulator switch (--dart-define=USE_EMULATOR=true)
  models/                   Message, AppUser, ProfileDraft (no Firebase imports)
  services/
    auth_service.dart       every Firebase Auth call
    user_service.dart       users/{uid}: watch + create the record
    board_service.dart      every messages/* call: create, live read, paging, update, delete, batch
    rules_probe_service.dart deliberate rule-breaking calls for the Rules Lab
    validators.dart         form rules that mirror the security rules
    app_exception.dart      Firebase error codes -> safe, helpful messages
  screens/
    splash_screen.dart      initializes Firebase behind a styled splash; Retry on failure
    auth_gate.dart          authStateChanges() routing (UX only, not security)
    auth_screen.dart        sign-in + registration with validation and a double-submit guard
    profile_gate.dart       board opens only when users/{uid} has all five fields
    board_screen.dart       live board, composer, edit/delete own messages, older pages
    rules_lab_screen.dart   on-device evidence: denials come from Firestore, not the UI
```

Widgets never import `cloud_firestore`. They call typed service methods and receive
`Message` / `AppUser` models or an `AppException` with a friendly message.

### Auth flow

`SplashScreen` (Firebase init) -> `AuthGate` listens to one stable `authStateChanges()`
stream -> signed out: `AuthScreen` (sign in / create account) -> signed in:
`ProfileGate` -> `BoardScreen`.

Registration signs the user in **before** the profile write can run, and the gate swaps
the form out at that moment. So the form leaves the typed names and role in
`UserService` (in memory, keyed by email). `ProfileGate`, which stays mounted, writes
the record and opens the board only after the server **confirms** it
(`hasPendingWrites == false`). If the write fails, the user sees "Account created,
profile not saved" with a Retry for the same uid. The app never creates a second
account and never re-runs `set()` on a later login.

---

## 3. Firestore data model

| Document | Fields | Writer | Readers | Purpose |
|---|---|---|---|---|
| `users/{uid}` | `uid`, `firstName`, `lastName`, `role`, `registrationDateTime` (server timestamp) | The client, **once**, at registration, as that uid | Owner only | Private user record required by the spec |
| `messages/{msgId}` | `text`, `authorUid`, `authorName`, `createdAt` (server timestamp), `editedAt` (server timestamp, set on edit) | Signed-in user creates own; author edits `text`/`editedAt`; author deletes | Any signed-in user | Public board content, streamed live |
| `users/{uid}/prefs/{doc}` | opt-in flag, device token, updatedAt | Owner (reserved for notifications) | Owner only | Private; never exposed to others |

* `authorName` is copied onto each message so the board never reads other users'
  private records. It is display text, not identity. Ownership is `authorUid`.
* `role` (`student` / `instructor` / `guest`) is descriptive only. No rule grants
  access by role.
* Ordering uses the **server** clock (`createdAt == request.time` is enforced), so
  phones with wrong clocks or in other time zones cannot reorder the board.

### Security rules (`firestore.rules`)

| Rule | What it prevents |
|---|---|
| `messages` read requires `request.auth != null` | Signed-out scraping of the board |
| create: `authorUid == request.auth.uid` | Posting as someone else (forged signature) |
| create: exact key set, `text` 1–500 chars after trim, `createdAt == request.time` | Junk fields, empty posts, back-dated posts |
| update: stored `authorUid == request.auth.uid` | Editing another user's message |
| update: only `text` + `editedAt` may change, `editedAt == request.time` | Taking over a message or rewriting its creation time |
| delete: stored `authorUid == request.auth.uid` | Deleting another user's message |
| `users/{uid}` read/write only when `request.auth.uid == uid` | Reading or forging someone's private record |
| `users` create: exactly the five fields, known role, server time; update only names; no delete | Resetting the registration time, self-promoting a role |

Hiding the edit/delete menu on other people's messages is **UX**. The rules are the
authorization layer. The Rules Lab screen and `rules-tests/` both prove that.

---

## 4. CRUD and how to verify each operation

| Operation | Service method | Firestore call | Verify |
|---|---|---|---|
| Create | `BoardService.postMessage` | transaction: `get(doc(id))`, then `set` if it does not exist | Post; the message appears at once; one new document in the console |
| Read (live) | `BoardService.liveWindow` | `orderBy('createdAt', descending)` + `snapshots()` | Post from a second window (`flutter run -d chrome`); the first updates without refresh |
| Read (older) | `BoardService.loadOlder` | `startAfterDocument(cursor).limit(20).get()` | Seed 120 messages in the Rules Lab, then "Load older messages" |
| Update | `BoardService.editMessage` | `doc(id).update({text, editedAt})` | Edit the middle of three posts; only it changes and shows "edited" |
| Delete | `BoardService.deleteMessage` | `doc(id).delete()` | Delete message 2 of 3; 1 and 3 are unchanged |
| Batch delete | `BoardService.deleteAllMine` | one `WriteBatch` of deletes | Rules Lab: "Delete all my messages (one batch)" |

States: loading spinner, an intentional empty state ("No messages yet"), an error state
with Retry, and "Sending…" while a server timestamp is pending.

### Duplicate submits

* The Post and Sign-in buttons are disabled while their Future runs.
* Each composer draft has its own document id (`newMessageId()`). Posting runs a
  transaction that writes only if that id does not exist yet. A double tap, a retry after
  a timeout, or a second call with the same draft returns `alreadyPosted` instead of
  creating a copy. The Rules Lab "double-submit test" proves 3 calls -> 1 document.
* Trade-off: transactions need a connection, so posting while offline fails with a clear
  message instead of queueing. This was chosen deliberately, because the offline queue
  plus a user re-tapping is exactly how duplicates appear (Case File 2).

### Stream lifecycle

The board's stream is created once in `initState`. `StreamBuilder` cancels the
subscription when the screen is disposed, so pushing the Rules Lab or signing out never
leaves an extra listener running (Case File 3).

---

## 5. Testing

| Layer | How | Output |
|---|---|---|
| Unit | `flutter test`: validators, model mapping, error messages | `docs/evidence/flutter_test_output.txt` |
| Static | `flutter analyze` | `docs/evidence/flutter_analyze_output.txt` |
| Rules (automated, Spice #2) | `rules-tests/`: 25 test cases with `@firebase/rules-unit-testing` on the Firestore emulator | `docs/evidence/rules_test_output.txt` |
| Rules (on device, real project) | Rules Lab screen: cross-user edit/delete, forged authorUid, owner change, device clock, other user's record, signed-out read | screenshots |
| Release build | `Run HW02.command` installs the exact release APK | `docs/evidence/apk_info.txt` |

### Emulator workflow (Spice #1)

```bash
firebase emulators:start --only auth,firestore --project demo-hw02   # UI: http://127.0.0.1:4000
flutter run --dart-define=USE_EMULATOR=true    # Android emulator reaches the host via 10.0.2.2
```

`demo-` projects never touch real Firebase. The splash shows "EMULATOR MODE" so
screenshots make clear which backend was used.

---

## 6. Extra Spices completed

* **Main Spice: Release Readiness Gate.** The release APK, tested end to end (see the evidence document).
* **#2 Rules Unit Tester:** `rules-tests/`.
* **#4 Idempotent Alchemist:** deterministic draft id + transaction (`postMessage`).
* **#6 Batch Librarian:** cursor pagination (`loadOlder`) + one atomic batched delete (`deleteAllMine`).
* (#1 Emulator Explorer is supported via `USE_EMULATOR` and the emulator config in `firebase.json`.)

## 7. Known limitations

* Older pages (beyond the first 20) are one-shot reads. Edits by *other* users to those
  older messages appear after "Load older" is pressed again or the board reopens.
* `authorName` is denormalized display text, not verified against `users/{uid}` by the
  rules (that would cost an extra read per write).
* The release APK is signed with the debug key (fine for a class submission, not for Play).

## 8. AI assistance disclosure

Claude (Anthropic), 11/21/2026, assisted with generating and reviewing the code, rules
and tests in this repository. All behaviour was run and verified on my own machine. The
evidence document records what was tested, observed and changed.
