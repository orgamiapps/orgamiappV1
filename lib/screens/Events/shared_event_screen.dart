import 'dart:async';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/firebase_initializer.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum SharedEventLoadState { loading, event, restricted, notFound, error }

class SharedEventScreen extends StatefulWidget {
  final String eventId;

  const SharedEventScreen({super.key, required this.eventId});

  @override
  State<SharedEventScreen> createState() => _SharedEventScreenState();
}

class _SharedEventScreenState extends State<SharedEventScreen> {
  SharedEventLoadState _state = SharedEventLoadState.loading;
  EventModel? _event;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _requestSubscription;
  String? _requestStatus;
  bool _submittingRequest = false;
  bool _approvalReloadScheduled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _state = SharedEventLoadState.loading);
    }
    try {
      await FirebaseInitializer.initializeOnce();
      await GuestModeService().initialize();
      await GuestModeService().ensureGuestSession();
      final snapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(widget.eventId)
          .get();
      if (!mounted) return;
      if (!snapshot.exists || snapshot.data() == null) {
        setState(() => _state = SharedEventLoadState.notFound);
        return;
      }
      final event = EventModel.fromJson({
        ...snapshot.data()!,
        'id': snapshot.id,
      });
      setState(() {
        _event = event;
        _state = SharedEventLoadState.event;
      });
    } on FirebaseException catch (error) {
      Logger.warning('Shared event ${widget.eventId} failed to load: $error');
      if (!mounted) return;
      if (error.code == 'permission-denied') {
        setState(() => _state = SharedEventLoadState.restricted);
        _watchAccessRequest();
      } else {
        setState(() => _state = SharedEventLoadState.error);
      }
    } catch (error) {
      Logger.warning('Shared event ${widget.eventId} failed to load: $error');
      if (mounted) setState(() => _state = SharedEventLoadState.error);
    }
  }

  void _watchAccessRequest() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    _requestSubscription?.cancel();
    _requestSubscription = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(widget.eventId)
        .collection('AccessRequests')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final status = snapshot.data()?['status']?.toString();
            setState(() => _requestStatus = status);
            if (status == 'approved' && !_approvalReloadScheduled) {
              _approvalReloadScheduled = true;
              Future<void>.delayed(const Duration(milliseconds: 350), _load);
            }
          },
          onError: (Object error) {
            Logger.warning('Unable to watch event access request: $error');
          },
        );
  }

  Future<void> _requestAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || AccountAccessService.isGuest) {
      await showAccountRequiredSheet(
        context: context,
        feature: AccountFeature.accessRequest,
        sharedEventId: widget.eventId,
      );
      return;
    }
    setState(() => _submittingRequest = true);
    try {
      await FirebaseFirestoreHelper().requestEventAccess(
        eventId: widget.eventId,
      );
      if (mounted) setState(() => _requestStatus = 'pending');
      _watchAccessRequest();
    } catch (error) {
      Logger.warning('Unable to request access to ${widget.eventId}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the access request.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == SharedEventLoadState.event && _event != null) {
      return SingleEventScreen(eventModel: _event!);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Shared event')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildState(),
          ),
        ),
      ),
    );
  }

  Widget _buildState() {
    switch (_state) {
      case SharedEventLoadState.loading:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening event…'),
          ],
        );
      case SharedEventLoadState.restricted:
        final pending = _requestStatus == 'pending';
        final declined = _requestStatus == 'declined';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            Text(
              'This event requires access',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              pending
                  ? 'Your request is waiting for the organizer.'
                  : declined
                  ? 'Your previous request was not approved.'
                  : 'Sign in and request access from the organizer to view this private event.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: pending || _submittingRequest ? null : _requestAccess,
              icon: _submittingRequest
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_outlined),
              label: Text(pending ? 'Request pending' : 'Request access'),
            ),
          ],
        );
      case SharedEventLoadState.notFound:
        return _message(
          Icons.event_busy_outlined,
          'Event unavailable',
          'This event may have been removed or the link may be incorrect.',
        );
      case SharedEventLoadState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _message(
              Icons.cloud_off_outlined,
              'Could not open event',
              'Check your connection and try again.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        );
      case SharedEventLoadState.event:
        return const SizedBox.shrink();
    }
  }

  Widget _message(IconData icon, String title, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
