import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class EventLocationViewScreen extends StatefulWidget {
  final EventModel eventModel;

  const EventLocationViewScreen({super.key, required this.eventModel});

  @override
  State<EventLocationViewScreen> createState() =>
      _EventLocationViewScreenState();
}

class _EventLocationViewScreenState extends State<EventLocationViewScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  late GoogleMapController mapController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  Set<Marker> markers = {};
  Set<Circle> circles = {};

  // Address lookup state
  String? _resolvedAddress;
  bool _isLoadingAddress = false;

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

    _initializeMap();
    _getAddressFromCoordinates();
  }

  void _initializeMap() {
    if (widget.eventModel.latitude != 0 && widget.eventModel.longitude != 0) {
      final eventLocation = widget.eventModel.getLatLng();

      setState(() {
        markers.add(
          Marker(
            markerId: const MarkerId('event-location'),
            position: eventLocation,
            infoWindow: InfoWindow(
              title: widget.eventModel.title,
              snippet: widget.eventModel.location,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );

        // Add a subtle circle around the location
        circles.add(
          Circle(
            circleId: const CircleId('location-circle'),
            center: eventLocation,
            radius: 100, // 100 meters radius
            fillColor: const Color(0xFF667EEA).withValues(alpha: 0.1),
            strokeColor: const Color(0xFF667EEA),
            strokeWidth: 2,
          ),
        );
      });
    }
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
          _bottomPanel(),
        ],
      ),
    );
  }

  Widget _headerView() {
    return Container(
      width: _screenWidth,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Event Location',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.eventModel.title,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
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
          initialCameraPosition: const CameraPosition(
            target: LatLng(0, 0),
            zoom: 1.3,
          ),
          markers: markers,
          circles: circles,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
        ),
        // Map controls
        Positioned(
          top: 20,
          right: 20,
          child: Column(
            children: [
              // Zoom to event button
              Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(bottom: 12),
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
                    onTap: () {
                      final lat = widget.eventModel.latitude;
                      final lng = widget.eventModel.longitude;
                      if (lat == 0 || lng == 0) {
                        ShowToast().showSnackBar('Location not set', context);
                        return;
                      }
                      final latLng = widget.eventModel.getLatLng();
                      mapController.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: latLng, zoom: 16),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.zoom_in_map,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Zoom in button
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
                    onTap: () {
                      mapController.animateCamera(CameraUpdate.zoomIn());
                    },
                    child: const Icon(
                      Icons.add,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Zoom out button
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
                    onTap: () {
                      mapController.animateCamera(CameraUpdate.zoomOut());
                    },
                    child: const Icon(
                      Icons.remove,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Map controls
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Open in Maps
                GestureDetector(
                  onTap: _openInMaps,
                  child: Row(
                    children: [
                      const Icon(Icons.map, color: Color(0xFF667EEA), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Open in Maps',
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                // Share
                GestureDetector(
                  onTap: _shareLocation,
                  child: Row(
                    children: [
                      const Icon(Icons.share, color: Color(0xFF667EEA), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Share',
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomPanel() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: _screenWidth,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Event details
            _buildEventDetails(),
            const SizedBox(height: 24),
            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFF667EEA),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  _isLoadingAddress
                      ? Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF667EEA),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Loading exact address...',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                fontFamily: 'Roboto',
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _resolvedAddress ?? widget.eventModel.location,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_month,
                color: Color(0xFF10B981),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date & Time',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat(
                      'EEEE, MMMM dd, yyyy • KK:mm a',
                    ).format(widget.eventModel.selectedDateTime),
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openInMaps,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.directions,
                      color: Color(0xFF667EEA),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Get Directions',
                      style: const TextStyle(
                        color: Color(0xFF667EEA),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _shareLocation,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Share Location',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    // Start with a globe view; do not auto-zoom to event
    mapController.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(target: LatLng(0, 0), zoom: 1.3),
      ),
    );
  }

  /// Gets the address from latitude and longitude coordinates using reverse geocoding
  Future<void> _getAddressFromCoordinates() async {
    // Only attempt if coordinates are available
    if (widget.eventModel.latitude == 0 || widget.eventModel.longitude == 0) {
      return;
    }

    setState(() {
      _isLoadingAddress = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        widget.eventModel.latitude,
        widget.eventModel.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];

        // Build a formatted address from placemark components
        List<String> addressParts = [];

        if (place.street?.isNotEmpty == true) {
          addressParts.add(place.street!);
        }
        if (place.locality?.isNotEmpty == true) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea?.isNotEmpty == true) {
          addressParts.add(place.administrativeArea!);
        }
        if (place.postalCode?.isNotEmpty == true) {
          addressParts.add(place.postalCode!);
        }
        if (place.country?.isNotEmpty == true) {
          addressParts.add(place.country!);
        }

        String formattedAddress;
        if (addressParts.isNotEmpty) {
          formattedAddress = addressParts.join(', ');
        } else {
          // Fallback to name or locality if no detailed address is available
          if (place.name?.isNotEmpty == true) {
            formattedAddress = place.name!;
          } else if (place.locality?.isNotEmpty == true) {
            formattedAddress = place.locality!;
          } else {
            formattedAddress =
                'Location coordinates: ${widget.eventModel.latitude.toStringAsFixed(6)}, ${widget.eventModel.longitude.toStringAsFixed(6)}';
          }
        }

        setState(() {
          _resolvedAddress = formattedAddress;
          _isLoadingAddress = false;
        });
      } else {
        throw Exception('No address found for coordinates');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAddress = false;
          // Fallback to coordinates display
          _resolvedAddress =
              'Coordinates: ${widget.eventModel.latitude.toStringAsFixed(6)}, ${widget.eventModel.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  void _openInMaps() async {
    try {
      final lat = widget.eventModel.latitude;
      final lng = widget.eventModel.longitude;
      final location = Uri.encodeComponent(widget.eventModel.location);

      // Try to open in Google Maps
      final googleMapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      final uri = Uri.parse(googleMapsUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        ShowToast().showSnackBar('Opening Google Maps...', context);
      } else {
        // Fallback to Apple Maps on iOS
        final appleMapsUrl = 'https://maps.apple.com/?q=$location&ll=$lat,$lng';
        final appleUri = Uri.parse(appleMapsUrl);
        if (await canLaunchUrl(appleUri)) {
          await launchUrl(appleUri, mode: LaunchMode.externalApplication);
          if (!mounted) return;
          ShowToast().showSnackBar('Opening Maps...', context);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Unable to open maps', context);
    }
  }

  void _shareLocation() async {
    try {
      final lat = widget.eventModel.latitude;
      final lng = widget.eventModel.longitude;
      final location = widget.eventModel.location;
      final eventTitle = widget.eventModel.title;

      final shareText =
          'Check out this event: $eventTitle\n'
          'Location: $location\n'
          'Date: ${DateFormat('EEEE, MMMM dd, yyyy').format(widget.eventModel.selectedDateTime)}\n'
          'Time: ${DateFormat('KK:mm a').format(widget.eventModel.selectedDateTime)} – ${DateFormat('KK:mm a').format(widget.eventModel.eventEndTime)}\n'
          'Maps: https://www.google.com/maps/search/?api=1&query=$lat,$lng';

      // Use the existing share functionality
      await SharePlus.instance.share(
        ShareParams(text: shareText, subject: 'Event Location: $eventTitle'),
      );
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Unable to share location', context);
    }
  }
}
