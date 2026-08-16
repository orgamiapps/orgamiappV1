import 'package:attendus/screens/Groups/shared_community_screen.dart'
    deferred as shared_community;
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';

class DeferredSharedCommunityScreen extends StatelessWidget {
  const DeferredSharedCommunityScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    return DeferredScreenLoader(
      loadLibrary: shared_community.loadLibrary,
      recoveryKey: 'shared-community',
      loadingLabel: 'Opening community',
      builder: () => shared_community.SharedCommunityScreen(
        organizationId: organizationId,
      ),
    );
  }
}
