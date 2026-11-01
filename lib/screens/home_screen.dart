import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';
import 'account_sections.dart';

/// The logged-in area. Shows the profile and the account actions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});

  final AppState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ActionState {
  @override
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// GET /api/users/me
  Future<void> _refresh() => run(() async {
    app.updateUser(await app.api.me());
    return null;
  });

  @override
  Widget build(BuildContext context) {
    final user = app.user!;
    return PageShell(
      title: 'Your account',
      app: app,
      actions: [
        IconButton(
          tooltip: 'Reload profile',
          onPressed: busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        StatusText(error: error),
        ProfileSection(app: app, user: user),
        if (!user.emailVerified) VerifyEmailSection(app: app),
        ChangeEmailSection(app: app),
        ChangePasswordSection(app: app),
        LogoutSection(app: app),
        DeleteAccountSection(app: app),
      ],
    );
  }
}
