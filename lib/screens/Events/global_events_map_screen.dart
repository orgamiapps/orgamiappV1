import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
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
  
  @override
  void initState() {
    super.initState();
    _loadEvents();
  }
  
  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }
  
  // Load all public, active events from Firestore
  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where('status', isEqualTo: 'active')
          .get();
      
      Logger.log('Loaded ${snapshot.docs.length} events from Firestore');
      
      _allEvents.clear();
      _markers.clear();
      
      for (final doc in snapshot.docs) {
        try {
          final event = EventModel.fromJson(doc);
          _allEvents.add(event);
          _markers.add(_createMarker(event));
        } catch (e) {
          Logger.error('Error parsing event ${doc.id}: $e');
        }
      }
      
      // Calculate bounds for all markers
      if (_allEvents.isNotEmpty) {
        _calculateBounds();
      }
      
      setState(() {
        _filteredEvents = List.from(_allEvents);
        _isLoading = false;
      });
      
      // Auto-fit map to show all markers after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_bounds != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(_bounds!, 50),
          );
        }
      });
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
      minLat = minLat == null ? event.latitude : (event.latitude < minLat ? event.latitude : minLat);
      maxLat = maxLat == null ? event.latitude : (event.latitude > maxLat ? event.latitude : maxLat);
      minLng = minLng == null ? event.longitude : (event.longitude < minLng ? event.longitude : minLng);
      maxLng = maxLng == null ? event.longitude : (event.longitude > maxLng ? event.longitude : maxLng);
    }
    
    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      _bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
    }
  }
  
  // Create a marker for an event with category-based color
  Marker _createMarker(EventModel event) {
    return Marker(
      markerId: MarkerId(event.id),
      position: LatLng(event.latitude, event.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerColor(event)),
      infoWindow: InfoWindow(
        title: event.title,
        snippet: DateFormat('MMM d, y • h:mm a').format(event.selectedDateTime),
      ),
      onTap: () => _showEventBottomSheet(event),
    );
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
      } else if (category.contains('business') || category.contains('networking')) {
        return BitmapDescriptor.hueBlue;
      } else if (category.contains('food') || category.contains('dining')) {
        return BitmapDescriptor.hueRose;
      } else if (category.contains('education') || category.contains('workshop')) {
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
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Event date/time
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMMM d, y • h:mm a').format(event.selectedDateTime),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
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
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
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
            event.categories.any((cat) => cat.toLowerCase().contains(lowerQuery)) ||
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
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_bounds!, 50),
      );
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
              content: Text('Location permission permanently denied. Please enable in settings.'),
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
            },
            initialCameraPosition: CameraPosition(
              target: _allEvents.isNotEmpty
                  ? LatLng(_allEvents.first.latitude, _allEvents.first.longitude)
                  : const LatLng(37.7749, -122.4194), // San Francisco default
              zoom: 12,
            ),
            markers: _markers,
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          
          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
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
                              contentPadding: EdgeInsets.symmetric(horizontal: 8),
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
                        separatorBuilder: (context, index) => const Divider(height: 1),
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              DateFormat('MMM d, y').format(event.selectedDateTime),
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
            top: MediaQuery.of(context).padding.top + 100,
            child: Column(
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
                  child: const Icon(
                    Icons.fit_screen,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                
                // My location button
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  backgroundColor: Colors.white,
                  onPressed: _goToMyLocation,
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          
          // Event counter badge (bottom center)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      '${_allEvents.length} events worldwide',
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
