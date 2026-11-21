import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is initialized behind the splash screen (see SplashScreen), so
  // the user sees the app immediately and a failure gets a Retry button.
  runApp(const MessageBoardApp());
}

class MessageBoardApp extends StatelessWidget {
  const MessageBoardApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5C3A24); // warm umber, like the assignment hub
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
