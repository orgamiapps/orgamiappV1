import 'dart:async';

import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/google_maps_bootstrap.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

bool isEventEligibleForGlobalMap(EventModel event, DateTime now) {
  final status = event.status.toLowerCase();
  final validStatus = status == 'scheduled' || status == 'active';
  final validCoordinates =
      event.latitude >= -90 &&
      event.latitude <= 90 &&
      event.longitude >= -180 &&
      event.longitude <= 180 &&
      !(event.latitude == 0 && event.longitude == 0);
  return validStatus &&
      !event.private &&
      event.locationType != 'online' &&
      validCoordinates &&
      now.isBefore(event.eventEndTime.add(const Duration(hours: 2)));
}

enum GlobalMapCameraMode { singleEvent, eventBounds, userLocation, world }

GlobalMapCameraMode selectGlobalMapCameraMode({
  required int eventCount,
  required bool hasBounds,
  required bool hasUserLocation,
}) {
  if (eventCount == 1) return GlobalMapCameraMode.singleEvent;
  if (eventCount > 1 && hasBounds) return GlobalMapCameraMode.eventBounds;
  if (hasUserLocation) return GlobalMapCameraMode.userLocation;
  return GlobalMapCameraMode.world;
}

class GlobalEventsMapScreen extends StatefulWidget {
  final Stream<List<EventModel>>? eventsForTesting;
  final bool requestUserLocation;
  final bool mapEnabled;

  const GlobalEventsMapScreen({
    super.key,
    this.eventsForTesting,
    this.requestUserLocation = true,
    this.mapEnabled = true,
  });

  @override
  State<GlobalEventsMapScreen> createState() => _GlobalEventsMapScreenState();
}

class _GlobalEventsMapScreenState extends State<GlobalEventsMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<EventModel> _allEvents = [];
  final Set<Marker> _markers = {};

  StreamSubscription<dynamic>? _subscription;
  GoogleMapController? _mapController;
  List<EventModel> _filteredEvents = const [];
  LatLng? _userLocation;
  LatLngBounds? _bounds;
  MapType _mapType = MapType.normal;
  bool _isLoading = true;
  bool _isSearching = false;
  String? _loadError;
  String? _locationNotice;
  int _snapshotGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
    if (widget.requestUserLocation) _loadUserLocation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToEvents() {
    _subscription?.cancel();
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final testEvents = widget.eventsForTesting;
    if (testEvents != null) {
      _subscription = testEvents.listen(
        _processEvents,
        onError: _handleEventsError,
      );
      return;
    }
    _subscription = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .where('private', isEqualTo: false)
        .snapshots()
        .listen(_processSnapshot, onError: _handleEventsError);
  }

  void _handleEventsError(Object error, StackTrace stackTrace) {
    Logger.error('Error loading map events', error, stackTrace);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadError =
          'Events could not be loaded. Check your connection and try again.';
    });
  }

  Future<void> _processSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final events = <EventModel>[];

    for (final doc in snapshot.docs) {
      try {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = data['id'] ?? doc.id;
        events.add(EventModel.fromJson(data));
      } catch (error) {
        Logger.warning('Skipping invalid map event ${doc.id}: $error');
      }
    }

    await _processEvents(events);
  }

  Future<void> _processEvents(List<EventModel> sourceEvents) async {
    final generation = ++_snapshotGeneration;
    final now = DateTime.now();
    final events = sourceEvents
        .where((event) => isEventEligibleForGlobalMap(event, now))
        .toList(growable: false);
    final markers = events.map(_markerFor).toSet();

    if (!mounted || generation != _snapshotGeneration) return;
    _allEvents
      ..clear()
      ..addAll(events);
    _markers
      ..clear()
      ..addAll(markers);
    _bounds = _calculateBounds(events);
    setState(() {
      _filteredEvents = List<EventModel>.from(events);
      _isLoading = false;
      _loadError = null;
    });
    if (mounted) _frameEvents();
  }

  Marker _markerFor(EventModel event) {
    return Marker(
      markerId: MarkerId(event.id),
      position: LatLng(event.latitude, event.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(_markerHue(event)),
      zIndexInt: event.isFeatured ? 1 : 0,
      infoWindow: InfoWindow(
        title: event.title,
        snippet: DateFormat('MMM d, y • h:mm a').format(event.selectedDateTime),
      ),
      onTap: () => _showEvent(event),
    );
  }

  double _markerHue(EventModel event) {
    if (event.isFeatured) return BitmapDescriptor.hueOrange;
    final category = event.categories.isEmpty
        ? ''
        : event.categories.first.toLowerCase();
    if (category.contains('music') || category.contains('concert')) {
      return BitmapDescriptor.hueViolet;
    }
    if (category.contains('sport') || category.contains('fitness')) {
      return BitmapDescriptor.hueGreen;
    }
    if (category.contains('business') || category.contains('networking')) {
      return BitmapDescriptor.hueBlue;
    }
    if (category.contains('food') || category.contains('dining')) {
      return BitmapDescriptor.hueRose;
    }
    if (category.contains('education') || category.contains('workshop')) {
      return BitmapDescriptor.hueYellow;
    }
    return BitmapDescriptor.hueRed;
  }

  LatLngBounds? _calculateBounds(List<EventModel> events) {
    if (events.length < 2) return null;
    var minLat = events.first.latitude;
    var maxLat = events.first.latitude;
    var minLng = events.first.longitude;
    var maxLng = events.first.longitude;
    for (final event in events.skip(1)) {
      minLat = event.latitude < minLat ? event.latitude : minLat;
      maxLat = event.latitude > maxLat ? event.latitude : maxLat;
      minLng = event.longitude < minLng ? event.longitude : minLng;
      maxLng = event.longitude > maxLng ? event.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _frameEvents() {
    final controller = _mapController;
    if (controller == null) return;
    final mode = selectGlobalMapCameraMode(
      eventCount: _allEvents.length,
      hasBounds: _bounds != null,
      hasUserLocation: _userLocation != null,
    );
    switch (mode) {
      case GlobalMapCameraMode.singleEvent:
        final event = _allEvents.first;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(event.latitude, event.longitude),
              zoom: 14,
            ),
          ),
        );
        break;
      case GlobalMapCameraMode.eventBounds:
        controller.animateCamera(CameraUpdate.newLatLngBounds(_bounds!, 80));
        break;
      case GlobalMapCameraMode.userLocation:
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _userLocation!, zoom: 10),
          ),
        );
        break;
      case GlobalMapCameraMode.world:
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            const CameraPosition(target: LatLng(20, 0), zoom: 2),
          ),
        );
        break;
    }
  }

  Future<void> _loadUserLocation({bool moveCamera = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() {
            _locationNotice =
                'Location services are off, so the map is showing a world view.';
          });
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationNotice =
                'Location permission was not granted, so the map is showing a world view.';
          });
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _locationNotice = null;
      });
      if (moveCamera || _allEvents.isEmpty) _frameEvents();
    } catch (error) {
      Logger.warning('Could not get map location: $error');
      if (mounted) {
        setState(() {
          _locationNotice =
              'Your location could not be loaded. The map is showing a world view.';
        });
        if (moveCamera) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get your location')),
          );
        }
      }
    }
  }

  void _filterEvents(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _isSearching = query.isNotEmpty;
      _filteredEvents = query.isEmpty
          ? List<EventModel>.from(_allEvents)
          : _allEvents.where((event) {
              return event.title.toLowerCase().contains(query) ||
                  event.location.toLowerCase().contains(query) ||
                  (event.locationName?.toLowerCase().contains(query) ??
                      false) ||
                  event.categories.any(
                    (category) => category.toLowerCase().contains(query),
                  );
            }).toList();
    });
  }

  void _selectSearchResult(EventModel event) {
    _searchFocus();
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(event.latitude, event.longitude),
          zoom: 15,
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _showEvent(event);
    });
  }

  void _searchFocus() {
    FocusScope.of(context).unfocus();
    setState(() => _isSearching = false);
  }

  Future<void> _showEvent(EventModel event) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: event.imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                event.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _detailRow(
                Icons.calendar_today_outlined,
                DateFormat(
                  'EEEE, MMMM d, y • h:mm a',
                ).format(event.selectedDateTime),
              ),
              const SizedBox(height: 8),
              _detailRow(
                Icons.location_on_outlined,
                event.locationName?.isNotEmpty == true
                    ? '${event.locationName}\n${event.location}'
                    : event.location,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    RouterClass.nextScreenNormal(
                      context,
                      SingleEventScreen(eventModel: event),
                    );
                  },
                  child: const Text('View event details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }

  void _openCreateEvent() {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest =
        GuestModeService().isGuestMode || user == null || user.isAnonymous;
    if (isGuest) {
      _showGuestCreateDialog();
      return;
    }
    RouterClass.nextScreenNormal(context, const PremiumEventCreationWrapper());
  }

  void _showGuestCreateDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account required'),
        content: Text(
          GuestModeService().getFeatureRestrictionMessage(
            GuestFeature.createEvent,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              RouterClass.nextScreenNormal(
                context,
                const CreateAccountScreen(),
              );
            },
            child: const Text('Create account'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapConfigurationError = GoogleMapsBootstrap.errorMessage;
    return Scaffold(
      body: Stack(
        children: [
          if (widget.mapEnabled && GoogleMapsBootstrap.isAvailable)
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                _frameEvents();
              },
              initialCameraPosition: const CameraPosition(
                target: LatLng(20, 0),
                zoom: 2,
              ),
              markers: _markers,
              mapType: _mapType,
              myLocationEnabled: _userLocation != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
            )
          else
            Container(color: const Color(0xFFE8EDF3)),
          _topSearch(),
          if (mapConfigurationError != null)
            _mapConfigurationErrorCard(mapConfigurationError),
          if (_isLoading)
            const Positioned(
              top: 116,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_isLoading && _loadError != null) _errorCard(),
          if (mapConfigurationError == null &&
              !_isLoading &&
              _loadError == null &&
              _allEvents.isEmpty)
            _emptyCard(),
          if (mapConfigurationError == null) _mapControls(),
          if (!_isLoading && _allEvents.isNotEmpty) _eventCount(),
        ],
      ),
    );
  }

  Widget _mapConfigurationErrorCard(String message) {
    return Positioned(
      top: 116,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 40),
              const SizedBox(height: 10),
              const Text(
                'Map unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topSearch() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Material(
                elevation: 5,
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterEvents,
                  decoration: InputDecoration(
                    hintText: 'Search events on the map',
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filterEvents('');
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_isSearching)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: _filteredEvents.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('No matching events on the map'),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _filteredEvents.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final event = _filteredEvents[index];
                            return ListTile(
                              leading: const Icon(Icons.event_outlined),
                              title: Text(event.title),
                              subtitle: Text(
                                event.locationName ?? event.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectSearchResult(event),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapControls() {
    return Positioned(
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 96,
      child: Column(
        children: [
          FloatingActionButton.small(
            heroTag: 'map_type',
            backgroundColor: Colors.white,
            onPressed: () {
              setState(() {
                _mapType = _mapType == MapType.normal
                    ? MapType.satellite
                    : MapType.normal;
              });
            },
            child: const Icon(Icons.layers_outlined, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'fit_events',
            backgroundColor: Colors.white,
            onPressed: _frameEvents,
            child: const Icon(Icons.fit_screen, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'my_location',
            backgroundColor: Colors.white,
            onPressed: () => _loadUserLocation(moveCamera: true),
            child: const Icon(Icons.my_location, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      child: Card(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 40),
              const SizedBox(height: 10),
              Text(
                'No events with map locations yet',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Be the first to add an in-person event with a precise location.',
                textAlign: TextAlign.center,
              ),
              if (_locationNotice != null) ...[
                const SizedBox(height: 8),
                Text(
                  _locationNotice!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _openCreateEvent,
                icon: const Icon(Icons.add),
                label: const Text('Create event'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(_loadError!)),
              TextButton(
                onPressed: _subscribeToEvents,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventCount() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 18,
      child: Center(
        child: Chip(
          avatar: const Icon(Icons.event, size: 18),
          label: Text(
            '${_allEvents.length} ${_allEvents.length == 1 ? 'event' : 'events'} on map',
          ),
        ),
      ),
    );
  }
}
