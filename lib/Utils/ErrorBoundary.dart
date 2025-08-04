import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )?
  errorBuilder;

  const ErrorBoundary({super.key, required this.child, this.errorBuilder});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // Set up error handling
    FlutterError.onError = _handleFlutterError;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    print('🚨 Flutter Error caught: ${details.exception}');
    print('Stack trace: ${details.stack}');

    // Use a post-frame callback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _error = details.exception;
          _stackTrace = details.stack;
          _hasError = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorBuilder?.call(context, _error!, _stackTrace) ??
          _buildDefaultErrorWidget();
    }

    return widget.child;
  }

  Widget _buildDefaultErrorWidget() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Colors.red[400],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The app encountered an unexpected error. Please try again.',
                  style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _stackTrace = null;
                          _hasError = false;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        SystemNavigator.pop();
                      },
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Restart App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        foregroundColor: const Color(0xFF1A1A1A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Debug Information:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Error: ${_error.toString()}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (_stackTrace != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Stack Trace: ${_stackTrace.toString()}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    FlutterError.onError = null;
    super.dispose();
  }
}

// Extension to easily wrap widgets with error boundary
extension ErrorBoundaryExtension on Widget {
  Widget withErrorBoundary({
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace)?
    errorBuilder,
  }) {
    return ErrorBoundary(errorBuilder: errorBuilder, child: this);
  }
}
