import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../widgets.dart';

/// Forgot password: POST /api/users/forgot, then POST /api/users/reset.
class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key, required this.app});

  final AppController app;

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Forgot password',
      children: [
        _SendCode(app: widget.app, email: _email),
        _SetPassword(app: widget.app, email: _email),
      ],
    );
  }
}

class _SendCode extends StatefulWidget {
  const _SendCode({required this.app, required this.email});

  final AppController app;
  final TextEditingController email;

  @override
  State<_SendCode> createState() => _SendCodeState();
}

class _SendCodeState extends State<_SendCode> with ActionState {
  final _form = GlobalKey<FormState>();

  @override
  AppController get app => widget.app;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: '1. Email me a code',
        subtitle: 'A 6 digit code is emailed if the account exists. '
            'The answer is always the same, so nobody can discover who is registered.',
        children: [
          StatusText(error: error, info: info),
          field(widget.email, 'Email', keyboard: TextInputType.emailAddress, validator: notEmpty),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    if (_form.currentState!.validate()) {
                      run(() => app.api.forgotPassword(widget.email.text.trim()));
                    }
                  },
            child: const Text('Send code'),
          ),
        ],
      ),
    );
  }
}

class _SetPassword extends StatefulWidget {
  const _SetPassword({required this.app, required this.email});

  final AppController app;
  final TextEditingController email;

  @override
  State<_SetPassword> createState() => _SetPasswordState();
}

class _SetPasswordState extends State<_SetPassword> with ActionState {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();

  @override
  AppController get app => widget.app;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    final ok = await run(() async {
      await app.api.resetPassword(
        email: widget.email.text.trim(),
        code: _code.text.trim(),
        password: _password.text,
      );
      return 'Password updated. Go back and log in with the new password.';
    });
    if (ok) {
      _code.clear();
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: '2. Set a new password',
        subtitle: 'The code works once, expires after 15 minutes and allows 5 wrong attempts. '
            'Resetting logs out every session.',
        children: [
          StatusText(error: error, info: info),
          field(_code, 'Code from the email', keyboard: TextInputType.number, validator: notEmpty),
          field(_password, 'New password (8 to 72 characters)',
              obscure: true, validator: validPassword),
          FilledButton(
            onPressed: busy ? null : _reset,
            child: const Text('Set new password'),
          ),
        ],
      ),
    );
  }
}
