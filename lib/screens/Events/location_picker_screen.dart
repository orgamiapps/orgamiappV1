import 'dart:async';

import 'package:attendus/Services/places_service.dart';
import 'package:attendus/Utils/google_maps_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef LocationPickerMapBuilder =
    Widget Function(ValueChanged<LatLng> onMapTap);

class PlaceSelection {
  final LatLng location;
  final String? placeId;
  final String displayName;
  final String formattedAddress;

  const PlaceSelection({
    required this.location,
    required this.displayName,
    required this.formattedAddress,
    this.placeId,
  });
}

class LocationPickerResult {
  final PlaceSelection selection;
  final double radius;

  const LocationPickerResult({required this.selection, required this.radius});

  LatLng get location => selection.location;
  String? get placeId => selection.placeId;
  String get displayName => selection.displayName;
  String get formattedAddress => selection.formattedAddress;
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final double? initialRadius;
  final String? initialPlaceId;
  final String? initialDisplayName;
  final String? initialAddress;
  final PlacesService? placesService;
  final bool mapEnabled;
  final LocationPickerMapBuilder? mapBuilder;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    this.initialRadius,
    this.initialPlaceId,
    this.initialDisplayName,
    this.initialAddress,
    this.placesService,
    this.mapEnabled = true,
    this.mapBuilder,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final PlacesService _places;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  GoogleMapController? _mapController;
  Timer? _debounce;
  late String _sessionToken;
  int _searchRequest = 0;
  bool _mapReady = false;
  bool _isSearching = false;
  bool _isResolving = false;
  bool _isLocating = false;
  bool _hasSearched = false;
  String? _searchError;
  LatLng? _locationBias;
  PlaceSelection? _selection;
  List<PlaceSuggestion> _suggestions = const [];
  double _radius = 100;
  Set<Marker> _markers = const {};
  Set<Circle> _circles = const {};

  bool get _hasValidSelection {
    final location = _selection?.location;
    return location != null &&
        location.latitude >= -90 &&
        location.latitude <= 90 &&
        location.longitude >= -180 &&
        location.longitude <= 180 &&
        !(location.latitude == 0 && location.longitude == 0);
  }

  @override
  void initState() {
    super.initState();
    _places = widget.placesService ?? PlacesService();
    _sessionToken = _places.createSessionToken();
    _radius = widget.initialRadius ?? 100;
    final initial = widget.initialLocation;
    if (initial != null && !(initial.latitude == 0 && initial.longitude == 0)) {
      _selection = PlaceSelection(
        location: initial,
        placeId: widget.initialPlaceId,
        displayName: widget.initialDisplayName ?? '',
        formattedAddress:
            widget.initialAddress ??
            '${initial.latitude.toStringAsFixed(6)}, ${initial.longitude.toStringAsFixed(6)}',
      );
      _searchController.text = _selection!.formattedAddress;
      _updateMarker(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _updateMarker(LatLng location) {
    _markers = {Marker(markerId: const MarkerId('picked'), position: location)};
    _circles = {
      Circle(
        circleId: const CircleId('radius-circle'),
        center: location,
        radius: _radius * 0.3048,
        fillColor: const Color(0xFF667EEA).withValues(alpha: 0.18),
        strokeColor: const Color(0xFF667EEA),
        strokeWidth: 2,
      ),
    };
  }

  void _updateRadius(double value) {
    setState(() {
      _radius = value;
      if (_selection != null) _updateMarker(_selection!.location);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (_selection != null &&
        query != _selection!.formattedAddress &&
        query != _selection!.displayName) {
      _selection = null;
      _markers = const {};
      _circles = const {};
    }
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _searchError = null;
        _isSearching = false;
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final request = ++_searchRequest;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await _places.autocomplete(
        query: query,
        sessionToken: _sessionToken,
        locationBias: _locationBias,
      );
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _suggestions = results;
        _hasSearched = true;
      });
    } on PlacesServiceException catch (error) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _suggestions = const [];
        _searchError = error.message;
        _hasSearched = false;
      });
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _isResolving = true;
      _searchError = null;
    });
    try {
      final details = await _places.details(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      final selection = PlaceSelection(
        location: details.location,
        placeId: details.placeId,
        displayName: details.displayName.isNotEmpty
            ? details.displayName
            : suggestion.primaryText,
        formattedAddress: details.formattedAddress.isNotEmpty
            ? details.formattedAddress
            : suggestion.description,
      );
      setState(() {
        _selection = selection;
        _searchController.text = selection.formattedAddress;
        _suggestions = const [];
        _hasSearched = false;
        _updateMarker(selection.location);
        _sessionToken = _places.createSessionToken();
      });
      _searchFocusNode.unfocus();
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: selection.location, zoom: 16),
        ),
      );
    } on PlacesServiceException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _selectPin(LatLng location) async {
    final coordinateLabel =
        '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
    setState(() {
      _selection = PlaceSelection(
        location: location,
        displayName: 'Pinned location',
        formattedAddress: coordinateLabel,
      );
      _searchController.text = coordinateLabel;
      _suggestions = const [];
      _hasSearched = false;
      _searchError = null;
      _isResolving = true;
      _updateMarker(location);
    });
    try {
      final details = await _places.reverseGeocode(location);
      if (!mounted || _selection?.location != location) return;
      setState(() {
        _selection = PlaceSelection(
          location: location,
          placeId: details.placeId,
          displayName: 'Pinned location',
          formattedAddress: details.formattedAddress.isEmpty
              ? coordinateLabel
              : details.formattedAddress,
        );
        _searchController.text = _selection!.formattedAddress;
      });
    } on PlacesServiceException catch (error) {
      if (mounted && _selection?.location == location) {
        setState(() => _searchError = error.message);
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _centerOnUser() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const PlacesServiceException(
          'Turn on location services to use your current location.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const PlacesServiceException(
          'Location permission is required to use your current position.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final location = LatLng(position.latitude, position.longitude);
      _locationBias = location;
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: location, zoom: 16),
        ),
      );
      await _selectPin(location);
    } on PlacesServiceException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchError = 'Could not get your location. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _selection?.location ?? const LatLng(20.0, 0.0);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Pick event location')),
      body: Stack(
        children: [
          if (widget.mapBuilder != null)
            widget.mapBuilder!(_selectPin)
          else if (widget.mapEnabled && GoogleMapsBootstrap.isAvailable)
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                setState(() => _mapReady = true);
              },
              initialCameraPosition: CameraPosition(
                target: initial,
                zoom: _selection == null ? 2 : 14,
              ),
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              markers: _markers,
              circles: _circles,
              onTap: _selectPin,
            )
          else
            Container(
              color: const Color(0xFFE8EDF3),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Text(
                GoogleMapsBootstrap.errorMessage ?? 'Map unavailable',
                textAlign: TextAlign.center,
              ),
            ),
          Positioned(left: 16, right: 16, top: 16, child: _searchPanel()),
          if (widget.mapEnabled && GoogleMapsBootstrap.isAvailable)
            Positioned(
              right: 16,
              top: 88,
              child: FloatingActionButton.small(
                heroTag: 'picker_my_location',
                onPressed: _mapReady && !_isLocating ? _centerOnUser : null,
                tooltip: 'Use my location',
                child: _isLocating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _hasValidSelection ? _selectionPanel() : null,
    );
  }

  Widget _searchPanel() {
    return Column(
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search for a venue or address',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching || _isResolving
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _debounce?.cancel();
                        ++_searchRequest;
                        setState(() {
                          _searchController.clear();
                          _selection = null;
                          _suggestions = const [];
                          _hasSearched = false;
                          _markers = const {};
                          _circles = const {};
                          _searchError = null;
                        });
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      suggestion.primaryText.isEmpty
                          ? suggestion.description
                          : suggestion.primaryText,
                    ),
                    subtitle: suggestion.secondaryText.isEmpty
                        ? null
                        : Text(suggestion.secondaryText),
                    onTap: () => _selectSuggestion(suggestion),
                  ),
                );
              },
            ),
          ),
        if (_hasSearched &&
            !_isSearching &&
            _suggestions.isEmpty &&
            _searchError == null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.search_off_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No locations found. Try a venue name, street address, or city.',
                  ),
                ),
              ],
            ),
          ),
        if (_searchError != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_searchError!)),
                if (_searchController.text.trim().length >= 3)
                  TextButton(
                    onPressed: () => _search(_searchController.text.trim()),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _selectionPanel() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selection!.displayName.isEmpty
                  ? 'Selected location'
                  : _selection!.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _selection!.formattedAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Geofence radius'),
                const Spacer(),
                Text('${_radius.round()} ft'),
              ],
            ),
            Slider(
              value: _radius,
              min: 10,
              max: 1000,
              divisions: 99,
              onChanged: _updateRadius,
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isResolving
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          LocationPickerResult(
                            selection: _selection!,
                            radius: _radius,
                          ),
                        );
                      },
                child: const Text('Use this location'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
