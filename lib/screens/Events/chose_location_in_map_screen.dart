import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:orgami/screens/Events/add_questions_prompt_screen.dart';
import 'package:orgami/Utils/router.dart';

class ChoseLocationInMapScreen extends StatefulWidget {
  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final List<String>? selectedSignInMethods;
  final String? manualCode;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;

  const ChoseLocationInMapScreen({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.selectedSignInMethods,
    this.manualCode,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
  });

  @override
  State<ChoseLocationInMapScreen> createState() =>
      _ChoseLocationInMapScreenState();
}

class _ChoseLocationInMapScreenState extends State<ChoseLocationInMapScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  late GoogleMapController mapController;
  LatLng? selectedLocation;
  double radius = 10.0; // Default radius

  Set<Marker> markers = {};
  Set<Circle> circles = {};

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    await Geolocator.getCurrentPosition().then((value) {
      LatLng newLatLng = LatLng(value.latitude, value.longitude);
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newLatLng, zoom: 15),
        ),
      );
      _addMarker(newLatLng);
      if (kDebugMode) {
        debugPrint(
          'Current Location is ${value.latitude} and ${value.longitude} and ${value.floor}',
        );
      }
    });
  }

  void _addMarker(LatLng latLng) {
    setState(() {
      markers.clear(); // Clear existing markers
      circles.clear(); // Clear existing circles

      markers.add(
        Marker(
          markerId: const MarkerId('selected-location'),
          position: latLng,
          infoWindow: const InfoWindow(title: 'Selected Location'),
        ),
      );

      // Add circle to show radius
      circles.add(
        Circle(
          circleId: const CircleId('radius-circle'),
          center: latLng,
          radius: radius * 0.3048, // Convert feet to meters
          fillColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
          strokeColor: const Color(0xFF667EEA),
          strokeWidth: 2,
        ),
      );

      selectedLocation = latLng;
    });
  }

  void _updateRadius(double newRadius) {
    setState(() {
      radius = newRadius;
      if (selectedLocation != null) {
        circles.clear();
        circles.add(
          Circle(
            circleId: const CircleId('radius-circle'),
            center: selectedLocation!,
            radius: radius * 0.3048, // Convert feet to meters
            fillColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
            strokeColor: const Color(0xFF667EEA),
            strokeWidth: 2,
          ),
        );
      }
    });
  }

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

    _getCurrentLocation();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
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
          Expanded(child: _mapView()),
          if (selectedLocation != null) _bottomPanel(),
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
                    color: Colors.white.withValues(alpha: 0.2),
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
                  'Select Location and Radius',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Subtitle
          const Text(
            'Tap on the map to select a location and adjust the radius',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    return Stack(
      children: [
        // Map
        GoogleMap(
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(
            target: selectedLocation != null
                ? selectedLocation!
                : const LatLng(37.42796133580664, -122.085749655962),
            zoom: 12.0,
          ),
          onTap: _onMapTapped,
          markers: markers,
          circles: circles,
        ),
        // Map controls
        Positioned(
          top: 20,
          right: 20,
          child: Column(
            children: [
              // Location button
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _getCurrentLocation,
                    child: const Icon(
                      Icons.my_location,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Zoom controls
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        onTap: () {
                          mapController.animateCamera(CameraUpdate.zoomIn());
                        },
                        child: const SizedBox(
                          width: 48,
                          height: 40,
                          child: Icon(
                            Icons.add,
                            color: Color(0xFF667EEA),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 1,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        onTap: () {
                          mapController.animateCamera(CameraUpdate.zoomOut());
                        },
                        child: const SizedBox(
                          width: 48,
                          height: 40,
                          child: Icon(
                            Icons.remove,
                            color: Color(0xFF667EEA),
                            size: 20,
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
      ],
    );
  }

  Widget _bottomPanel() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF000000),
              spreadRadius: 0,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Radius selection
            Row(
              children: [
                const Icon(
                  Icons.radio_button_checked,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Select Radius (Feet)',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${radius.round()} Feet',
                    style: const TextStyle(
                      color: Color(0xFF667EEA),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF667EEA),
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                thumbColor: const Color(0xFF667EEA),
                overlayColor: const Color(0xFF667EEA).withValues(alpha: 0.1),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                trackHeight: 4,
              ),
              child: Slider(
                value: radius,
                min: 10,
                max: 1000,
                divisions: 99,
                onChanged: _updateRadius,
              ),
            ),
            const SizedBox(height: 24),
            // Continue button
            Container(
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
                    color: const Color(0xFF667EEA).withValues(alpha: 0.3),
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
                  onTap: () {
                    if (kDebugMode) {
                      debugPrint('Selected Location: $selectedLocation');
                      debugPrint('Selected Radius: $radius feet');
                    }

                    RouterClass.nextScreenNormal(
                      context,
                      AddQuestionsPromptScreen(
                        selectedDateTime: widget.selectedDateTime,
                        eventDurationHours: widget.eventDurationHours,
                        selectedLocation: selectedLocation!,
                        radios: radius,
                        selectedSignInMethods:
                            widget.selectedSignInMethods ??
                            const ['qr_code', 'manual_code'],
                        manualCode: widget.manualCode,
                        preselectedOrganizationId:
                            widget.preselectedOrganizationId,
                        forceOrganizationEvent: widget.forceOrganizationEvent,
                      ),
                    );
                  },
                  child: const Center(
                    child: Text(
                      'Continue',
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
            ),
          ],
        ),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    setState(() {
      mapController = controller;
    });
  }

  void _onMapTapped(LatLng location) {
    _addMarker(location);
    mapController.moveCamera(CameraUpdate.newLatLng(location));
  }
}
