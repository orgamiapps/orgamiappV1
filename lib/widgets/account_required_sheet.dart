import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Services/product_funnel_service.dart';

enum _AccountChoice { createAccount, logIn }

final _activeAccountSheets = <NavigatorState>{};

Future<void> showGuestAuthSheet({required BuildContext context}) =>
    _showAccountSheet(context: context, fromHeader: true);

Future<void> showAccountRequiredSheet({
  required BuildContext context,
  required AccountFeature feature,
  String? sharedEventId,
  String? sharedCommunityId,
  String? eventAction,
  String? saveEventId,
}) => _showAccountSheet(
  context: context,
  feature: feature,
  sharedEventId: sharedEventId,
  sharedCommunityId: sharedCommunityId,
  eventAction: eventAction,
  saveEventId: saveEventId,
);

Future<void> _showAccountSheet({
  required BuildContext context,
  AccountFeature feature = AccountFeature.account,
  bool fromHeader = false,
  String? sharedEventId,
  String? sharedCommunityId,
  String? eventAction,
  String? saveEventId,
}) async {
  final navigator = Navigator.of(context);
  if (!_activeAccountSheets.add(navigator)) return;
  try {
    if (!fromHeader) {
      ProductFunnelService().record(
        'guest_locked_feature_prompt',
        dimensions: {'feature': feature.name},
      );
    }
    var choiceSubmitted = false;
    void choose(_AccountChoice? choice) {
      if (choiceSubmitted) return;
      choiceSubmitted = true;
      navigator.pop(choice);
    }

    final choice = await showAttendUsBottomSheet<_AccountChoice>(
      context: context,
      title: fromHeader
          ? 'Join the Attendus community'
          : AccountAccessService.title(feature),
      subtitle: fromHeader
          ? 'Create an account or log in to save events, join groups, and connect with others.'
          : AccountAccessService.message(feature),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttendUsButton.primary(
            label: 'Create account',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: () => choose(_AccountChoice.createAccount),
          ),
          const SizedBox(height: 10),
          AttendUsButton.secondary(
            label: 'Log in',
            icon: Icons.login,
            onPressed: () => choose(_AccountChoice.logIn),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => choose(null),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    ProductFunnelService().record(
      'guest_auth_started',
      dimensions: {
        'entryPoint': fromHeader ? 'header' : 'locked_feature',
        'feature': feature.name,
        'authChoice': choice == _AccountChoice.createAccount
            ? 'create_account'
            : 'sign_in',
      },
    );
    if (fromHeader) {
      await PendingAuthIntentService.rememberHome();
    } else if (sharedCommunityId != null) {
      await PendingAuthIntentService.rememberCommunity(
        sharedCommunityId,
        feature: feature,
      );
    } else if (saveEventId != null) {
      await PendingAuthIntentService.rememberSaveEvent(saveEventId);
    } else if (sharedEventId != null) {
      await PendingAuthIntentService.rememberSharedEvent(
        sharedEventId,
        action: eventAction,
      );
    } else {
      await PendingAuthIntentService.rememberFeature(feature);
    }
    if (!context.mounted) return;
    RouterClass.nextScreenNormal(
      context,
      choice == _AccountChoice.createAccount
          ? const CreateAccountScreen()
          : const LoginScreen(),
    );
  } finally {
    _activeAccountSheets.remove(navigator);
  }
}

class AccountRequiredGate extends StatefulWidget {
  final AccountFeature feature;
  final Widget child;

  const AccountRequiredGate({
    super.key,
    required this.feature,
    required this.child,
  });

  @override
  State<AccountRequiredGate> createState() => _AccountRequiredGateState();
}

class _AccountRequiredGateState extends State<AccountRequiredGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!AccountAccessService.isGuest || !mounted) return;
      await showAccountRequiredSheet(context: context, feature: widget.feature);
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => AccountAccessService.isGuest
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : widget.child;
}
