import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/logger.dart';

class GlobalEventsMapScreen extends StatefulWidget {
  const GlobalEventsMapScreen({super.key});

  @override
  State<GlobalEventsMapScreen> createState() => _GlobalEventsMapScreenState();
}

class _GlobalEventsMapScreenState extends State<GlobalEventsMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  MapType _currentMapType = MapType.normal;

  // Map boundaries for fitting all markers
  LatLngBounds? _bounds;

  // User's current location
  LatLng? _userLocation;
  bool _hasMovedToUserLocation = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _getUserLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Get user's current location
  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Logger.warning('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Logger.warning('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Logger.warning('Location permission permanently denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      Logger.success(
        'Got user location: ${position.latitude}, ${position.longitude}',
      );

      // Move camera to user location once map is ready
      _moveToUserLocation();
    } catch (e) {
      Logger.error('Error getting user location: $e');
    }
  }

  // Move camera to user's location with appropriate zoom
  void _moveToUserLocation() {
    if (_mapController != null &&
        _userLocation != null &&
        !_hasMovedToUserLocation) {
      _hasMovedToUserLocation = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userLocation!,
            zoom: 12.0, // Good balance - shows neighborhood area
          ),
        ),
      );
      Logger.info('Moved map to user location with zoom 12.0');
    }
  }

  // Load all public, active events from Firestore
  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      // Get current time for filtering
      final now = DateTime.now();

      // Query for public events (removed status filter to get more events)
      final snapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .get();

      Logger.info(
        'Loaded ${snapshot.docs.length} public events from Firestore',
      );

      _allEvents.clear();
      _markers.clear();

      int validLocationCount = 0;
      int filteredOutCount = 0;
      int geocodedCount = 0;

      for (final doc in snapshot.docs) {
        try {
          final event = EventModel.fromJson(doc);

          Logger.info(
            'Processing event: ${event.title}, Status: ${event.status}, Lat: ${event.latitude}, Lng: ${event.longitude}, Location: ${event.location}',
          );

          // Calculate event end time (selectedDateTime + eventDuration hours)
          final eventEndTime = event.selectedDateTime.add(
            Duration(hours: event.eventDuration),
          );

          // Add 2 hours buffer after event ends
          final cutoffTime = eventEndTime.add(const Duration(hours: 2));

          // Check if event should be shown:
          // Show if event hasn't ended + 2 hours yet
          final shouldShowEvent = now.isBefore(cutoffTime);

          if (!shouldShowEvent) {
            filteredOutCount++;
            Logger.info(
              'Event ${event.title} filtered out - ended more than 2 hours ago',
            );
            continue;
          }

          // Try to get valid coordinates
          double lat = event.latitude;
          double lng = event.longitude;

          // If no valid coordinates, try to geocode the location
          if (lat == 0.0 && lng == 0.0 && event.location.isNotEmpty) {
            try {
              Logger.info('Attempting to geocode location: ${event.location}');
              List<Location> locations = await locationFromAddress(
                event.location,
              );
              if (locations.isNotEmpty) {
                lat = locations.first.latitude;
                lng = locations.first.longitude;
                geocodedCount++;
                Logger.success(
                  'Geocoded ${event.title}: ${event.location} -> $lat, $lng',
                );
              }
            } catch (e) {
              Logger.warning(
                'Could not geocode location for ${event.title}: ${event.location} - $e',
              );
            }
          }

          // Now check if we have valid coordinates
          if (lat != 0.0 && lng != 0.0) {
            // Update event coordinates if they were geocoded
            if (event.latitude == 0.0 && event.longitude == 0.0) {
              event.latitude = lat;
              event.longitude = lng;
            }

            _allEvents.add(event);
            final marker = await _createMarker(event);
            _markers.add(marker);
            validLocationCount++;
            Logger.info(
              '✓ Added marker for event: ${event.title} at $lat, $lng',
            );
          } else {
            Logger.warning(
              'Event ${event.title} has no valid coordinates and could not be geocoded',
            );
          }
        } catch (e) {
          Logger.error('Error processing event ${doc.id}: $e');
        }
      }

      Logger.info(
        '📍 Map Summary: $validLocationCount markers created from ${snapshot.docs.length} events ($geocodedCount geocoded, $filteredOutCount time-filtered)',
      );

      // Calculate bounds for all markers
      if (_allEvents.isNotEmpty) {
        _calculateBounds();
      }

      setState(() {
        _filteredEvents = List.from(_allEvents);
        _isLoading = false;
      });

      // Only auto-fit to markers if we haven't centered on user location
      // This prevents the map from jumping away from user's location
      if (_markers.isNotEmpty && _userLocation == null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (_bounds != null && _mapController != null && mounted) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(_bounds!, 100),
            );
            Logger.info('Auto-fitted map to show all markers');
          }
        });
      }
    } catch (e) {
      Logger.error('Error loading events: $e');
      setState(() => _isLoading = false);
    }
  }

  // Calculate bounds to fit all markers
  void _calculateBounds() {
    if (_allEvents.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;

    for (final event in _allEvents) {
      minLat = minLat == null
          ? event.latitude
          : (event.latitude < minLat ? event.latitude : minLat);
      maxLat = maxLat == null
          ? event.latitude
          : (event.latitude > maxLat ? event.latitude : maxLat);
      minLng = minLng == null
          ? event.longitude
          : (event.longitude < minLng ? event.longitude : minLng);
      maxLng = maxLng == null
          ? event.longitude
          : (event.longitude > maxLng ? event.longitude : maxLng);
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      _bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
    }
  }

  // Create a marker for an event with category-based color
  Future<Marker> _createMarker(EventModel event) async {
    // Create custom marker with enhanced visibility
    final BitmapDescriptor markerIcon = await _getCustomMarkerIcon(event);

    return Marker(
      markerId: MarkerId(event.id),
      position: LatLng(event.latitude, event.longitude),
      icon: markerIcon,
      infoWindow: InfoWindow(
        title: event.title,
        snippet: DateFormat('MMM d, y • h:mm a').format(event.selectedDateTime),
      ),
      onTap: () => _showEventBottomSheet(event),
      visible: true,
      alpha: 1.0,
      zIndexInt: event.isFeatured ? 1 : 0,
    );
  }

  // Get custom marker icon with proper color
  Future<BitmapDescriptor> _getCustomMarkerIcon(EventModel event) async {
    final double hue = _getMarkerColor(event);

    // Use larger marker for featured events
    if (event.isFeatured) {
      return BitmapDescriptor.defaultMarkerWithHue(hue);
    }

    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }

  // Get marker color based on event properties
  double _getMarkerColor(EventModel event) {
    // Featured events are orange
    if (event.isFeatured) {
      return BitmapDescriptor.hueOrange;
    }

    // Color-code by first category
    if (event.categories.isNotEmpty) {
      final category = event.categories.first.toLowerCase();

      if (category.contains('music') || category.contains('concert')) {
        return BitmapDescriptor.hueViolet;
      } else if (category.contains('sport') || category.contains('fitness')) {
        return BitmapDescriptor.hueGreen;
      } else if (category.contains('business') ||
          category.contains('networking')) {
        return BitmapDescriptor.hueBlue;
      } else if (category.contains('food') || category.contains('dining')) {
        return BitmapDescriptor.hueRose;
      } else if (category.contains('education') ||
          category.contains('workshop')) {
        return BitmapDescriptor.hueYellow;
      } else if (category.contains('art') || category.contains('culture')) {
        return BitmapDescriptor.hueCyan;
      }
    }

    // Default color
    return BitmapDescriptor.hueRed;
  }

  // Show event details in bottom sheet
  void _showEventBottomSheet(EventModel event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Event image
            if (event.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: event.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(Icons.event, size: 50),
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Event title
            Text(
              event.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Event date/time with duration
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat(
                          'EEEE, MMMM d, y',
                        ).format(event.selectedDateTime),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateFormat('h:mm a').format(event.selectedDateTime)} - ${DateFormat('h:mm a').format(event.selectedDateTime.add(Duration(hours: event.eventDuration)))}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Event location
            Row(
              children: [
                const Icon(Icons.location_on, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.locationName ?? event.location,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              ],
            ),

            // Categories
            if (event.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: event.categories.take(3).map((category) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 20),

            // View details button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close bottom sheet
                  RouterClass.nextScreenNormal(
                    context,
                    SingleEventScreen(eventModel: event),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View Event Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            // Bottom padding for safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // Filter events based on search query
  void _filterEvents(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredEvents = List.from(_allEvents);
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredEvents = _allEvents.where((event) {
        return event.title.toLowerCase().contains(lowerQuery) ||
            event.location.toLowerCase().contains(lowerQuery) ||
            (event.locationName?.toLowerCase().contains(lowerQuery) ?? false) ||
            event.categories.any(
              (cat) => cat.toLowerCase().contains(lowerQuery),
            ) ||
            event.description.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  // Zoom to selected event
  void _zoomToEvent(EventModel event) {
    setState(() => _isSearching = false);
    _searchController.clear();
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(event.latitude, event.longitude),
          zoom: 15,
        ),
      ),
    );
    // Show bottom sheet after animation
    Future.delayed(const Duration(milliseconds: 500), () {
      _showEventBottomSheet(event);
    });
  }

  // Fit all markers in view
  void _fitAllMarkers() {
    if (_bounds != null && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(_bounds!, 50));
    }
  }

  // Go to user's location
  Future<void> _goToMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission permanently denied. Please enable in settings.',
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 14,
          ),
        ),
      );
    } catch (e) {
      Logger.error('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              Logger.info('Map created with ${_markers.length} markers');

              // Move to user location if available
              _moveToUserLocation();
            },
            initialCameraPosition: CameraPosition(
              target: _userLocation ?? const LatLng(37.7749, -122.4194),
              zoom: _userLocation != null ? 12.0 : 10.0,
            ),
            markers: _markers,
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: true,
            buildingsEnabled: true,
            indoorViewEnabled: false,
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(child: CircularProgressIndicator()),
            ),

          // Top search bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Column(
                children: [
                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),

                        // Search field
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search events...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onChanged: (value) {
                              _filterEvents(value);
                              setState(() {
                                _isSearching = value.isNotEmpty;
                              });
                            },
                          ),
                        ),

                        // Clear button
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filterEvents('');
                              setState(() => _isSearching = false);
                            },
                          ),
                      ],
                    ),
                  ),

                  // Search results dropdown
                  if (_isSearching && _filteredEvents.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _filteredEvents.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final event = _filteredEvents[index];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: event.imageUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey[200],
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.event, size: 25),
                                ),
                              ),
                            ),
                            title: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              DateFormat(
                                'MMM d, y',
                              ).format(event.selectedDateTime),
                              style: const TextStyle(fontSize: 12),
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

          // Map controls (right side)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Map type toggle
                FloatingActionButton.small(
                  heroTag: 'map_type',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      _currentMapType = _currentMapType == MapType.normal
                          ? MapType.satellite
                          : MapType.normal;
                    });
                  },
                  child: Icon(
                    _currentMapType == MapType.normal
                        ? Icons.layers
                        : Icons.map,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),

                // Fit all markers button
                FloatingActionButton.small(
                  heroTag: 'fit_all',
                  backgroundColor: Colors.white,
                  onPressed: _fitAllMarkers,
                  child: const Icon(Icons.fit_screen, color: Colors.black87),
                ),
                const SizedBox(height: 12),

                // My location button
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  backgroundColor: Colors.white,
                  onPressed: _goToMyLocation,
                  child: const Icon(Icons.my_location, color: Colors.black87),
                ),
              ],
            ),
          ),

          // Event counter badge (bottom center)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      _markers.isEmpty
                          ? 'No events with locations'
                          : '${_markers.length} events on map',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
