// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get newMessage => 'New Message';

  @override
  String get newGroupMessage => 'New Group Message';

  @override
  String get yourGroups => 'Your Groups';

  @override
  String get info => 'Info';

  @override
  String get refresh => 'Refresh';

  @override
  String get noMembers => 'No members';

  @override
  String members(Object count) {
    return '$count members';
  }

  @override
  String get noUsersFound => 'No users found';

  @override
  String get noUsersAvailable => 'No users available';

  @override
  String get tryDifferentSearch => 'Try a different search term';

  @override
  String get noUsersToMessage => 'There are no other users to message';

  @override
  String get inviteFriends => 'Invite friends';

  @override
  String get discoverPeople => 'Discover people';

  @override
  String get aboutGroups => 'About groups';

  @override
  String get orgGroupExplainer => 'Selecting a group here will create a group conversation with all approved members of that organization.';

  @override
  String get viewProfile => 'View profile';

  @override
  String get message => 'Message';

  @override
  String get reportOrBlock => 'Report / Block';

  @override
  String get createWithSelected => 'Create group with selected users';

  @override
  String get createGroup => 'Create group';

  @override
  String get createFromOrg => 'Create group from selected organization';

  @override
  String get searchFailedToast => 'Search failed. Try again.';

  @override
  String get searchFailedMsg => 'Search failed. Please try again.';

  @override
  String get retry => 'Retry';

  @override
  String get messageType => 'Message type';

  @override
  String get searchUsers => 'Search users...';

  @override
  String get searchUsersHint => 'Type a name or @username';

  @override
  String get clearSearch => 'Clear search';

  @override
  String recentSearch(Object term) {
    return 'Recent search: $term';
  }

  @override
  String selectedUserChip(Object name) {
    return 'Selected: $name';
  }

  @override
  String get removeSelectedHint => 'Double tap to remove';

  @override
  String get a11yScaleFabTooltip => 'Toggle text scale for accessibility testing';

  @override
  String a11yScaleFabLabel(Object scale) {
    return 'Change text scale to $scale';
  }
}
