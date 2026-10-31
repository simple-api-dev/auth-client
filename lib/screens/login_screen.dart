import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../widgets.dart';
import 'register_screen.dart';
import 'reset_screen.dart';
import 'settings_screen.dart';

/// POST /api/users/login
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.app});

  final AppController app;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with ActionState {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  AppController get app => widget.app;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    await run(() async {
      final session = await app.api.login(email: _email.text.trim(), password: _password.text);
      app.signIn(session);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Log in',
      children: [
        Form(
          key: _form,
          child: Section(
            title: 'Log in',
            subtitle: 'After 5 wrong passwords an email is locked for 15 minutes.'
                '${app.usingDemoKey ? ' This demo shares one key, so accounts are public.' : ''}',
            children: [
              StatusText(error: error ?? app.notice, info: info),
              field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: notEmpty),
              field(_password, 'Password',
                  obscure: true, validator: notEmpty, onSubmitted: (_) => _login()),
              FilledButton(
                onPressed: busy ? null : _login,
                child: Text(busy ? 'Logging in...' : 'Log in'),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => RegisterScreen(app: app))),
              child: const Text('Create an account'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => ResetScreen(app: app))),
              child: const Text('Forgot password?'),
            ),
            TextButton(
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
