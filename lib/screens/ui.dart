import 'package:flutter/material.dart';

import '../app_state.dart';
import '../auth_api.dart';
import '../config.dart';

/// A centered, scrollable page with a sensible maximum width.
class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.app,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final EdgeInsets padding;

  /// Pass the app on top-level screens: they get a back arrow to simpleapi.dev. Inner screens leave it null and
  /// keep the normal in-app back arrow.
  final AppState? app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: app == null
            ? null
            : IconButton(
                tooltip: 'Back to SimpleAPI',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => app!.openUrl(homeUrl),
              ),
        title: Text(title),
        actions: actions,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: padding, children: children),
        ),
      ),
    );
  }
}

/// A titled card that groups one feature.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A text field with consistent spacing.
Widget field(
  TextEditingController controller,
  String label, {
  bool obscure = false,
  String? helper,
  TextInputType? keyboard,
  String? Function(String?)? validator,
  void Function(String)? onSubmitted,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

String? notEmpty(String? value) => (value == null || value.trim().isEmpty) ? 'Required' : null;

String? validPassword(String? value) {
  if (value == null || value.length < 8) return 'At least 8 characters';
  if (value.length > 72) return 'At most 72 characters';
  return null;
}

/// An API timestamp such as `2026-11-01T05:32:25Z` as a date for people, `1 Nov 2026`, in the viewer's time zone.
/// Null when there is no valid timestamp, so a raw value never reaches the screen.
String? readableDate(String? timestamp) {
  final date = timestamp == null ? null : DateTime.tryParse(timestamp)?.toLocal();
  if (date == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

const demoFullMessage = 'The demo is full. It resets every night.';

const demoNoticeText =
    'This is a shared demo. Data resets every night. '
    'Do not use a real password or any private details.';

/// Shown when someone tries to change or delete the shared demo account, which would lock everyone else out.
const demoLockedMessage =
    'The shared demo account cannot be changed or deleted. '
    'Create your own account to try this.';

/// Shown on the login and register screens.
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(demoNoticeText, style: TextStyle(color: scheme.onSecondaryContainer)),
    );
  }
}

/// Shows the result of the last action: an error in red, otherwise a note.
class StatusText extends StatelessWidget {
  const StatusText({super.key, this.error, this.info});

  final String? error;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = error ?? info;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: TextStyle(color: error != null ? scheme.error : scheme.primary)),
    );
  }
}

/// Shared "run an API call, show busy/error/info" logic for the forms.
///
/// The action returns a message to show on success (or null). API failures
/// are turned into plain-language text; a 401 on a protected call means the
/// token is gone, so the user is sent back to the log-in screen.
mixin ActionState<T extends StatefulWidget> on State<T> {
  AppState get app;

  bool busy = false;
  String? error;
  String? info;

  /// Shows [message] as the error without calling the API (used to protect the shared demo account).
  void refuse(String message) => setState(() {
    error = message;
    info = null;
  });

  /// Returns true when the action succeeded.
  Future<bool> run(Future<String?> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => info = message);
      return true;
    } on ApiException catch (e) {
      if (e.isBadSession) app.signOutLocal(notice: describeError(e));
      // The demo key holds only 25 users. Once they are used up nobody can register, so say so.
      final text = e.isUserCapReached ? demoFullMessage : describeError(e);
      if (mounted) setState(() => error = text);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
