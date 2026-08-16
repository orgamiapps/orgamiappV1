import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Services/product_funnel_service.dart';

Future<void> showAccountRequiredSheet({
  required BuildContext context,
  required AccountFeature feature,
  String? sharedEventId,
  String? saveEventId,
}) async {
  ProductFunnelService().record(
    'guest_locked_feature_prompt',
    dimensions: {'feature': feature.name},
  );
  await showAttendUsBottomSheet<void>(
    context: context,
    title: AccountAccessService.title(feature),
    subtitle: AccountAccessService.message(feature),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendUsButton.primary(
          label: 'Create account',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: () async {
            ProductFunnelService().record(
              'guest_auth_started',
              dimensions: {
                'entryPoint': 'locked_feature',
                'feature': feature.name,
                'authChoice': 'create_account',
              },
            );
            if (saveEventId != null) {
              await PendingAuthIntentService.rememberSaveEvent(saveEventId);
            } else if (sharedEventId != null) {
              await PendingAuthIntentService.rememberSharedEvent(sharedEventId);
            } else {
              await PendingAuthIntentService.rememberFeature(feature);
            }
            if (!context.mounted) return;
            Navigator.pop(context);
            RouterClass.nextScreenNormal(context, const CreateAccountScreen());
          },
        ),
        const SizedBox(height: 10),
        AttendUsButton.secondary(
          label: 'Sign in',
          icon: Icons.login,
          onPressed: () async {
            ProductFunnelService().record(
              'guest_auth_started',
              dimensions: {
                'entryPoint': 'locked_feature',
                'feature': feature.name,
                'authChoice': 'sign_in',
              },
            );
            if (saveEventId != null) {
              await PendingAuthIntentService.rememberSaveEvent(saveEventId);
            } else if (sharedEventId != null) {
              await PendingAuthIntentService.rememberSharedEvent(sharedEventId);
            } else {
              await PendingAuthIntentService.rememberFeature(feature);
            }
            if (!context.mounted) return;
            Navigator.pop(context);
            RouterClass.nextScreenNormal(context, const LoginScreen());
          },
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
      ],
    ),
  );
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
