import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';

class GeofenceSetupScreen extends StatefulWidget {
  final EventModel eventModel;

  const GeofenceSetupScreen({super.key, required this.eventModel});

  @override
  State<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends State<GeofenceSetupScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  late GoogleMapController mapController;
  LatLng? selectedLocation;
  double radius = 10.0; // Default radius in feet

  Set<Marker> markers = {};
  Set<Circle> circles = {};

  // Search state
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();

    // Initialize radius from event if present
    if (widget.eventModel.radius > 0) {
      radius = widget.eventModel.radius;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _addMarker(LatLng latLng) {
    setState(() {
      markers.clear();
      circles.clear();

      markers.add(
        Marker(
          markerId: const MarkerId('selected-location'),
          position: latLng,
          infoWindow: const InfoWindow(title: 'Event Location'),
        ),
      );

      circles.add(
        Circle(
          circleId: const CircleId('radius-circle'),
          center: latLng,
          radius: radius * 0.3048, // Convert feet to meters
          fillColor: const Color(0xFF667EEA).withOpacity(0.2),
          strokeColor: const Color(0xFF667EEA),
          strokeWidth: 2,
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    // Start with a "globe" view
    await mapController.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: LatLng(0, 0),
          zoom: 1.3, // World view
        ),
      ),
    );

    // If event has existing coordinates, add marker but do not auto-zoom
    if (widget.eventModel.latitude != 0 && widget.eventModel.longitude != 0) {
      final eventLatLng = widget.eventModel.getLatLng();
      selectedLocation = eventLatLng;
      _addMarker(eventLatLng);
    }
  }

  Future<void> _zoomToEvent() async {
    if (widget.eventModel.latitude == 0 && widget.eventModel.longitude == 0) {
      ShowToast().showNormalToast(msg: 'No event location set yet');
      return;
    }
    final eventLatLng = widget.eventModel.getLatLng();
    await mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: eventLatLng, zoom: 16),
      ),
    );
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final latLng = LatLng(loc.latitude, loc.longitude);
        await mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 14),
          ),
        );
      } else {
        ShowToast().showNormalToast(msg: 'No results found for "$query"');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Search failed');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(opacity: _fadeAnimation, child: _bodyView()),
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          _headerView(),
          Expanded(child: _contentView()),
        ],
      ),
    );
  }

  Widget _headerView() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          // Back button and title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Set Distance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              // Zoom to event
              GestureDetector(
                onTap: _zoomToEvent,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.zoom_in_map,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Subtitle
          const Text(
            'Start from a globe view. Zoom in to set your exact event location and distance.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _searchPlace(),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search a place',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _isSearching ? null : _searchPlace,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: _isSearching ? 0.2 : 0.3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isSearching ? 'Searching...' : 'Go',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Event Info Card
            _buildEventInfoCard(),
            const SizedBox(height: 24),
            // Map Container
            _buildMapContainer(),
            const SizedBox(height: 24),
            // Distance Slider
            _buildDistanceSlider(),
            const Spacer(),
            // Continue Button
            _buildContinueButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.eventModel.title,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Text(
                      widget.eventModel.location,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapContainer() {
    return Container(
      width: double.infinity,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: const CameraPosition(
                target: LatLng(0, 0),
                zoom: 1.3,
              ),
              markers: markers,
              circles: circles,
              onTap: (LatLng latLng) {
                setState(() {
                  selectedLocation = latLng;
                });
                _addMarker(latLng);
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            // Zoom controls
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _mapIconBtn(
                    Icons.add,
                    () => mapController.animateCamera(CameraUpdate.zoomIn()),
                  ),
                  const SizedBox(height: 8),
                  _mapIconBtn(
                    Icons.remove,
                    () => mapController.animateCamera(CameraUpdate.zoomOut()),
                  ),
                ],
              ),
            ),
            // Helper hint
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Tap on the map to set the event location. Use the slider below to adjust distance.',
                  style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapIconBtn(IconData icon, VoidCallback onTap) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Icon(icon, color: const Color(0xFF667EEA)),
        ),
      ),
    );
  }

  Widget _buildDistanceSlider() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.radar,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Detection Distance',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${radius.toInt()} feet',
            style: const TextStyle(
              color: Color(0xFF667EEA),
              fontWeight: FontWeight.bold,
              fontSize: 18,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            value: radius,
            min: 5.0,
            max: 100.0,
            divisions: 19,
            activeColor: const Color(0xFF667EEA),
            inactiveColor: Colors.grey[300],
            onChanged: (value) {
              setState(() {
                radius = value;
                if (selectedLocation != null) {
                  _addMarker(selectedLocation!);
                }
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '5 ft',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
              Text(
                '100 ft',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (selectedLocation == null) {
              ShowToast().showNormalToast(
                msg: 'Please select a location on the map',
              );
              return;
            }

            try {
              // Update the event with geofence settings
              await FirebaseFirestore.instance
                  .collection(EventModel.firebaseKey)
                  .doc(widget.eventModel.id)
                  .update({
                    'latitude': selectedLocation!.latitude,
                    'longitude': selectedLocation!.longitude,
                    'radius': radius,
                    'getLocation': true,
                  });

              ShowToast().showNormalToast(
                msg: 'Geofence settings updated successfully!',
              );
              if (!mounted) return;
              Navigator.pop(context);
            } catch (e) {
              if (!mounted) return;
              ShowToast().showNormalToast(
                msg: 'Failed to update geofence settings: $e',
              );
            }
          },
          child: const Center(
            child: Text(
              'Save Settings',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
