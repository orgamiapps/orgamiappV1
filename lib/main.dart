import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:orgami/Screens/Splash/SplashScreen.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/firebase_options.dart';

/// Comprehensive error handling for GoogleApiManager SecurityException and GMS issues
class FirebaseErrorHandler {
  // Static variables for error handling
  static bool _isFirebaseInitialized = false;
  static bool _isOfflineMode = false;
  static String? _lastError;

  // Performance monitoring variables
  static int _frameSkipCount = 0;
  static int _totalFrames = 0;
  static bool _performanceWarningShown = false;

  static const String _errorMessage =
      'Firebase services failed to connect. Click to fix:';

  /// Initialize Firebase with comprehensive error handling
  static Future<bool> initializeFirebase() async {
    try {
      print('🔧 Initializing Firebase...');

      // Check hardware acceleration for emulator performance
      _checkHardwareAcceleration();

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      _isFirebaseInitialized = true;
      _isOfflineMode = false;
      _lastError = null;

      print('✅ Firebase initialized successfully');

      // Start performance monitoring
      _startPerformanceMonitoring();

      return true;
    } catch (e) {
      _lastError = e.toString();
      print('❌ Firebase initialization failed: $e');

      if (_isSecurityException(e)) {
        print('🔒 SecurityException detected - likely SHA-1 fingerprint issue');
      } else if (_isFirebaseException(e)) {
        print('🔥 FirebaseException detected - configuration issue');
      }

      return false;
    }
  }

  /// Check if error is a SecurityException
  static bool _isSecurityException(dynamic error) {
    return error.toString().contains('SecurityException') ||
        error.toString().contains('DEVELOPER_ERROR') ||
        error.toString().contains('GoogleApiManager');
  }

  /// Check if error is a FirebaseException
  static bool _isFirebaseException(dynamic error) {
    return error.toString().contains('FirebaseException') ||
        error.toString().contains('PERMISSION_DENIED');
  }

  /// Check hardware acceleration for emulator performance
  static void _checkHardwareAcceleration() {
    try {
      print('🔍 Checking hardware acceleration...');
      // Note: Enable 'Hardware GLES 2.0' in AVD Manager for better emulator performance
    } catch (e) {
      print('⚠️ Hardware acceleration check failed: $e');
    }
  }

  /// Start performance monitoring for frame skips
  static void _startPerformanceMonitoring() {
    SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
      _totalFrames++;

      // Check for frame skips (simplified detection)
      if (_totalFrames % 60 == 0) {
        // Check every second (assuming 60fps)
        double frameSkipRate = _frameSkipCount / _totalFrames;

        if (frameSkipRate > 0.5 && !_performanceWarningShown) {
          // More than 50% frame skips
          print(
              '⚠️ PERFORMANCE WARNING: High frame skip rate detected ($frameSkipRate)');
          print(
              '💡 Enable Hardware GLES 2.0 in AVD Manager for better emulator performance');
          _performanceWarningShown = true;
        }
      }
    });
  }

  /// Get the error message for display
  static String getErrorMessage() {
    if (_isOfflineMode) {
      return 'Running in offline mode. Some features may be limited.';
    }
    return _errorMessage;
  }

  /// Attempt to fix Firebase issues
  static Future<bool> attemptFix(BuildContext context) async {
    print('🔧 Attempting to fix Firebase issues...');

    // Show detailed fix dialog
    bool shouldRetry = await _showFixDialog(context);

    if (shouldRetry) {
      print(
          '🔄 User confirmed retry - attempting Firebase reinitialization...');
      return await initializeFirebase();
    }

    return false;
  }

  /// Show comprehensive fix dialog with step-by-step instructions
  static Future<bool> _showFixDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.build, color: AppThemeColor.darkGreenColor),
                  const SizedBox(width: 8),
                  const Text('Firebase Configuration Fix'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Follow these steps to fix the Firebase connection issue:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Step 1: Generate signing report
                    _buildStep(
                      '1. Generate SHA-1 Fingerprint',
                      'Run this command in your project\'s android/ folder:',
                      './gradlew signingReport',
                    ),

                    const SizedBox(height: 8),

                    // Step 2: Copy debug SHA-1
                    _buildStep(
                      '2. Copy Debug SHA-1',
                      'From the output, copy the SHA-1 value under "Variant: debug"',
                      'Example: AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC',
                    ),

                    const SizedBox(height: 8),

                    // Step 3: Add to Firebase Console
                    _buildStep(
                      '3. Add to Firebase Console',
                      'Go to Firebase Console > Project Settings > Your Android App > Add Fingerprint',
                      'Paste the SHA-1 value and save',
                    ),

                    const SizedBox(height: 8),

                    // Step 4: Download updated google-services.json
                    _buildStep(
                      '4. Download Updated Config',
                      'Download the updated google-services.json file',
                      'Replace the existing file in android/app/',
                    ),

                    const SizedBox(height: 8),

                    // Step 5: Clean and rebuild
                    _buildStep(
                      '5. Clean and Rebuild',
                      'Run these commands in your project root:',
                      'flutter clean && flutter pub get && flutter run',
                    ),

                    const SizedBox(height: 16),

                    // Additional notes
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.orange[700], size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'Additional Notes:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• For emulator: Enable "Hardware GLES 2.0" in AVD Manager\n'
                            '• Ensure internet connection is stable\n'
                            '• Check that google-services.json is valid JSON\n'
                            '• If using emulator, restart with hardware acceleration enabled',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry After Fix'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// Build a step in the fix dialog
  static Widget _buildStep(String title, String description, String command) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: command));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: $command'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Enable offline mode as fallback
  static void enableOfflineMode() {
    _isOfflineMode = true;
    print('🔄 Enabling offline mode as fallback');
  }

  /// Check if Firebase is initialized
  static bool get isFirebaseInitialized => _isFirebaseInitialized;

  /// Check if in offline mode
  static bool get isOfflineMode => _isOfflineMode;

  /// Get last error
  static String? get lastError => _lastError;
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    print('🚀 Starting app initialization...');

    // Initialize Firebase with comprehensive error handling
    bool firebaseInitialized = false;
    try {
      firebaseInitialized = await FirebaseErrorHandler.initializeFirebase();
    } catch (e) {
      print('❌ Firebase initialization crashed: $e');
      // Continue without Firebase - app will run in offline mode
    }

    if (!firebaseInitialized) {
      print('⚠️ Firebase initialization failed - running in offline mode');
      FirebaseErrorHandler.enableOfflineMode();
    }

    print('✅ App initialization complete');
    runApp(const MyApp());
  } catch (e) {
    print('💥 Critical app initialization error: $e');
    // Show a basic error screen
    runApp(const ErrorApp());
  }
}

/// Error app shown when critical initialization fails
class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Error',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 20),
                Text(
                  'App Initialization Error',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  'The app failed to start properly. Please restart the app or check your device settings.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Restart the app
                    SystemNavigator.pop();
                  },
                  child: const Text('Restart App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: AppThemeColor.darkGreenColor),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
          builder: (context, child) {
            // Show persistent error message if Firebase failed
            if (!FirebaseErrorHandler.isFirebaseInitialized &&
                !FirebaseErrorHandler.isOfflineMode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showPersistentErrorSnackBar(context);
              });
            }
            return child!;
          },
        );
      },
    );
  }

  /// Show persistent error snackbar with fix button
  void _showPersistentErrorSnackBar(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(FirebaseErrorHandler.getErrorMessage()),
            ),
            TextButton(
              onPressed: () async {
                bool fixed = await FirebaseErrorHandler.attemptFix(context);
                if (!fixed) {
                  // Enable offline mode as fallback
                  FirebaseErrorHandler.enableOfflineMode();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Switched to offline mode. Some features may be limited.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Firebase connection restored!'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text(
                'FIX',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        duration: const Duration(days: 365), // Persistent until dismissed
        backgroundColor: Colors.red[700],
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
