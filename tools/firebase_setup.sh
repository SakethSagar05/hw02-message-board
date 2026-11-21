#!/usr/bin/env bash
# One-time Firebase setup (interactive). Creates or selects the Firebase
# project, creates the Firestore database, asks you to switch on
# Email/Password, and runs flutterfire configure for Android + web.
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/env.sh
need firebase "Run: npm install -g firebase-tools" || exit 1
if ! command -v flutterfire >/dev/null 2>&1; then
  echo "==> Installing the FlutterFire CLI"
  dart pub global activate flutterfire_cli || exit 1
fi

if [ -f lib/firebase_options.dart ] && [ -n "$(project_id)" ]; then
  echo "Firebase already configured for project $(project_id). Skipping."
  exit 0
fi

echo "==> Checking the Firebase CLI sign-in"
if ! firebase login:list 2>/dev/null | grep -q "@"; then
  firebase login || exit 1
fi
firebase login:list | grep "@" | head -1

echo
echo "Which Firebase project should Vault Board use?"
echo "  - Press Return to CREATE a new project (recommended)."
echo "  - Or type an existing project ID. Deploying this app's rules REPLACES"
echo "    that project's Firestore rules, so do not reuse ica13-auth unless"
echo "    you no longer need ICA16's rules there."
read -r -p "Project ID [new]: " PROJECT
if [ -z "$PROJECT" ]; then
  PROJECT="vault-board-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
  echo "==> Creating Firebase project $PROJECT"
  if ! firebase projects:create "$PROJECT" --display-name "HW02 Vault Board"; then
    echo
    echo "Project creation failed (see above). Create one in the console:"
    echo "  https://console.firebase.google.com/  ->  Add project"
    read -r -p "Then type its project ID: " PROJECT
  fi
fi
[ -n "$PROJECT" ] || { echo "No project ID given."; exit 1; }
echo "$PROJECT" > .firebase_project
printf '{\n  "projects": {\n    "default": "%s"\n  }\n}\n' "$PROJECT" > .firebaserc

echo "==> Making sure the Firestore database exists"
if firebase firestore:databases:list --project "$PROJECT" 2>/dev/null | grep -q "(default)"; then
  echo "Firestore (default) database already exists."
elif firebase firestore:databases:create "(default)" --location nam5 --project "$PROJECT"; then
  echo "Created the Firestore database in nam5 (United States)."
else
  echo "Could not create it from the CLI. Opening the console: click 'Create database',"
  echo "pick a US location and 'Start in production mode'."
  open "https://console.firebase.google.com/project/$PROJECT/firestore"
  read -r -p "Press Return when the database exists. " _
fi

echo
echo "==> Switch on Email/Password sign-in (one click)"
echo "In the page that opens: Get started (if shown) -> Email/Password -> Enable -> Save."
open "https://console.firebase.google.com/project/$PROJECT/authentication/providers"
read -r -p "Press Return when Email/Password shows as Enabled. " _

echo "==> flutterfire configure (Android + web)"
flutterfire configure \
  --project="$PROJECT" \
  --platforms=android,web \
  --android-package-name=edu.gsu.csc4360.message_board \
  --out=lib/firebase_options.dart \
  --yes || exit 1

echo "Firebase setup finished for $PROJECT."
