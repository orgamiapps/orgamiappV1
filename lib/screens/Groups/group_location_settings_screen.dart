import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/models/organization_model.dart';
// Removed current location helper import since feature is not used here

class GroupLocationSettingsScreen extends StatefulWidget {
  final String organizationId;
  final OrganizationModel organization;

  const GroupLocationSettingsScreen({
    super.key,
    required this.organizationId,
    required this.organization,
  });

  @override
  State<GroupLocationSettingsScreen> createState() =>
      _GroupLocationSettingsScreenState();
}

class _GroupLocationSettingsScreenState
    extends State<GroupLocationSettingsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isSaving = false;
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  String? _selectedLocationAddress;
  double? _selectedLatitude;
  double? _selectedLongitude;
  late final String _placesSessionToken;

  @override
  void initState() {
    super.initState();
    _placesSessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    _initializeCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _initializeCurrentLocation() {
    if (widget.organization.locationAddress != null &&
        widget.organization.locationAddress!.isNotEmpty) {
      _searchController.text = widget.organization.locationAddress!;
      _selectedLocationAddress = widget.organization.locationAddress;
      _selectedLatitude = widget.organization.latitude;
      _selectedLongitude = widget.organization.longitude;
    }
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = value.trim();
      if (query.length < 2) {
        setState(() => _suggestions = []);
        return;
      }
      _fetchLocationSuggestions(query);
    });
  }

  /// Build a "City, ST" string from Google address components
  String _cityStateFromComponents(List<dynamic>? components) {
    if (components == null) return '';
    String? city;
    String? state;

    for (final component in components) {
      try {
        final types = (component['types'] as List?)?.cast<String>() ?? const [];
        if (types.contains('administrative_area_level_1')) {
          state = component['short_name'] as String?;
        }
        if (types.contains('locality')) {
          city = component['long_name'] as String?;
        }
        // Fallbacks for places where locality may be absent
        if (city == null &&
            (types.contains('postal_town') ||
                types.contains('administrative_area_level_2') ||
                types.contains('sublocality') ||
                types.contains('neighborhood'))) {
          city = component['long_name'] as String?;
        }
      } catch (_) {
        // Ignore malformed component entries
      }
    }

    if ((city ?? '').isNotEmpty && (state ?? '').isNotEmpty) {
      return '${city!}, ${state!}';
    }
    return '';
  }

  Future<void> _fetchLocationSuggestions(String input) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'key': AppConstants.googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
          'types': '(cities)',
          'components': 'country:us',
          'language': 'en',
        },
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List predictions = data['predictions'] ?? [];
          setState(() {
            _suggestions = predictions.cast<Map<String, dynamic>>();
          });
        } else {
          setState(() => _suggestions = []);
        }
      }
    } catch (e) {
      debugPrint('Error fetching location suggestions: $e');
      setState(() => _suggestions = []);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectLocation(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String?;
    if (placeId == null) return;

    setState(() => _isLoading = true);

    try {
      final detailsUri =
          Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
            'place_id': placeId,
            'fields': 'geometry,name,formatted_address,address_components',
            'key': AppConstants.googlePlacesApiKey,
            'sessiontoken': _placesSessionToken,
          });

      final response = await http.get(detailsUri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final geometry = result['geometry'];
          final location = geometry?['location'];
          final components = (result['address_components'] as List?)
              ?.cast<dynamic>();

          if (location != null) {
            // Prefer "City, ST" formatting for display and storage
            String displayAddress = _cityStateFromComponents(components).trim();
            if (displayAddress.isEmpty) {
              // Fallback to Google's formatted address or suggestion description
              displayAddress =
                  (result['formatted_address'] as String?) ??
                  (suggestion['description'] as String? ?? '');
              // Strip trailing ", USA" if present
              if (displayAddress.endsWith(', USA')) {
                displayAddress = displayAddress.substring(
                  0,
                  displayAddress.length - 5,
                );
              }
            }
            final lat = (location['lat'] as num).toDouble();
            final lng = (location['lng'] as num).toDouble();

            setState(() {
              _searchController.text = displayAddress;
              _selectedLocationAddress = displayAddress;
              _selectedLatitude = lat;
              _selectedLongitude = lng;
              _suggestions = [];
            });

            _searchFocusNode.unfocus();
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting place details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLocation() async {
    if (_selectedLocationAddress == null ||
        _selectedLatitude == null ||
        _selectedLongitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _db.collection('Organizations').doc(widget.organizationId).update({
        'locationAddress': _selectedLocationAddress,
        'latitude': _selectedLatitude,
        'longitude': _selectedLongitude,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group location updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint('Error saving location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _removeLocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Location'),
        content: const Text(
          'Are you sure you want to remove the group location? This will make your group location-independent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      await _db.collection('Organizations').doc(widget.organizationId).update({
        'locationAddress': FieldValue.delete(),
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
      });

      setState(() {
        _searchController.clear();
        _selectedLocationAddress = null;
        _selectedLatitude = null;
        _selectedLongitude = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group location removed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation =
        _selectedLocationAddress != null &&
        _selectedLatitude != null &&
        _selectedLongitude != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Location Settings',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (hasLocation)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isSaving ? null : _removeLocation,
              tooltip: 'Remove location',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
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
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.1),
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
                                  'Group Location',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Set a location to help members find local events and connect with nearby groups.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Search section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search for a city or state in the US...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          prefixIcon: _isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : Icon(Icons.search, color: Colors.grey[500]),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.grey[500],
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _suggestions = [];
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF667EEA),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),
                    ],
                  ),
                ),

                // Suggestions
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Text(
                            'Suggestions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _suggestions.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            final description =
                                suggestion['description'] as String? ?? '';
                            final mainText =
                                suggestion['structured_formatting']?['main_text']
                                    as String? ??
                                '';
                            final secondaryText =
                                suggestion['structured_formatting']?['secondary_text']
                                    as String? ??
                                '';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF667EEA,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.location_city,
                                  color: Color(0xFF667EEA),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                mainText.isNotEmpty ? mainText : description,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: secondaryText.isNotEmpty
                                  ? Text(
                                      secondaryText,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                              onTap: () => _selectLocation(suggestion),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                // Current location display
                if (hasLocation) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Selected Location',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedLocationAddress!,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.green[700],
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Coordinates: ${_selectedLatitude!.toStringAsFixed(6)}, ${_selectedLongitude!.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 100), // Space for bottom button
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_isSaving || !hasLocation) ? null : _saveLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
