#!/bin/bash
# Double-click AFTER "Run HW02.command" has installed the release APK.
# Drives the release app on the Android emulator with adb against the REAL
# Firebase project and saves numbered evidence in docs/evidence/:
#   NN_*.png    screenshots       NN_*.txt   what Firestore returned at that moment
#   capture_run.log  every step, the text on screen, and PASS/FAIL
# It creates two fictional test accounts (…@example.com) in your project.
cd "$(dirname "$0")" || exit 1
source tools/env.sh
EVID=docs/evidence
PKG=edu.gsu.csc4360.message_board
UI="$(mktemp -t vb_ui).xml"
RUN="$(date +%m%d%H%M)"
PW="VaultTest-$RUN"                      # fictional test password
ALICE="alice.$RUN@example.com"
BOB="bob.$RUN@example.com"
mkdir -p "$EVID"
echo "alice=$ALICE bob=$BOB password=$PW" > "$EVID/test_accounts.txt"
exec > >(tee "$EVID/capture_run.log") 2>&1
FAILS=0

say()  { printf '\n==> %s\n' "$*"; }
pass() { echo "    PASS: $*"; }
bad()  { echo "    FAIL: $*"; FAILS=$((FAILS + 1)); }
fs()   { python3 -B tools/fs.py "$@"; }
dump() {
  for _ in 1 2 3; do
    adb shell uiautomator dump /sdcard/vb_ui.xml >/dev/null 2>&1 &&
      adb exec-out cat /sdcard/vb_ui.xml > "$UI" 2>/dev/null &&
      grep -q "<node" "$UI" && return 0
    sleep 1
  done
  return 1
}
texts() { dump && python3 -B tools/ui_find.py "$UI" texts x; }
has()   { python3 -B tools/ui_find.py "$UI" has "$1"; }
shot()  { adb exec-out screencap -p > "$EVID/$1.png"; echo "    saved $EVID/$1.png"; }
H="$(adb shell wm size | tr -d '\r' | awk -F'[ x]' '/Physical/ {print $NF}')"; H="${H:-2400}"
W="$(adb shell wm size | tr -d '\r' | awk -F'[ x:]' '/Physical/ {print $(NF-1)}')"; W="${W:-1080}"
up()   { adb shell input swipe $((W/2)) $((H*65/100)) $((W/2)) $((H*30/100)) 300; sleep 1; }
down() { adb shell input swipe $((W/2)) $((H*30/100)) $((W/2)) $((H*70/100)) 300; sleep 1; }

wait_text() {  # wait_text "text" [seconds]
  local end=$((SECONDS + ${2:-30}))
  while [ $SECONDS -lt $end ]; do dump && has "$1" && return 0; sleep 1; done
  return 1
}
wait_gone() {
  local end=$((SECONDS + ${2:-20}))
  while [ $SECONDS -lt $end ]; do dump && ! has "$1" && return 0; sleep 1; done
  return 1
}
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then adb shell input keyevent 4; sleep 1; fi
}
pos_of() { dump && python3 -B tools/ui_find.py "$UI" "${2:-find}" "$1" "${3:-0}"; }
tap() {  # tap "label" [find|field] [index]  (scrolls if needed)
  local p x y
  for try in 1 2 3 4 5 6; do
    if p="$(pos_of "$@")"; then
      x="${p% *}"; y="${p#* }"
      if [ "$y" -gt $((H * 97 / 100)) ]; then up; continue; fi
      adb shell input tap "$x" "$y"; echo "    tapped \"$1\" at $x,$y"; sleep 1; return 0
    fi
    if [ $try -le 3 ]; then up; else down; fi
  done
  echo "    could not find \"$1\""; shot "FAIL_$(echo "$1" | tr -c 'A-Za-z0-9' '_' | head -c 30)"; texts; return 1
}
type_into() {  # type_into "field label" index "text"
  tap "$1" field "$2" || return 1
  adb shell input keyevent 123
  adb shell input keyevent $(printf '67 %.0s' $(seq 1 60))
  adb shell "input text '${3// /%s}'"; sleep 1
}
post() {  # post "text": succeeds when Firestore holds exactly one such message
  hide_keyboard
  type_into "Write a message" 0 "$1"
  hide_keyboard
  tap "Post" || return 1
  local end=$((SECONDS + 20))
  while [ $SECONDS -lt $end ]; do
    [ "$(fs count-text "$ALICE" "$PW" "$1")" = "1" ] && sleep 1 && return 0
    sleep 1
  done
  return 1
}
abort() { bad "$*"; shot "FAIL_last_screen"; texts; echo "RESULT: STOPPED EARLY ($FAILS failure(s))"; read -r -p "Press Return to close." _; exit 1; }

say "Preflight"
adb devices | grep -qw device || abort "No Android emulator is running. Run 'Run HW02.command' first."
adb shell pm list packages | grep -q "$PKG" || abort "Vault Board is not installed. Run 'Run HW02.command' first."
echo "    project: $(project_id)   device: $(adb shell getprop ro.product.model | tr -d '\r')"
echo "    accounts: $ALICE, $BOB (fictional, password in test_accounts.txt)"
adb shell pm clear "$PKG" >/dev/null   # start signed out with an empty cache

say "01. Launch: splash screen while Firebase initializes"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 0.8; shot 01_splash_a
sleep 0.6; shot 01_splash_b
wait_text "Sign in to the board" 30 || abort "sign-in screen did not appear"
texts; shot 02_signed_out_sign_in
has "Post" && bad "composer visible while signed out" || pass "signed-out user sees only sign-in; no board"

say "03. Invalid input is caught before any network call"
hide_keyboard; tap "Sign in"
wait_text "Enter your email" 5 && pass "empty form shows field errors" || bad "no validation message"
shot 03_invalid_input

say "04. Wrong credentials give a safe, helpful message"
type_into "Email" 0 "nobody.$RUN@example.com"
type_into "Password" 1 "wrong-password"
hide_keyboard; tap "Sign in"
wait_text "incorrect" 20 && pass "failed sign-in explained without raw exception text" || bad "no friendly failed-sign-in message"
texts; shot 04_failed_sign_in

say "05. Rules: signed-out read of messages is denied by Firestore"
tap "Rules check: read board while signed out" || abort "rules check button missing"
tap "Run signed-out read"
wait_text "RESULT:" 20 || bad "no result"
texts; shot 05_signed_out_read_denied
has "permission-denied" && pass "denied with permission-denied" || bad "signed-out read was not denied"
fs signed-out-read > "$EVID/05_rest_signed_out_read.txt"; cat "$EVID/05_rest_signed_out_read.txt" | head -4
adb shell input keyevent 4; sleep 1

say "06. Register Alice (first name, last name, role, email, password)"
wait_text "New here? Create an account" 10 && tap "New here? Create an account"
wait_text "Create your account" 10 || abort "registration form did not open"
type_into "First name" 0 "Alice"
type_into "Last name" 1 "Adams"
type_into "Email" 2 "$ALICE"
type_into "Password" 3 "$PW"
type_into "Confirm password" 4 "$PW"
hide_keyboard; shot 06_registration_form
tap "Create account"
wait_text "Signed in as Alice Adams" 40 || abort "board did not open after registration"
texts; shot 07_board_empty_state
has "No messages yet" && pass "intentional empty-board state" || echo "    (board already had messages, so no empty state)"

say "08. Firestore user record has all five fields"
fs record "$ALICE" "$PW" | tee "$EVID/08_user_record_alice.txt"
for f in uid firstName lastName role registrationDateTime; do
  grep -q "\"$f\"" "$EVID/08_user_record_alice.txt" || bad "user record missing $f"
done
grep -q '"registrationDateTime": "20' "$EVID/08_user_record_alice.txt" && pass "uid, firstName, lastName, role, registrationDateTime present"

say "09. Create: three posts appear through the live stream"
post "Alice message one" || bad "post 1 not shown"
post "Alice message two" || bad "post 2 not shown"
post "Alice message three" || bad "post 3 not shown"
hide_keyboard; texts; shot 09_three_posts
fs messages "$ALICE" "$PW" | tee "$EVID/09_firestore_after_create.txt"
grep '"Alice message one"\|"Alice message three"' "$EVID/09_firestore_after_create.txt" > /tmp/vb_before.txt

say "10. Update: edit the middle message only"
tap "Message options: Alice message two" || abort "options for message two not found"
tap "Edit"
wait_text "Edit message" 10 || abort "edit dialog did not open"
type_into "Message text" 0 "Alice message two edited"
hide_keyboard; tap "Save"
wait_gone "Edit message" 10; wait_text "Alice message two edited" 20 && pass "edited text shown live" || bad "edit not shown"
sleep 2; texts; shot 10_after_edit
fs messages "$ALICE" "$PW" | tee "$EVID/10_firestore_after_edit.txt"
grep '"Alice message two edited"' "$EVID/10_firestore_after_edit.txt" | grep -q '"editedAt": "20' && pass "editedAt set by the server" || bad "editedAt missing"

say "11. Delete: remove message two; one and three untouched"
tap "Message options: Alice message two edited" || abort "options for edited message not found"
tap "Delete"
wait_text "Delete this message?" 10 || abort "delete confirmation did not open"
tap "Delete"
wait_gone "Alice message two edited" 20 && pass "message removed from the live board" || bad "message still shown"
texts; shot 11_after_delete
fs messages "$ALICE" "$PW" | tee "$EVID/11_firestore_after_delete.txt"
grep '"Alice message one"\|"Alice message three"' "$EVID/11_firestore_after_delete.txt" > /tmp/vb_after.txt
diff -q /tmp/vb_before.txt /tmp/vb_after.txt >/dev/null && pass "messages one and three are byte-for-byte unchanged" || bad "other messages changed"
grep -q "message two" "$EVID/11_firestore_after_delete.txt" && bad "message two still in Firestore" || pass "message two gone from Firestore"

say "12. Duplicate submit: rapid double tap on Post"
type_into "Write a message" 0 "Double tap check $RUN"
hide_keyboard
P="$(pos_of "Post")"; adb shell "input tap ${P% *} ${P#* }; input tap ${P% *} ${P#* }; input tap ${P% *} ${P#* }"
sleep 4; texts; shot 12_double_tap
N="$(fs count-text "$ALICE" "$PW" "Double tap check $RUN")"
echo "    documents with that text: $N" | tee "$EVID/12_double_tap_count.txt"
[ "$N" = "1" ] && pass "three taps produced exactly one document" || bad "expected 1 document, found $N"

say "13. Live stream: a second device (REST client signed in as Bob) posts"
fs signup "$BOB" "$PW" > "$EVID/13_bob_uid.txt"
fs create-record "$BOB" "$PW" "Bob" "Baker" "student" | tee -a "$EVID/13_bob_uid.txt"
fs post "$BOB" "$PW" "Bob Baker" "Hello from Bob on a second device" | tee "$EVID/13_second_device_post.txt"
wait_text "Hello from Bob on a second device" 20 && pass "Alice's board updated with no refresh" || bad "live update did not arrive"
texts; shot 13_live_update_from_second_device
has "Message options: Hello from Bob" && bad "Alice is offered edit/delete on Bob's message" || pass "no edit/delete menu on another user's message (UX layer; rules are tested next)"

say "14. Rules Lab as Alice: every bypass attempt is denied by Firestore"
tap "Rules Lab" || abort "Rules Lab button not found"
wait_text "Run all denial checks" 10 || abort "Rules Lab did not open"
tap "Run all denial checks"
sleep 15
dump; shot 14a_rules_lab_top; texts
up; up; shot 14b_rules_lab_middle; texts
up; up; shot 14c_rules_lab_bottom; texts
grep -o 'RESULT: [A-Z]*' "$UI" | sort | uniq -c

say "15. Double-submit test in the Rules Lab (same draft id, three calls)"
tap "Run double-submit test"
wait_text "Documents in Firestore with that text" 30 || bad "no double-submit result"
texts; shot 15_double_submit_test
has "with that text: 1" && pass "3 calls with one id -> 1 document" || bad "double-submit test did not show 1 document"

say "16. REST cross-check: Bob edits Alice's message over the raw API"
ALICE_ID="$(grep '"Alice message one"' "$EVID/11_firestore_after_delete.txt" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["id"])')"
fs cross-edit "$BOB" "$PW" "$ALICE_ID" | tee "$EVID/16_rest_cross_user_edit.txt"
grep -q "PERMISSION_DENIED" "$EVID/16_rest_cross_user_edit.txt" && pass "raw API edit denied by the rules" || bad "raw API edit not denied"

say "17. Pagination: seed 120 messages, then load older pages with a cursor"
tap "Seed 120 messages"
wait_text "Seeded 120 messages" 300 || bad "seeding did not finish"
texts; shot 17_seeded
adb shell input keyevent 4; sleep 3
wait_text "Seed message #120 of 120" 20 || bad "newest seeded message not on the board"
shot 17a_board_newest_page
for _ in $(seq 1 12); do down; dump && has "Load older messages" && break; done
shot 17b_load_older_button
tap "Load older messages" && sleep 3
for _ in 1 2 3; do down; done
texts; shot 17c_older_page_loaded
has "Seed message #0" && pass "older seeded messages loaded through the cursor" || bad "older page not visible"

say "18. Batch write: delete all of Alice's messages in one atomic batch"
tap "Rules Lab" || abort "Rules Lab button not found"
for _ in 1 2 3 4; do up; done
tap "Delete all my messages (one batch)"
tap "Delete all"
wait_text "Batch committed" 60 || bad "batch did not commit"
texts; shot 18_batch_delete
echo "    Alice messages left: $(fs count-author "$ALICE" "$PW")  Bob messages left: $(fs count-author "$BOB" "$PW")" | tee "$EVID/18_after_batch.txt"
grep -q "Alice messages left: 0" "$EVID/18_after_batch.txt" && pass "all of Alice's messages deleted" || bad "Alice still has messages"
grep -q "Bob messages left: 1" "$EVID/18_after_batch.txt" && pass "Bob's message untouched" || bad "Bob's message affected"
adb shell input keyevent 4; sleep 2

say "19. Sign out returns to the sign-in screen"
tap "Sign out"
wait_text "Sign in to the board" 20 && pass "signed out; board hidden" || bad "sign-out did not return to sign-in"
shot 19_signed_out

say "20. Sign in as Bob; kill and relaunch; session survives"
type_into "Email" 0 "$BOB"
type_into "Password" 1 "$PW"
hide_keyboard; tap "Sign in"
wait_text "Signed in as Bob Baker" 30 || bad "Bob could not sign in"
adb shell am force-stop "$PKG"; sleep 1
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
wait_text "Signed in as Bob Baker" 30 && pass "authStateChanges() restored Bob's session after a kill" || bad "session lost after relaunch"
texts; shot 20_relaunch_still_signed_in

say "Done"
ls "$EVID" | sed 's/^/    /'
if [ "$FAILS" -eq 0 ]; then echo "RESULT: ALL CHECKS PASSED"; else echo "RESULT: $FAILS CHECK(S) FAILED (see FAIL lines above)"; fi
read -r -p "Press Return to close." _
