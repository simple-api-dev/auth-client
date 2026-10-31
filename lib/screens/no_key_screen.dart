import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../config.dart';
import '../widgets.dart';
import 'settings_screen.dart';

/// Shown when no key is built in and the user has not pasted one. Nothing
/// here talks to the API.
class NoKeyScreen extends StatelessWidget {
  const NoKeyScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'SimpleApi Auth sample',
      children: [
        Section(
          title: 'This demo has no key configured',
          subtitle: 'The site owner has not set a demo key, so the app cannot call '
              'the API yet. Get a free key and paste it under Settings; it is saved '
              'only in this browser.',
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
