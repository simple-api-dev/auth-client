import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'ui.dart';

/// Shows the profile and edits the name: PUT /api/users/me {name}
class ProfileSection extends StatefulWidget {
  const ProfileSection({super.key, required this.app, required this.user});

  final AppState app;
  final User user;

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> with ActionState {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);

  @override
  AppState get app => widget.app;

  @override
  void didUpdateWidget(ProfileSection old) {
    super.didUpdateWidget(old);
    // Keep the field in step when the profile is reloaded from /me.
    if (old.user.name != widget.user.name) _name.text = widget.user.name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Form(
      key: _form,
      child: Section(
        title: 'Profile',
        subtitle:
            'Email: ${user.email}  '
            '(${user.emailVerified ? 'verified' : 'not verified'})\n'
            'User id: ${user.id}'
            '${user.createdAt == null ? '' : '   Created: ${user.createdAt}'}',
        children: [
          StatusText(error: error, info: info),
          field(_name, 'Name', validator: notEmpty),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    await run(() async {
                      app.updateUser(await app.api.updateMe(name: _name.text.trim()));
                      return 'Name saved.';
                    });
                  },
            child: const Text('Save name'),
          ),
        ],
      ),
    );
  }
}

/// POST /api/users/me/email/send-code, then POST /api/users/me/email/verify
class VerifyEmailSection extends StatefulWidget {
  const VerifyEmailSection({super.key, required this.app});

  final AppState app;

  @override
  State<VerifyEmailSection> createState() => _VerifyEmailSectionState();
}

class _VerifyEmailSectionState extends State<VerifyEmailSection> with ActionState {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  AppState get app => widget.app;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: 'Verify your email',
        subtitle:
            'Ask for a 6-digit code, then type it below. '
            'One email per minute; the code works once for 15 minutes.',
        children: [
          StatusText(error: error, info: info),
          OutlinedButton(
            onPressed: busy ? null : () => run(app.api.sendVerificationCode),
            child: const Text('Email me a code'),
          ),
          const SizedBox(height: 12),
          field(_code, 'Code from the email', keyboard: TextInputType.number, validator: notEmpty),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    await run(() async {
                      app.updateUser(await app.api.verifyEmail(_code.text.trim()));
                      return 'Email verified.';
                    });
                  },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }
}

/// PUT /api/users/me {email, current_password}
class ChangeEmailSection extends StatefulWidget {
  const ChangeEmailSection({super.key, required this.app});

  final AppState app;

  @override
  State<ChangeEmailSection> createState() => _ChangeEmailSectionState();
}

class _ChangeEmailSectionState extends State<ChangeEmailSection> with ActionState {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _current = TextEditingController();

  @override
  AppState get app => widget.app;

  @override
  void dispose() {
    _email.dispose();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: 'Change email',
        subtitle: 'Needs your current password. The new address must be verified again.',
        children: [
          StatusText(error: error, info: info),
          field(_email, 'New email', keyboard: TextInputType.emailAddress, validator: notEmpty),
          field(_current, 'Current password', obscure: true, validator: notEmpty),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    final ok = await run(() async {
                      app.updateUser(
                        await app.api.updateMe(
                          email: _email.text.trim(),
                          currentPassword: _current.text,
                        ),
                      );
                      return 'Email changed. Please verify the new address.';
                    });
                    if (ok) {
                      _email.clear();
                      _current.clear();
                    }
                  },
            child: const Text('Change email'),
          ),
        ],
      ),
    );
  }
}

/// PUT /api/users/me {password, current_password}
class ChangePasswordSection extends StatefulWidget {
  const ChangePasswordSection({super.key, required this.app});

  final AppState app;

  @override
  State<ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<ChangePasswordSection> with ActionState {
  final _form = GlobalKey<FormState>();
  final _new = TextEditingController();
  final _current = TextEditingController();

  @override
  AppState get app => widget.app;

  @override
  void dispose() {
    _new.dispose();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: 'Change password',
        subtitle: 'Needs your current password. Other devices are logged out.',
        children: [
          StatusText(error: error, info: info),
          field(_new, 'New password (8 to 72 characters)', obscure: true, validator: validPassword),
          field(_current, 'Current password', obscure: true, validator: notEmpty),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    final ok = await run(() async {
                      app.updateUser(
                        await app.api.updateMe(password: _new.text, currentPassword: _current.text),
                      );
                      return 'Password changed.';
                    });
                    if (ok) {
                      _new.clear();
                      _current.clear();
                    }
                  },
            child: const Text('Change password'),
          ),
        ],
      ),
    );
  }
}

/// POST /api/users/logout (this device) or ?all=true (every device)
class LogoutSection extends StatefulWidget {
  const LogoutSection({super.key, required this.app});

  final AppState app;

  @override
  State<LogoutSection> createState() => _LogoutSectionState();
}

class _LogoutSectionState extends State<LogoutSection> with ActionState {
  @override
  AppState get app => widget.app;

  Future<void> _logout({required bool all}) async {
    final ok = await run(() async {
      await app.api.logout(all: all);
      return null;
    });
    if (ok) app.signOutLocal();
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Log out',
      children: [
        StatusText(error: error, info: info),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: busy ? null : () => _logout(all: false),
              child: const Text('Log out this device'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => _logout(all: true),
              child: const Text('Log out all devices'),
            ),
          ],
        ),
      ],
    );
  }
}

/// DELETE /api/users/me {password}
class DeleteAccountSection extends StatefulWidget {
  const DeleteAccountSection({super.key, required this.app});

  final AppState app;

  @override
  State<DeleteAccountSection> createState() => _DeleteAccountSectionState();
}

class _DeleteAccountSectionState extends State<DeleteAccountSection> with ActionState {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  AppState get app => widget.app;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This permanently deletes your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await run(() async {
      await app.api.deleteMe(_password.text);
      return null;
    });
    if (ok) app.signOutLocal(notice: 'Your account was deleted.');
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Section(
        title: 'Delete account',
        subtitle: 'Needs your password. This cannot be undone.',
        children: [
          StatusText(error: error, info: info),
          field(_password, 'Password', obscure: true, validator: notEmpty),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: busy ? null : _delete,
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
  }
}
