import 'package:attendus/Services/guest_mode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AccountFeature {
  groups,
  messages,
  profile,
  account,
  notifications,
  createEvent,
  createGroup,
  joinGroup,
  registration,
  tickets,
  comments,
  favorites,
  feedback,
  accessRequest,
  attendeeProfiles,
  analytics,
}

class AccountAccessService {
  const AccountAccessService._();

  static bool get isGuest {
    final service = GuestModeService();
    if (service.isInitialized) return service.isGuestMode;
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user?.isAnonymous ?? false;
    } catch (_) {
      // Lightweight widget tests and previews may intentionally omit Firebase.
      return false;
    }
  }

  static String title(AccountFeature feature) => switch (feature) {
    AccountFeature.createEvent => 'Create events with an account',
    AccountFeature.groups ||
    AccountFeature.createGroup ||
    AccountFeature.joinGroup => 'Join the Attendus community',
    AccountFeature.messages => 'Sign in to message',
    AccountFeature.profile ||
    AccountFeature.attendeeProfiles => 'Profiles require an account',
    AccountFeature.notifications => 'Keep up with your activity',
    AccountFeature.account => 'Manage your Attendus account',
    AccountFeature.registration ||
    AccountFeature.tickets => 'Save this event to your account',
    AccountFeature.analytics => 'Unlock event analytics',
    _ => 'Sign in to continue',
  };

  static String message(AccountFeature feature) => switch (feature) {
    AccountFeature.createEvent =>
      'Create an account to publish events and manage attendance.',
    AccountFeature.groups =>
      'Create an account to discover, create, and join groups.',
    AccountFeature.createGroup =>
      'Create an account to build and manage a group.',
    AccountFeature.joinGroup =>
      'Create an account to join this group and participate.',
    AccountFeature.messages =>
      'Sign in to start conversations with people in Attendus.',
    AccountFeature.profile =>
      'Create an account to manage your profile, activity, tickets, and badges.',
    AccountFeature.attendeeProfiles =>
      'Sign in to view attendee profiles and connect with people.',
    AccountFeature.account =>
      'Sign in to access settings, subscriptions, and account tools.',
    AccountFeature.notifications =>
      'Sign in to receive and manage personalized notifications.',
    AccountFeature.registration || AccountFeature.tickets =>
      'Create an account to register, purchase tickets, and keep them available across devices.',
    AccountFeature.comments => 'Sign in to join the event conversation.',
    AccountFeature.favorites => 'Sign in to save events to your favorites.',
    AccountFeature.feedback => 'Sign in to submit and manage event feedback.',
    AccountFeature.accessRequest =>
      'Sign in to request access to this private event.',
    AccountFeature.analytics =>
      'Sign in to view attendance analytics and insights.',
  };
}
