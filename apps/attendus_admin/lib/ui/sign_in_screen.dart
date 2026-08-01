import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.onSignIn,
    this.onGoogleSignIn,
    this.errorText,
  });
  final Future<void> Function(String, String)? onSignIn;
  final Future<void> Function()? onGoogleSignIn;
  final String? errorText;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController(), password = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: SizedBox(
          width: 430,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/attendus_logo.png', height: 68),
                    const SizedBox(height: 24),
                    Text(
                      'Attendus Admin',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Secure operations console',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: email,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Administrator email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      autofillHints: const [AutofillHints.password],
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.errorText != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    else if (widget.onSignIn == null)
                      Consumer<SessionController>(
                        builder: (_, session, _) => session.error == null
                            ? const SizedBox.shrink()
                            : Semantics(
                                liveRegion: true,
                                child: Text(
                                  session.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                      )
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.login),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Text('Sign in'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _googleSignIn,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.white,
                              child: Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Continue with Google',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Access requires an administrator claim and an active role.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  void _submit() {
    if (email.text.trim().isNotEmpty && password.text.isNotEmpty) {
      if (widget.onSignIn != null) {
        widget.onSignIn!(email.text.trim(), password.text);
      } else {
        context.read<SessionController>().signIn(email.text, password.text);
      }
    }
  }

  void _googleSignIn() {
    if (widget.onGoogleSignIn != null) {
      widget.onGoogleSignIn!();
    } else {
      context.read<SessionController>().signInWithGoogle();
    }
  }
}

class UnauthorizedScreen extends StatelessWidget {
  const UnauthorizedScreen({
    super.key,
    required this.onRetry,
    required this.onSignOut,
  });
  final VoidCallback onRetry, onSignOut;
  @override
  Widget build(BuildContext context) => _AccessMessage(
    icon: Icons.gpp_bad_outlined,
    title: 'Access not authorized',
    message:
        'Your identity is valid, but no active Attendus administrator role permits access.',
    onRetry: onRetry,
    onSignOut: onSignOut,
  );
}

class AccessErrorScreen extends StatelessWidget {
  const AccessErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final String? message;
  final VoidCallback onRetry, onSignOut;
  @override
  Widget build(BuildContext context) => _AccessMessage(
    icon: Icons.cloud_off,
    title: 'Admin API unavailable',
    message: message ?? 'Could not verify administrator access.',
    onRetry: onRetry,
    onSignOut: onSignOut,
  );
}

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final IconData icon;
  final String title, message;
  final VoidCallback onRetry, onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 480,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    OutlinedButton(
                      onPressed: onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
