import 'package:flutter/material.dart';

typedef StartupRetry = Future<void> Function();

/// Keeps Firebase-dependent widgets out of the tree until Firebase is ready,
/// while still allowing Flutter to paint immediately.
class AppStartupGate extends StatefulWidget {
  const AppStartupGate({
    super.key,
    required this.initialization,
    required this.onRetry,
    required this.child,
    this.onReady,
  });

  final Future<void> initialization;
  final StartupRetry onRetry;
  final Widget child;
  final VoidCallback? onReady;

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  late Future<void> _initialization;
  Future<void>? _observedInitialization;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _setInitialization(widget.initialization);
  }

  @override
  void didUpdateWidget(covariant AppStartupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialization, widget.initialization)) {
      _attempt++;
      _setInitialization(widget.initialization);
    }
  }

  void _setInitialization(Future<void> initialization) {
    _initialization = initialization;
    _observeReady(initialization);
  }

  void _observeReady(Future<void> initialization) {
    _observedInitialization = initialization;
    initialization.then(
      (_) {
        if (!mounted || !identical(_observedInitialization, initialization)) {
          return;
        }
        widget.onReady?.call();
      },
      onError: (_) {
        // FutureBuilder renders the actionable error state.
      },
    );
  }

  void _retry() {
    setState(() {
      _attempt++;
      _setInitialization(widget.onRetry());
    });
  }

  @override
  void dispose() {
    _observedInitialization = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      key: ValueKey(_attempt),
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.child;
        }

        if (snapshot.hasError) {
          return _StartupStatusScreen(
            title: 'Unable to start Attendus',
            message: 'Check your connection, then try again.',
            actionLabel: 'Try again',
            onAction: _retry,
          );
        }

        return const _StartupStatusScreen(
          title: 'Attendus',
          message: 'Checking your session...',
        );
      },
    );
  }
}

class _StartupStatusScreen extends StatelessWidget {
  const _StartupStatusScreen({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'attendus_logo_only.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.event_available,
                      size: 72,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (onAction == null)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
