import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';

/// POST /api/users/register (also logs the new user in)
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.app});

  final AppState app;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with ActionState {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  AppState get app => widget.app;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    final ok = await run(() async {
      final session = await app.api.register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      app.signIn(session);
      return null;
    });
    // The home screen is now showing underneath; close this page.
    if (ok && mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Create an account',
      children: [
        Form(
          key: _form,
          child: Section(
            title: 'Register',
            subtitle: 'The free tier allows 25 users per key.',
            children: [
              if (app.usingDemoKey) const DemoNotice(),
              StatusText(error: error, info: info),
              field(_name, 'Name', validator: notEmpty),
              field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: notEmpty),
              field(_password, 'Password',
                  helper: 'At least 8 characters',
                  obscure: true, validator: validPassword, onSubmitted: (_) => _register()),
              FilledButton(
                onPressed: busy ? null : _register,
                child: Text(busy ? 'Creating...' : 'Create account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
