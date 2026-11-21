import 'package:flutter/foundation.dart';

/// Off by default: the release APK talks to the real Firebase project.
/// Extra Spice #1 (Emulator Explorer) turns it on:
///   flutter run --dart-define=USE_EMULATOR=true
const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// For a physical phone, pass the computer's LAN address:
///   flutter run --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=192.168.1.20
const String _emulatorHostOverride = String.fromEnvironment('EMULATOR_HOST');

/// The Android emulator reaches the computer through 10.0.2.2; web and
/// desktop share the computer's localhost.
String get emulatorHost {
  if (_emulatorHostOverride.isNotEmpty) return _emulatorHostOverride;
  if (kIsWeb) return 'localhost';
  return defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
}

const String appName = 'Vault Board';
