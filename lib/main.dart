import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(AuthClientApp(controller: AppState()));
}

class AuthClientApp extends StatelessWidget {
  const AuthClientApp({super.key, required this.controller});

  final AppState controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleAPI Auth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0066CC), useMaterial3: true),
      // Which screen to show depends only on the controller's state.
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            controller.loggedIn ? HomeScreen(app: controller) : LoginScreen(app: controller),
      ),
    );
  }
}
