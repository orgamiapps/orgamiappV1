import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:attendus/Utils/app_constants.dart';

// Model to return both location and radius
class LocationPickerResult {
  final LatLng location;
  final double radius;

  LocationPickerResult({required this.location, required this.radius});
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final double? initialRadius;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    this.initialRadius,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with TickerProviderStateMixin {
  late GoogleMapController _mapController;
  bool _mapReady = false;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  double _radius = 100.0; // Default radius in feet

  // Search state
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<dynamic> _suggestions = [];
  late final String _placesSessionToken = DateTime.now().millisecondsSinceEpoch
      .toString();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _radius = widget.initialRadius ?? 100.0;
    if (_selectedLocation != null) {
      _addMarker(_selectedLocation!);
    }
  }

  void _addMarker(LatLng latLng) {
    setState(() {
      _markers = {Marker(markerId: const MarkerId('picked'), position: latLng)};
      _circles = {
        Circle(
          circleId: const CircleId('radius-circle'),
          center: latLng,
          radius: _radius * 0.3048, // Convert feet to meters
          fillColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
          strokeColor: const Color(0xFF667EEA),
          strokeWidth: 2,
        ),
      };
      _selectedLocation = latLng;
    });
  }

  void _updateRadius(double newRadius) {
    setState(() {
      _radius = newRadius;
      if (_selectedLocation != null) {
        _circles = {
          Circle(
            circleId: const CircleId('radius-circle'),
            center: _selectedLocation!,
            radius: _radius * 0.3048, // Convert feet to meters
            fillColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
            strokeColor: const Color(0xFF667EEA),
            strokeWidth: 2,
          ),
        };
      }
    });
  }

  Future<void> _centerOnUser() async {
    try {
      if (!_mapReady) return;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      _mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 15),
        ),
      );
      _addMarker(latLng);
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = value.trim();
      if (query.length < 2) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      await _fetchPlaceSuggestions(query);
    });
  }

  Future<void> _fetchPlaceSuggestions(String input) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'key': AppConstants.googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List predictions = (data['predictions'] as List?) ?? [];
        if (mounted) setState(() => _suggestions = predictions);
      }
    } catch (_) {}
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    try {
      final placeId = suggestion['place_id'] as String?;
      if (placeId == null) return;
      final detailsUri =
          Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
            'place_id': placeId,
            'fields': 'geometry,name,formatted_address',
            'key': AppConstants.googlePlacesApiKey,
            'sessiontoken': _placesSessionToken,
          });
      final res = await http.get(detailsUri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final result = data['result'];
        final loc = result['geometry']?['location'];
        if (loc != null) {
          final latLng = LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          );
          _mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: latLng, zoom: 16),
            ),
          );
          _addMarker(latLng);
          if (mounted) {
            setState(() {
              _searchController.text =
                  (result['formatted_address'] as String?) ??
                  (suggestion['description'] as String? ?? '');
              _suggestions = [];
            });
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.initialLocation ??
        const LatLng(37.42796133580664, -122.085749655962);
    return Scaffold(
      appBar: AppBar(title: const Text('Pick Location')),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) {
              _mapController = c;
              _mapReady = true;
            },
            initialCameraPosition: CameraPosition(target: initial, zoom: 12),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            onTap: (latLng) {
              _addMarker(latLng);
              if (_suggestions.isNotEmpty) {
                setState(() => _suggestions = []);
              }
            },
            markers: _markers,
            circles: _circles,
          ),
          // Search bar
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search for a place or address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _suggestions = [];
                                });
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.1),
                      ),
                    ),
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final s = _suggestions[index] as Map<String, dynamic>;
                        final desc = s['description'] as String? ?? '';
                        return ListTile(
                          leading: const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF667EEA),
                          ),
                          title: Text(desc),
                          onTap: () => _selectSuggestion(s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // My location button (placed under search)
          Positioned(
            right: 16,
            top: 84,
            child: FloatingActionButton(
              heroTag: 'my_loc',
              mini: true,
              onPressed: _centerOnUser,
              tooltip: 'My location',
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedLocation == null
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Radius slider section
                    Row(
                      children: [
                        const Icon(
                          Icons.radio_button_checked,
                          color: Color(0xFF667EEA),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Geofence Radius',
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
                            '${_radius.round()} ft',
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
                    const SizedBox(height: 12),
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
                        value: _radius,
                        min: 10,
                        max: 1000,
                        divisions: 99,
                        onChanged: _updateRadius,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Use this location button
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667EEA),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final result = LocationPickerResult(
                            location: LatLng(
                              _selectedLocation!.latitude,
                              _selectedLocation!.longitude,
                            ),
                            radius: _radius,
                          );
                          Navigator.of(context).pop<LocationPickerResult>(result);
                        },
                        child: const Text(
                          'Use this location',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
