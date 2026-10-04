import 'package:attendus/Services/firebase_initializer.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:flutter/material.dart';

class SharedCommunityScreen extends StatefulWidget {
  const SharedCommunityScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<SharedCommunityScreen> createState() => _SharedCommunityScreenState();
}

class _SharedCommunityScreenState extends State<SharedCommunityScreen> {
  late final Future<void> _initialization = _initialize();

  Future<void> _initialize() async {
    await FirebaseInitializer.initializeOnce();
    await GuestModeService().initialize();
    await GuestModeService().ensureGuestSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Could not open this community.')),
          );
        }
        return GroupProfileScreenV2(organizationId: widget.organizationId);
      },
    );
  }
}
