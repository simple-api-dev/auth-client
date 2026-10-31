import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../auth_api.dart';
import '../config.dart';
import '../widgets.dart';

/// Use your own SimpleApi key instead of the demo key built into the site.
///
/// The pasted key is checked with [AuthApi.checkKey], then kept only in this
/// browser's localStorage. It overrides the build-time key until you go back.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});

  final AppController app;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with ActionState {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();

  @override
  AppController get app => widget.app;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final candidate = _key.text.trim();
    final ok = await run(() async {
      await AuthApi(apiKey: candidate, client: app.client).checkKey();
      app.useOwnKey(candidate);
      return null;
    });
    if (ok && mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _backToDemo() {
    app.useDemoKey();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final status = app.usingOwnKey
        ? 'You are using your own key.'
        : app.usingDemoKey
            ? 'You are using the shared demo key.'
            : 'No key is configured.';
    return PageShell(
      title: 'Settings',
      children: [
        Form(
          key: _form,
          child: Section(
            title: 'Use your own key',
            subtitle: '$status Get a free key at $getKeyUrl and paste it here. It is '
                'checked with the API, saved only in this browser (localStorage) and '
                'sent to auth.simpleapi.dev as the apikey query parameter. It '
                'overrides the demo key.',
            children: [
              StatusText(error: error, info: info),
              field(_key, 'API key', validator: notEmpty, onSubmitted: (_) => _save()),
              FilledButton(
                onPressed: busy ? null : _save,
                child: Text(busy ? 'Checking...' : 'Save key'),
              ),
              if (app.usingOwnKey)
                TextButton(
                  onPressed: _backToDemo,
                  child: Text(app.buildKey.isNotEmpty
                      ? 'Go back to the demo key'
                      : 'Remove my key'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
