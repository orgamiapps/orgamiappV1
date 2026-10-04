import 'package:attendus/models/notification_model.dart';

typedef LoadNotificationPreferences =
    Future<Map<String, dynamic>?> Function(String uid);
typedef SaveNotificationPreferences =
    Future<void> Function(String uid, Map<String, dynamic> data);

/// Prevents a delayed load or save for a previous account from changing defaults.
class NotificationPreferencesService {
  NotificationPreferencesService({
    required this.currentUid,
    required this.load,
    required this.save,
  });
  final String? Function() currentUid;
  final LoadNotificationPreferences load;
  final SaveNotificationPreferences save;
  String? _owner;
  UserNotificationSettings? _cached;
  Future<void> _writes = Future<void>.value();
  UserNotificationSettings? get cached =>
      _owner == currentUid() ? _cached : null;

  Future<UserNotificationSettings> read() async {
    final uid = currentUid();
    if (uid == null) {
      throw StateError('Sign in to load notification preferences.');
    }
    final data = await load(uid);
    if (currentUid() != uid) {
      throw StateError('Account changed. Reload preferences.');
    }
    _owner = uid;
    return _cached = data == null
        ? UserNotificationSettings()
        : UserNotificationSettings.fromMap(data);
  }

  Future<void> write(UserNotificationSettings settings) {
    final uid = currentUid();
    if (uid == null) {
      return Future.error(
        StateError('Sign in to save notification preferences.'),
      );
    }
    final next = _writes.then((_) async {
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      await save(uid, settings.toMap());
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      _owner = uid;
      _cached = settings;
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
