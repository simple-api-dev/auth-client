import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../widgets.dart';

/// Paste the SimpleApi key. It is stored only in this browser's localStorage.
class KeyScreen extends StatefulWidget {
  const KeyScreen({super.key, required this.app});

  final AppController app;

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) widget.app.saveKey(_key.text);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'SimpleApi Auth sample',
      children: [
        Form(
          key: _form,
          child: Section(
            title: 'Your SimpleApi key',
            subtitle: 'Get a free key at https://keys.simpleapi.dev/?product=auth '
                'and paste it here. It is saved only in this browser (localStorage) '
                'and sent to auth.simpleapi.dev as the apikey query parameter.',
            children: [
              field(_key, 'API key', validator: notEmpty, onSubmitted: (_) => _save()),
              FilledButton(onPressed: _save, child: const Text('Save key')),
            ],
          ),
        ),
      ],
    );
  }
}
