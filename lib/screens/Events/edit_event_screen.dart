import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

import 'package:image_picker/image_picker.dart';

import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Events/Widget/delete_event_dialogue.dart';

import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/text_fields.dart';
import 'package:attendus/Utils/toast.dart';

import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:attendus/screens/Events/Widget/sign_in_methods_selector.dart';
import 'package:attendus/screens/Events/geofence_setup_screen.dart';
import 'package:attendus/screens/Events/location_picker_screen.dart';
import 'dart:io';

class EditEventScreen extends StatefulWidget {
  final EventModel eventModel;

  const EditEventScreen({super.key, required this.eventModel});

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen>
    with TickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool successMessage = false;
  final _btnCtlr = RoundedLoadingButtonController();

  bool privateEvent = false;
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];
  List<String> _selectedCategories = [];

  final TextEditingController groupNameEdtController = TextEditingController();
  final TextEditingController titleEdtController = TextEditingController();
  final TextEditingController locationEdtController = TextEditingController();
  final TextEditingController thumbnailUrlCtlr = TextEditingController();
  final TextEditingController descriptionEdtController =
      TextEditingController();

  String? _selectedImagePath;
  String? _currentImageUrl;

  // Sign-in methods
  List<String> _selectedSignInMethods = ['qr_code', 'manual_code'];
  String? _manualCode;

  // Location selection
  LatLng? _selectedLocationInternal;
  String? _resolvedAddress;
  bool _isResolvingAddress = false;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize with existing event data
    _initializeEventData();

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
  }

  void _initializeEventData() {
    final event = widget.eventModel;

    groupNameEdtController.text = event.groupName;
    titleEdtController.text = event.title;
    locationEdtController.text = event.location;
    descriptionEdtController.text = event.description;
    _currentImageUrl = event.imageUrl;
    _selectedCategories = List.from(event.categories);
    privateEvent = event.private;
    _selectedSignInMethods = List.from(event.signInMethods);
    _manualCode = event.manualCode;

    // Initialize location
    _selectedLocationInternal = LatLng(event.latitude, event.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reverseGeocodeSelectedLocation();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxHeight: 1200,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
          thumbnailUrlCtlr.text = image.path;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            LocationPickerScreen(initialLocation: _selectedLocationInternal),
      ),
    );
    if (picked != null) {
      setState(() => _selectedLocationInternal = picked);
      await _reverseGeocodeSelectedLocation();
    }
  }

  Future<void> _reverseGeocodeSelectedLocation() async {
    if (_selectedLocationInternal == null) return;
    setState(() => _isResolvingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        _selectedLocationInternal!.latitude,
        _selectedLocationInternal!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if ((p.street ?? '').isNotEmpty) p.street!,
          if ((p.locality ?? '').isNotEmpty) p.locality!,
          if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
          if ((p.postalCode ?? '').isNotEmpty) p.postalCode!,
          if ((p.country ?? '').isNotEmpty) p.country!,
        ];
        final addr = parts.isNotEmpty
            ? parts.join(', ')
            : '${_selectedLocationInternal!.latitude.toStringAsFixed(6)}, ${_selectedLocationInternal!.longitude.toStringAsFixed(6)}';
        setState(() {
          _resolvedAddress = addr;
          locationEdtController.text = addr;
        });
      }
    } catch (_) {
      final lat = _selectedLocationInternal!.latitude.toStringAsFixed(6);
      final lng = _selectedLocationInternal!.longitude.toStringAsFixed(6);
      setState(() {
        _resolvedAddress = 'Coordinates: $lat, $lng';
        locationEdtController.text = _resolvedAddress!;
      });
    } finally {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  Future<String?> _uploadToFirebaseHosting() async {
    if (_selectedImagePath == null) return _currentImageUrl;

    try {
      String? imageUrl;
      Uint8List imageData = await XFile(_selectedImagePath!).readAsBytes();

      // Generate unique filename with timestamp
      final String fileName =
          'event_${DateTime.now().millisecondsSinceEpoch}_${_selectedImagePath.hashCode}.jpg';
      final Reference storageReference = FirebaseStorage.instance.ref().child(
        'events_images/$fileName',
      );

      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      );

      final UploadTask uploadTask = storageReference.putData(
        imageData,
        metadata,
      );

      // Show upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        // You could add a progress indicator here if needed
        // final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      });

      await uploadTask.whenComplete(() async {
        imageUrl = await storageReference.getDownloadURL();
      });

      return imageUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      _btnCtlr.start();

      try {
        if (_selectedLocationInternal == null) {
          _btnCtlr.reset();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please pick the event location'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        String? imageUrl = await _uploadToFirebaseHosting();

        if (imageUrl != null) {
          // Create updated event model
          EventModel updatedEvent = EventModel(
            id: widget.eventModel.id,
            title: titleEdtController.text.trim(),
            description: descriptionEdtController.text.trim(),
            location: locationEdtController.text.trim(),
            groupName: groupNameEdtController.text.trim(),
            imageUrl: imageUrl,
            selectedDateTime: widget.eventModel.selectedDateTime,
            customerUid: widget.eventModel.customerUid,
            categories: _selectedCategories,
            private: privateEvent,
            getLocation: widget.eventModel.getLocation,
            radius: widget.eventModel.radius,
            ticketsEnabled: widget.eventModel.ticketsEnabled,
            maxTickets: widget.eventModel.maxTickets,
            issuedTickets: widget.eventModel.issuedTickets,
            isFeatured: widget.eventModel.isFeatured,
            status: widget.eventModel.status,
            eventGenerateTime: widget.eventModel.eventGenerateTime,
            latitude: _selectedLocationInternal!.latitude,
            longitude: _selectedLocationInternal!.longitude,
            organizationId: widget.eventModel.organizationId,
            accessList: widget.eventModel.accessList,
            signInMethods: _selectedSignInMethods,
            manualCode: _manualCode,
          );

          // Update in Firestore
          await FirebaseFirestore.instance
              .collection(EventModel.firebaseKey)
              .doc(widget.eventModel.id)
              .update(updatedEvent.toJson());

          _btnCtlr.success();
          if (!mounted) return;
          ShowToast().showNormalToast(msg: 'Event updated successfully!');

          // Navigate back to the updated event
          Future.delayed(const Duration(seconds: 1), () {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SingleEventScreen(eventModel: updatedEvent),
              ),
            );
          });
        } else {
          _btnCtlr.error();
          if (!mounted) return;
          ShowToast().showNormalToast(
            msg: 'Failed to upload image. Please try again.',
          );
          Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
        }
      } catch (e) {
        _btnCtlr.error();
        if (!mounted) return;
        ShowToast().showNormalToast(msg: 'Failed to update event: $e');
        Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(children: [_buildHeader(), _buildFormContent()]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                  'Edit Event',
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
          const Text(
            'Update your event details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Event Image
          _buildImageSection(),
          const SizedBox(height: 24),

          // Event Details
          _buildEventDetailsSection(),
          const SizedBox(height: 24),

          // Categories
          _buildCategoriesSection(),
          const SizedBox(height: 24),

          // Sign-In Methods
          _buildSignInMethodsSection(),
          const SizedBox(height: 24),

          // Privacy Settings
          _buildPrivacySection(),
          const SizedBox(height: 32),

          // Submit Button
          _buildSubmitButton(),
          const SizedBox(height: 16),

          // Delete Event Button
          _buildDeleteButton(),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.image,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Event Image',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (_selectedImagePath != null || _currentImageUrl != null)
                    ? const Color(0xFF667EEA)
                    : Colors.grey.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: _selectedImagePath != null || _currentImageUrl != null
                ? _buildImagePreview()
                : _buildUploadPlaceholder(),
          ),
          if (_selectedImagePath != null || _currentImageUrl != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF667EEA),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedImagePath != null
                                ? 'New image selected'
                                : 'Current image',
                            style: TextStyle(
                              color: const Color(0xFF667EEA),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImagePath = null;
                      _currentImageUrl = null;
                      thumbnailUrlCtlr.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Remove',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventDetailsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.event,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Event Details',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Event Title
          AppTextFields.textField2(
            controller: titleEdtController,
            hintText: 'Event Title',
            titleText: 'Event Title',
            width: double.infinity,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter event title';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Organizer Name
          AppTextFields.textField2(
            controller: groupNameEdtController,
            hintText: 'Organizer Name',
            titleText: 'Organizer Name',
            width: double.infinity,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter organizer name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Location selector
          _buildLocationSelector(),
          const SizedBox(height: 16),

          // Description
          AppTextFields.textField2(
            controller: descriptionEdtController,
            hintText: 'Event Description',
            titleText: 'Event Description',
            width: double.infinity,
            maxLines: 4,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter event description';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelector() {
    final hasLocation =
        _selectedLocationInternal != null &&
        !(_selectedLocationInternal!.latitude == 0 &&
            _selectedLocationInternal!.longitude == 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
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
                      if (hasLocation) ...[
                        Text(
                          _resolvedAddress ?? locationEdtController.text,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_selectedLocationInternal!.latitude.toStringAsFixed(6)}, ${_selectedLocationInternal!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'No location selected',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (_isResolvingAddress) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF667EEA),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Resolving address...'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickLocation,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(hasLocation ? 'Change' : 'Pick'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF667EEA)),
                    foregroundColor: const Color(0xFF667EEA),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.category,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Categories',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _allCategories.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCategories.remove(category);
                    } else {
                      _selectedCategories.add(category);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF667EEA)
                        : const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF667EEA),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF667EEA),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInMethodsSection() {
    return SignInMethodsSelector(
      selectedMethods: _selectedSignInMethods,
      onMethodsChanged: (methods) {
        setState(() {
          _selectedSignInMethods = methods;
        });

        // Check if geofence was just enabled
        if (methods.contains('geofence') &&
            !widget.eventModel.signInMethods.contains('geofence')) {
          // Geofence was just enabled, navigate to setup screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            RouterClass.nextScreenNormal(
              context,
              GeofenceSetupScreen(eventModel: widget.eventModel),
            );
          });
        }
      },
      manualCode: _manualCode,
      onManualCodeChanged: (code) {
        setState(() {
          _manualCode = code;
        });
      },
      isEditing: true,
    );
  }

  Widget _buildPrivacySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.security,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Privacy Settings',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: privateEvent,
                onChanged: (value) {
                  setState(() {
                    privateEvent = value ?? false;
                  });
                },
                activeColor: const Color(0xFF667EEA),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Make this event private',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto',
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
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
          onTap: _handleSubmit,
          child: Center(
            child: RoundedLoadingButton(
              controller: _btnCtlr,
              onPressed: () {},
              child: const Text(
                'Update Event',
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
    );
  }

  Widget _buildDeleteButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF5722), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5722).withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showDialog(
            context: context,
            builder: (context) =>
                DeleteEventDialoge(singleEvent: widget.eventModel),
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_forever, color: Color(0xFFFF5722), size: 20),
                SizedBox(width: 8),
                Text(
                  'Delete Event',
                  style: TextStyle(
                    color: Color(0xFFFF5722),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _selectedImagePath != null
              ? Image.file(
                  File(_selectedImagePath!),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 48,
                      ),
                    );
                  },
                )
              : Image.network(
                  _currentImageUrl!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 48,
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: Color(0xFF667EEA),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Upload Event Image',
              style: TextStyle(
                color: const Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to select an image from your gallery',
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.7),
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
