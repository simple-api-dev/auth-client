import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import 'ui.dart';
import 'settings_screen.dart';

/// Shown when no key is built in and the user has not pasted one. Nothing
/// here talks to the API.
class NoKeyScreen extends StatelessWidget {
  const NoKeyScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'SimpleAPI Auth sample',
      children: [
        Section(
          title: 'This demo has no key configured',
          subtitle: 'Get a free key, then paste it under Settings.',
          children: [
            FilledButton(
              onPressed: () => app.openUrl(getKeyUrl),
              child: const Text('Get a free key'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => SettingsScreen(app: app))),
              child: const Text('Settings'),
            ),
          ],
        ),
      ],
    );
  }
}
