# HW-02 written sections (draft)

Items in [BRACKETS] are filled in from the real test run. Read every answer
before submitting; you should be able to explain each one in your own words.

---

## Case File 1: The Ghost Editor

**Diagnosis.** The tutorial rule `allow read, write: if request.auth != null;` checks
only *authentication* (is somebody signed in?), never *authorization* (is this person
allowed to change this document?). Every demo passed because each tester used the app's UI,
and the UI only shows Edit/Delete on your own messages. So nobody ever *sent* a write for
someone else's document, and the hole was never exercised. Hiding buttons is UX. It decides
what the app offers, not what the database accepts. Authorization lives only in the rules,
because the rules are the only check a request cannot skip.

**What an attacker could do before the fix.** With only a signed-in account and a REST
client (or the JS SDK in a browser console), they could send a PATCH or DELETE to
`messages/{anyId}`. Each one passes `request.auth != null`. They could rewrite or delete
every post, create posts with someone else's `authorUid`, back-date posts with a fake
`createdAt`, and, because the rule says `write`, set any field they liked.

**Fix (what my app deploys):**

```
match /messages/{msgId} {
  allow read:   if request.auth != null;
  allow create: if request.auth != null
    && request.resource.data.authorUid == request.auth.uid
    && request.resource.data.createdAt == request.time
    && request.resource.data.keys().hasOnly(['text','authorUid','authorName','createdAt']);
  allow update: if request.auth != null
    && resource.data.authorUid == request.auth.uid
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['text','editedAt']);
  allow delete: if request.auth != null
    && resource.data.authorUid == request.auth.uid;
}
```

Update and delete check the author stored in the **existing** document (`resource.data`),
not a value the client sends, so the owner cannot be forged. `affectedKeys().hasOnly(...)`
also stops the real owner from handing a message to someone else.

**Trade-off.** There are no moderator powers now. Even a TA cannot remove an abusive post
from the client. Adding that safely needs a role the client cannot write (a custom Auth
claim set by trusted server code), not the descriptive `role` field in `users/{uid}`. I
accepted the trade-off because the assignment keeps roles descriptive only.

**Evidence the fix works.**
1. Automated: `rules-tests/` runs against the emulator and asserts these are denied:
   cross-user update, cross-user delete, forged `authorUid` on create, owner changing
   `authorUid`. It also asserts the correct-author edit and delete are allowed
   ([N] passing, `rules_test_output.txt`).
2. On the real project, through the app with the UI bypassed: the Rules Lab cross-user
   edit and delete return `permission-denied` (screenshots [14a–c]).
3. With no UI at all: a raw REST PATCH signed in as Bob against Alice's message returns
   HTTP 403 `PERMISSION_DENIED` (`16_rest_cross_user_edit.txt`). That is the exact
   attacker from the ticket.

---

## Case File 2: The Runaway Dupes

**Mechanism.** The Firestore SDK applies a write to its local cache at once
(latency compensation) and queues it. Offline, the write sits in the queue and the
`Future` does not complete. On reconnect, the SDK sends the queued writes. A write sent
with `add()` always generates a **new random id**. So any path that issues the same intent
twice produces two documents. Examples: a user re-taps after a "slow" spinner times out, a
retry wrapper fires after a lost acknowledgement, or the app restarts and the user posts
again while the first copy is still queued. The two copies can land minutes or hours apart,
whenever the second one gets through. Disabling the button only covers *one widget instance
during one pending Future*. It does nothing about timeouts, retries, app restarts, or a
queued write that is replayed later.

**Decision: deterministic draft id + transaction.** My composer gives each draft a
document id (`newMessageId()`) when the draft starts, and keeps that id for every retry
until the post succeeds. `postMessage` runs a transaction: read `messages/{draftId}`. If
it exists, return `alreadyPosted`. Otherwise `set` it. Two taps, a retry, or a second call
with the same draft all target the same document, so at most one can create it. For a
two-person team with one sprint, this is a few lines inside `BoardService`, and no server
code is needed. The disabled button stays as a cheap first layer.

**Residual risk I accept.** Transactions need a connection. So instead of queueing
offline, a post fails fast with "You appear to be offline". The user keeps the text and
the same draft id, so retrying later is still safe. I traded offline posting for
correctness. Duplicates that are *different drafts* with identical text (the user types
the same thing twice on purpose) are not prevented, and I think that is correct.

**Experiment.**
- *Reproduce:* with plain `add()`, put the emulator on a throttled network (or airplane
  mode), tap Post, kill the app, relaunch, post again, reconnect. Count the documents with
  that text: 2.
- *Prove the fix:* (a) triple-tap Post in one `adb shell` command. Firestore holds exactly
  [1] document (`12_double_tap_count.txt`). (b) The Rules Lab double-submit test fires two
  concurrent `postMessage` calls plus a later retry, all with one draft id. The results were
  `[alreadyPosted, created, alreadyPosted]`. The two concurrent calls raced, exactly one
  won, and the document count was 1 (screenshot 15).

---

## Case File 3: The Stream That Would Not Stop (optional third)

**Lifecycle.** `snapshots()` opens a Firestore listener when a subscriber listens. Every
document change it delivers is billed as a read. `StreamBuilder` subscribes in its
`State` and cancels the subscription when that `State` is disposed. The bug in the ticket
comes from creating a **new** stream inside `build()` or `initState()` of a screen that
stays alive under a pushed route. The board screen is not disposed when the profile screen
is pushed on top of it, so its listener keeps running. If the profile screen also calls
`collection('messages').snapshots()`, that is a second listener. Each push without a pop,
or each rebuild that creates a new stream, adds another listener. So reads grow with
navigation.

**What I shipped first: cancel-on-dispose discipline with one stream per screen state.**
`BoardScreen` creates its stream once (a `late` field, not in `build`). `StreamBuilder`
cancels it on dispose. The `async*` generator propagates the cancel to the Firestore
listener. Screens that do not need live data (Rules Lab probes) use one-shot
`get(Source.server)`. I give up live updates on those secondary screens. A single shared
app-wide stream would remove the duplicate entirely, but it needs state management, so it
is the next step if the app grows.

**Measurement.** Compare the Firestore usage tab (reads per minute) while sitting on the
board vs. after pushing and popping the second screen ten times. Or wrap the stream with
`.listen` counters in debug and log active listeners. A leak shows up as a step increase
that does not drop after popping.

---

## Reflection prompts

**Prompt 1: Expectation vs obtained.** I expected the first full-cycle run (register,
post three messages, edit the middle one, delete it) to just work, because each piece
mirrors the starter code. What actually happened: the app itself passed
the cycle first time. The first *automated* run failed at "create three posts", but not
because of the app. My test script could not tap the composer: it sits at 93.4% of the
screen height, and the script treated anything below 93% as off-screen and kept scrolling.
The screenshot showed the composer right there, so the bug was in the test, not the
board. After the fix, all 20 checks passed on the release APK. The live stream behaved as expected: a message posted by
a second client appeared on the emulator with no refresh (screenshot [13]).

**Prompt 1 follow-up: analysis.** Root cause: a hard-coded screen-position assumption in
the test harness, made without checking it against the real layout of a tall 1440x3120
emulator. A failing test is evidence about the test *and* the app, and the screenshot
settles which one is wrong. A second design lesson from building the app:
registration signs the user in *before* the profile write runs, so the auth gate tears
down the registration form mid-submit. I moved the write into `ProfileGate`, which stays
mounted, and open the board only once the server confirms the record
(`hasPendingWrites == false`). Authentication alone is not proof the profile exists.

**Prompt 2: debug evidence.** Creating the Firestore database for my brand-new Firebase
project failed from the CLI with HTTP 403: "Cloud Firestore API has not been used in
project vault-board-qjnocm before or it is disabled." A new project does not have the
Firestore API switched on, so the CLI cannot create the `(default)` database. I created
the database in the Firebase console (US location, production mode), which enables the
API. Then `firebase deploy --only firestore:rules` succeeded ("released rules
firestore.rules to cloud.firestore"). The signed-out read test (05) confirmed the fix:
HTTP 403 PERMISSION_DENIED from my rules, not "API disabled". A second issue: the
automated rules tests did not run at first, for two reasons. `node --test test/` no longer
accepts a folder on Node 24, so I pointed it at the test file. And the Firestore emulator
needs Java, which was not on my PATH, so I used the JDK bundled with Android Studio. After
that, 25 of 25 rules tests passed.

**Prompt 2 follow-up: alternatives.** I considered (a) `add()` plus a disabled button
and (b) a Cloud Function that deduplicates on the server. I rejected (a) because it misses
retries and restarts (Case File 2). I rejected (b) because it adds deployment, cost and
latency. A deterministic id with a transaction fixes the cause inside `BoardService` and is
testable on the client.

**Prompt 3: improvement plan.** Add a `schemaVersion` field to messages now, while the
board is small. Today any format change (renaming `text`, adding reactions) would leave
old documents unreadable by new code. A version field plus a one-time migration lets the
model evolve without losing posts. Second: replace the denormalized `authorName` with a
rules-checked value, so a user cannot post under a fake display name.

**Prompt 4: privacy and placement.** I kept everything personal out of local storage.
The app stores no passwords (Firebase Auth handles credentials; my code only passes them
through), no user records on disk beyond Firestore's own cache, and nobody else's
profile. Other users' names reach a device only as the `authorName` printed on public
messages. `users/{uid}` is readable only by its owner, which the Rules Lab "read another
user's record" probe proves is denied. The convenience I kept is Firebase's persisted
session, so users are not asked to sign in on every launch.

**Prompt 5: cloud vs device.** Firestore holds everything that must be shared or must
follow the account across devices: messages and the user record. A half-typed draft
belongs on the device. It is private and temporary, and losing it costs little. The
persisted Firebase session blurs the line: it is device-stored, but it is an identity
credential that grants cloud access until sign-out. That is why it lives in the Auth
SDK's own storage and not in my code, and why sign-out matters. My split: shared and
durable data goes to Firestore, ephemeral data stays on the device, and credentials stay
with the SDK.

**Prompt 6: scale.** At 10,000 users and 100,000 messages, an unbounded
`orderBy('createdAt').snapshots()` breaks first. Every client would download the whole
board and pay a read for every document, then one read per change for every listener. My
board already fetches 20, listens only from the newest message down to that anchor, and
loads older history with `startAfterDocument` cursors (Spice #6). Next I would move older
pages onto listeners only while visible, keep one shared board stream per app, and keep
the rules test suite in CI so a rule change can never reopen Case File 1.

---

## AI Lab (undergraduate: Flow & Lifetime Showdown)

**My survival predictions (made before checking with AI or testing):**
1. Force-kill the app and reopen it: I expected to be **signed out**.
2. Reboot the phone and reopen the app: I expected to be **still signed in**.
3. Clear app data in Android Settings: I expected to be **signed out**, with my **messages coming back** from Firestore after signing in.
4. Half-typed message, then force-kill: I expected the **draft to be kept**.
5. Flow: splash while Firebase starts, then sign-in/registration, then the board. Signed-out users never see the board.

**AI tool, date, summary:** Claude (Anthropic), 11/21/2026. It described the flow as
splash → `authStateChanges()` → profile gate → board. It said `get()` reads once and
`snapshots()` stays live, and that server timestamps keep ordering correct across
devices. It said the Firebase Auth session is stored on the device, so it survives an app
kill and a reboot. It said that clearing app data deletes that session and Firestore's
local cache but not the data on the server. It suggested tests for invalid input,
signed-out read, cross-user edit, and double-tap.

**The claim I doubted:** "Clearing app data signs you out, but your messages come back
from Firestore." I was not sure "clear data" would leave the messages alone, because the
app also keeps a local Firestore cache.

**Compare, verify, decide.** I tested all four predictions on the release APK with a
script (`Verify Predictions.command`, log in `docs/evidence/ai_lab_predictions.log`,
screenshots AI_1–AI_4b):

| Prediction | Observed | Who was right |
|---|---|---|
| Kill → signed out | Still signed in (AI_2) | AI; my prediction was wrong |
| Reboot → signed in | Still signed in (AI_3) | Both |
| Clear data → signed out, messages back | Signed out (AI_4a); after signing in, Bob's message was back (AI_4b) | Both; my doubted claim was confirmed |
| Draft kept after kill | Draft lost (AI_1 vs AI_2) | My prediction was wrong |

The experiment settled the doubted claim: clearing app data removed only what was on the
device (the Auth session and the cache). The messages live in Firestore, so they came
back as soon as I signed in. That matches the Firebase docs. Firestore's offline cache is
a local copy, not the source of truth
(https://firebase.google.com/docs/firestore/manage-data/enable-offline). Auth state on
Android is persisted to disk until sign-out
(https://firebase.google.com/docs/auth/flutter/start).

I was wrong twice. The session survives an app kill for the same reason it survives a
reboot: it is saved to disk, not kept in memory. Treating "kill" and "reboot" differently
was inconsistent of me. The draft was lost because the composer text lives only in a
`TextEditingController` in memory, and nothing writes it to disk.

**Decision:** I kept the AI's flow and the session behavior (both verified). I did not add
draft saving tonight, but it is a cheap improvement: save the composer text to
`shared_preferences` on change and clear it after a successful post. A lost draft costs
the user little, so I left it as a documented limitation. **Flow Referee:** confirmed AI
statement: "the session survives an app kill" (test 20 and AI_2). Corrected statement: my
own assumption that a draft survives a kill. No AI claim I tested was contradicted, so I
am not claiming the AI Mythbuster badge.
