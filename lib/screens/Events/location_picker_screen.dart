import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:attendus/Utils/app_constants.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with TickerProviderStateMixin {
  late GoogleMapController _mapController;
  bool _mapReady = false;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};

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
    if (_selectedLocation != null) {
      _addMarker(_selectedLocation!);
    }
  }

  void _addMarker(LatLng latLng) {
    setState(() {
      _markers = {Marker(markerId: const MarkerId('picked'), position: latLng)};
      _selectedLocation = latLng;
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _selectedLocation == null
                  ? null
                  : () {
                      // Ensure we return a concrete LatLng value
                      final LatLng result = LatLng(
                        _selectedLocation!.latitude,
                        _selectedLocation!.longitude,
                      );
                      Navigator.of(context).pop<LatLng>(result);
                    },
              child: const Text('Use this location'),
            ),
          ),
        ),
      ),
    );
  }
}
