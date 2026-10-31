import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'key_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/no_key_screen.dart';

void main() {
  runApp(AuthClientApp(controller: AppController(keyStore: createKeyStore())));
}

class AuthClientApp extends StatelessWidget {
  const AuthClientApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleApi Auth sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // Which screen to show depends only on the controller's state.
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.hasKey) return NoKeyScreen(app: controller);
          if (!controller.loggedIn) return LoginScreen(app: controller);
          return HomeScreen(app: controller);
        },
      ),
    );
  }
}
