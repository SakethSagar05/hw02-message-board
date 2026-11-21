#!/bin/bash
# Double-click this file in Finder. It does everything that has to happen on
# this Mac, in order, and saves every output in docs/evidence/:
#   1. project setup (android/ + web/ folders, packages, Android settings)
#   2. Firebase setup (first run only: project, Firestore, Email/Password, flutterfire)
#   3. deploys firestore.rules to that project
#   4. flutter analyze, flutter test, and the automated rules tests (emulator)
#   5. builds the RELEASE APK and copies it to submission/
#   6. boots an Android emulator if none is running, installs that exact APK, opens it
cd "$(dirname "$0")" || exit 1
source tools/env.sh
set -uo pipefail
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m%s\033[0m\n' "$*"; read -r -p "Press Return to close." _; exit 1; }
EVID=docs/evidence
mkdir -p "$EVID" submission

step "1/6 Project setup"
bash tools/setup.sh 2>&1 | tee "$EVID/setup_output.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "Setup failed. Tell Claude: 'setup failed' (the log is in docs/evidence/setup_output.txt)."

step "2/6 Firebase project"
bash tools/firebase_setup.sh || fail "Firebase setup failed. Copy the lines above to Claude."
PROJECT="$(project_id)"
[ -f lib/firebase_options.dart ] || fail "lib/firebase_options.dart is missing; flutterfire configure did not finish."
echo "Using Firebase project: $PROJECT"

step "3/6 Deploy security rules to $PROJECT"
firebase deploy --only firestore:rules,firestore:indexes --project "$PROJECT" 2>&1 | tee "$EVID/rules_deploy_output.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "Rules deploy failed. See docs/evidence/rules_deploy_output.txt."

step "4/6 Automated checks (saved in docs/evidence/)"
{ date; sw_vers 2>/dev/null; flutter --version; firebase --version; node --version; java -version 2>&1 | head -1; } > "$EVID/env.txt" 2>&1
flutter analyze 2>&1 | tee "$EVID/flutter_analyze_output.txt"
flutter test 2>&1 | tee "$EVID/flutter_test_output.txt"
if java -version >/dev/null 2>&1; then
  (cd rules-tests && npm install --no-audit --no-fund >/dev/null 2>&1 && npm test 2>&1) | tee "$EVID/rules_test_output.txt"
else
  echo "Java not found: skipped the rules emulator tests (brew install openjdk@21)." | tee "$EVID/rules_test_output.txt"
fi

step "5/6 Build the release APK"
flutter build apk --release 2>&1 | tee "$EVID/apk_build_output.txt"
APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || fail "The release APK was not built. Tell Claude: 'APK build failed'."
cp "$APK" submission/Vault_Board_HW02_release.apk
{ echo "Built: $(date)"; ls -l "$APK"; shasum -a 256 "$APK"; } | tee "$EVID/apk_info.txt"

step "6/6 Install that exact APK on an Android emulator"
if ! adb devices 2>/dev/null | grep -qw device; then
  AVD="$(flutter emulators 2>/dev/null | awk -F ' • ' 'NF>=4 && $1 != "Id" {print $1; exit}')"
  [ -n "$AVD" ] || fail "No Android emulator found. Create one in Android Studio (Device Manager), then run this again."
  echo "Starting Android emulator: $AVD"
  flutter emulators --launch "$AVD"
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
fi
adb shell getprop ro.product.model | sed 's/^/Device: /' | tee -a "$EVID/apk_info.txt"
adb install -r "$APK" 2>&1 | tee -a "$EVID/apk_info.txt"
adb shell monkey -p edu.gsu.csc4360.message_board -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

printf '\n\033[1;32mDone. Vault Board (release build) is open on the emulator.\033[0m\n'
echo "Second window for the live-update test:  flutter run -d chrome"
echo "Next: double-click 'Capture Evidence.command' (if present) or tell Claude 'done'."
read -r -p "Press Return to close." _
