#!/usr/bin/env bash
# One-time project setup. Safe to run again.
# Adds the Android and web platform folders, fetches packages and applies the
# Android settings Firebase needs.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/env.sh
need flutter "Install the Flutter SDK or open a terminal where 'flutter --version' works."

if [ ! -d android ] || [ ! -d web ]; then
  echo "==> Adding the Android and web platforms"
  # Keep the hand-written files safe in case flutter create replaces any.
  BACKUP="$(mktemp -d)"
  cp -R lib test README.md pubspec.yaml .gitignore analysis_options.yaml "$BACKUP"/
  flutter create . --platforms=android,web --project-name message_board --org edu.gsu.csc4360
  rm -rf lib test
  cp -R "$BACKUP"/lib "$BACKUP"/test .
  cp "$BACKUP"/README.md "$BACKUP"/pubspec.yaml "$BACKUP"/.gitignore "$BACKUP"/analysis_options.yaml .
else
  echo "==> android/ and web/ already exist, skipping flutter create"
fi

flutter pub get

GRADLE=android/app/build.gradle.kts
if [ -f "$GRADLE" ] && ! grep -q "maxOf(flutter.minSdkVersion, 23)" "$GRADLE"; then
  echo "==> Setting Android minSdk to at least 23 (required by Firebase)"
  perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = maxOf(flutter.minSdkVersion, 23)/' "$GRADLE"
fi
GRADLE_GROOVY=android/app/build.gradle
if [ -f "$GRADLE_GROOVY" ] && ! grep -q "Math.max(flutter.minSdkVersion, 23)" "$GRADLE_GROOVY"; then
  perl -pi -e 's/minSdk(Version)?\s*=?\s*flutter\.minSdkVersion/minSdk = Math.max(flutter.minSdkVersion, 23)/' "$GRADLE_GROOVY"
fi

MAIN=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$MAIN"; then
  echo "==> Declaring INTERNET in the main manifest so the RELEASE APK can reach Firebase"
  perl -0pi -e 's#(<manifest[^>]*>)#$1\n    <uses-permission android:name="android.permission.INTERNET" />#' "$MAIN"
fi
perl -pi -e 's/android:label="message_board"/android:label="Vault Board"/' "$MAIN"

echo "==> Allowing plain HTTP in DEBUG builds only (for the local Firebase emulators)"
mkdir -p android/app/src/debug
cat > android/app/src/debug/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- Debug only: the Firebase emulators on 10.0.2.2 speak plain HTTP. -->
    <application android:usesCleartextTraffic="true"/>
</manifest>
XML

echo "Setup finished."
