#!/bin/bash
# AI Lab: test my four survival predictions on the release APK (emulator).
#   1) half-typed draft, then force-kill    2) sign-in after app kill
#   3) sign-in after a phone reboot         4) Clear app data: sign-in + messages
# Saves AI_*.png screenshots and docs/evidence/ai_lab_predictions.log
cd "$(dirname "$0")" || exit 1
source tools/env.sh
EVID=docs/evidence; PKG=edu.gsu.csc4360.message_board
UI="$(mktemp -t vb_ui).xml"
ACC="$(cat "$EVID/test_accounts.txt")"
BOB="$(echo "$ACC" | sed -E 's/.*bob=([^ ]+).*/\1/')"; PW="$(echo "$ACC" | sed -E 's/.*password=([^ ]+).*/\1/')"
exec > >(tee "$EVID/ai_lab_predictions.log") 2>&1
say() { printf '\n==> %s\n' "$*"; }
dump() { for _ in 1 2 3; do adb shell uiautomator dump /sdcard/vb_ui.xml >/dev/null 2>&1 && adb exec-out cat /sdcard/vb_ui.xml > "$UI" && grep -q "<node" "$UI" && return 0; sleep 1; done; return 1; }
has() { dump && python3 -B tools/ui_find.py "$UI" has "$1"; }
texts() { dump && python3 -B tools/ui_find.py "$UI" texts x; }
shot() { adb exec-out screencap -p > "$EVID/$1.png"; echo "    saved $EVID/$1.png"; }
tapf() { local p; dump && p="$(python3 -B tools/ui_find.py "$UI" "${2:-find}" "$1" 0)" && adb shell input tap ${p% *} ${p#* } && sleep 1; }
typein() {
  tapf "$1" field || return 1
  sleep 1; adb shell input keyevent 123
  adb shell input keyevent $(printf '67 %.0s' $(seq 1 160))
  adb shell "input text '${2// /%s}'"; sleep 1
  adb shell dumpsys input_method | grep -q "mInputShown=true" && { adb shell input keyevent 4; sleep 1; }
}
launch() { adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 8; }
signed_in() { has "Sign out"; }

say "Start: open the app (Bob should still be signed in from the capture run)"
launch
if ! signed_in; then
  echo "    not signed in; signing in as $BOB"
  typein "Email" "$BOB"; typein "Password" "$PW"; tapf "Sign in"; sleep 6
fi
signed_in && echo "    signed in as Bob" || { echo "    could not sign in"; texts; exit 1; }

say "Prediction 1 + 2: type a draft (do not post), then force-kill and relaunch"
typein "Write a message" "unsent draft test"
has "unsent draft test" && echo "    draft visible before kill"; shot AI_1_draft_before_kill
adb shell am force-stop $PKG; sleep 2; launch
shot AI_2_after_kill
signed_in && echo "    OBSERVED: still signed in after app kill" || echo "    OBSERVED: signed out after app kill"
has "unsent draft test" && echo "    OBSERVED: draft kept after app kill" || echo "    OBSERVED: draft lost after app kill"

say "Prediction 3: reboot the emulator, then open the app"
adb reboot; sleep 5; adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
sleep 10; launch
shot AI_3_after_reboot
signed_in && echo "    OBSERVED: still signed in after reboot" || echo "    OBSERVED: signed out after reboot"

say "Prediction 4: Clear app data (adb shell pm clear), then open the app"
adb shell pm clear $PKG; sleep 2; launch
shot AI_4a_after_clear_data
signed_in && echo "    OBSERVED: still signed in after clearing data" || echo "    OBSERVED: signed out after clearing data"
echo "    signing back in as Bob to check the messages"
typein "Email" "$BOB"; typein "Password" "$PW"; tapf "Sign in"; sleep 8
shot AI_4b_signed_back_in
has "Hello from Bob on a second device" && echo "    OBSERVED: messages came back from Firestore after clearing data" || { echo "    OBSERVED: Bob's message not visible"; texts; }
say "Done"
read -r -p "Press Return to close." _
