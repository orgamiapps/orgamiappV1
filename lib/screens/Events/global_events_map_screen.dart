import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:intl/intl.dart';

/// Global Events Map Screen - Shows all public events worldwide on an Apple Maps-style interface
class GlobalEventsMapScreen extends StatefulWidget {
  const GlobalEventsMapScreen({super.key});

  @override
  State<GlobalEventsMapScreen> createState() => _GlobalEventsMapScreenState();
}

class _GlobalEventsMapScreenState extends State<GlobalEventsMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final List<EventModel> _allEvents = [];
  final List<EventModel> _filteredEvents = [];
  bool _isLoading = true;
  bool _showSearchResults = false;
  final TextEditingController _searchController = TextEditingController();
  MapType _currentMapType = MapType.normal;
  String? _selectedEventId;

  // Default location (San Francisco)
  static const LatLng _defaultLocation = LatLng(37.7749, -122.4194);

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Load all public events from Firestore
  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where('status', isEqualTo: 'active')
          .get();

      _allEvents.clear();
      _markers.clear();

      for (var doc in snapshot.docs) {
        try {
          final event = EventModel.fromJson(doc);
          _allEvents.add(event);
          _addMarkerForEvent(event);
        } catch (e) {
          debugPrint('Error parsing event ${doc.id}: $e');
        }
      }

      // Sort events by date
      _allEvents.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading events: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Add a marker for an event on the map
  void _addMarkerForEvent(EventModel event) {
    final marker = Marker(
      markerId: MarkerId(event.id),
      position: LatLng(event.latitude, event.longitude),
      icon: _getMarkerIcon(event),
      infoWindow: InfoWindow(
        title: event.title,
        snippet: DateFormat('MMM d, y • h:mm a').format(event.selectedDateTime),
        onTap: () => _openEventDetails(event),
      ),
      onTap: () {
        setState(() => _selectedEventId = event.id);
        _showEventBottomSheet(event);
      },
    );

    _markers.add(marker);
  }

  /// Get marker icon based on event type
  BitmapDescriptor _getMarkerIcon(EventModel event) {
    // For now, use default markers with different colors
    // In production, you could create custom marker icons
    if (event.isFeatured) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (event.categories.isNotEmpty) {
      // Color code by category
      switch (event.categories.first.toLowerCase()) {
        case 'music':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
        case 'sports':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        case 'business':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
        case 'food':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
        case 'education':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
        default:
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      }
    }
    return BitmapDescriptor.defaultMarker;
  }

  /// Open event details screen
  void _openEventDetails(EventModel event) {
    RouterClass.nextScreenNormal(
      context,
      SingleEventScreen(
        eventId: event.id,
        model: event,
      ),
    );
  }

  /// Show event details in a bottom sheet
  void _showEventBottomSheet(EventModel event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Event image
            if (event.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  event.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image_not_supported, size: 50),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Date and time
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM d, y • h:mm a').format(event.selectedDateTime),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Location
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.locationName ?? event.location,
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Categories
                  if (event.categories.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: event.categories.take(3).map((category) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  // View Details button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _openEventDetails(event);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'View Event Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle search text changes
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _filteredEvents.clear();
      });
      return;
    }

    setState(() {
      _showSearchResults = true;
      _filteredEvents.clear();
      _filteredEvents.addAll(
        _allEvents.where((event) {
          return event.title.toLowerCase().contains(query) ||
              event.location.toLowerCase().contains(query) ||
              (event.locationName?.toLowerCase().contains(query) ?? false) ||
              event.categories.any((cat) => cat.toLowerCase().contains(query)) ||
              event.description.toLowerCase().contains(query);
        }),
      );
    });
  }

  /// Zoom to a specific event on the map
  void _zoomToEvent(EventModel event) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(event.latitude, event.longitude),
          zoom: 15,
        ),
      ),
    );
    setState(() {
      _selectedEventId = event.id;
      _showSearchResults = false;
      _searchController.clear();
    });
    _showEventBottomSheet(event);
  }

  /// Toggle map type
  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal 
          ? MapType.satellite 
          : MapType.normal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultLocation,
              zoom: 3,
            ),
            markers: _markers,
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              // If we have events, fit bounds to show all markers
              if (_markers.isNotEmpty) {
                _fitMarkersBounds();
              }
            },
          ),

          // Search bar overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search bar with back button
                  Row(
                    children: [
                      // Back button
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.arrow_back, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Search input
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search events...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _showSearchResults = false);
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Search results dropdown
                  if (_showSearchResults && _filteredEvents.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _filteredEvents.length,
                        itemBuilder: (context, index) {
                          final event = _filteredEvents[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.event,
                                color: Theme.of(context).primaryColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              event.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${event.locationName ?? event.location} • ${DateFormat('MMM d').format(event.selectedDateTime)}',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _zoomToEvent(event),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Map controls (bottom right)
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                // Map type toggle
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _toggleMapType,
                      child: Icon(
                        _currentMapType == MapType.normal
                            ? Icons.layers
                            : Icons.map,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // My location button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _fitMarkersBounds,
                      child: const Icon(Icons.my_location, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Events counter (bottom center)
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${_allEvents.length} events worldwide',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fit map camera to show all markers
  void _fitMarkersBounds() {
    if (_markers.isEmpty || _mapController == null) return;

    // Calculate bounds
    double minLat = 90;
    double maxLat = -90;
    double minLng = 180;
    double maxLng = -180;

    for (var marker in _markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    // Add padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }
}
