import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/event_question_model.dart';
import 'package:orgami/Screens/Events/single_event_screen.dart';
import 'package:orgami/Screens/Home/dashboard_screen.dart';

import 'package:orgami/Utils/router.dart';

import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

import 'dart:io';

class CreateEventScreen extends StatefulWidget {
  final DateTime selectedDateTime;
  final int eventDurationHours;
  final LatLng selectedLocation;
  final double radios;
  final List<String>? selectedSignInMethods;
  final String? manualCode;
  final List<EventQuestionModel>? questions;

  const CreateEventScreen({
    super.key,
    required this.selectedDateTime,
    required this.eventDurationHours,
    required this.selectedLocation,
    required this.radios,
    this.selectedSignInMethods,
    this.manualCode,
    this.questions,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool successMessage = false;
  final _btnCtlr = RoundedLoadingButtonController();

  bool privateEvent = false;
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];
  final List<String> _selectedCategories = [];

  final TextEditingController groupNameEdtController = TextEditingController();
  final TextEditingController titleEdtController = TextEditingController();
  final TextEditingController locationEdtController = TextEditingController();
  final TextEditingController thumbnailUrlCtlr = TextEditingController();
  final TextEditingController descriptionEdtController =
      TextEditingController();

  String? _selectedImagePath;

  // Sign-in methods
  late List<String> _selectedSignInMethods;
  String? _manualCode;

  // Animation controllers
  late AnimationController _fadeController;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

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

  Future<String?> _uploadToFirebaseHosting() async {
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
      if (_selectedImagePath != null) {
        // Upload local image
        await _uploadToFirebaseHosting().then((String? imgUrl) async {
          if (imgUrl != null) {
            setState(() => thumbnailUrlCtlr.text = imgUrl);
            uploadEvent();
          } else {
            setState(() {
              _selectedImagePath = null;
              thumbnailUrlCtlr.clear();
            });
            _btnCtlr.reset();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to upload image. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      } else {
        // No image selected, proceed without image
        uploadEvent();
      }
    }
  }

  Future uploadEvent() async {
    try {
      await FirebaseFirestoreHelper().getEventID().then((docId) async {
        EventModel newEvent = EventModel(
          id: docId,
          groupName: groupNameEdtController.text,
          title: titleEdtController.text,
          description: descriptionEdtController.text,
          location: locationEdtController.text,
          customerUid: FirebaseAuth.instance.currentUser!.uid,
          imageUrl: thumbnailUrlCtlr.text,
          selectedDateTime: widget.selectedDateTime,
          eventGenerateTime: DateTime.now(),
          status: '',
          getLocation: true,
          radius: widget.radios,
          longitude: widget.selectedLocation.longitude,
          latitude: widget.selectedLocation.latitude,
          private: privateEvent,
          categories: _selectedCategories,
          eventDuration: widget.eventDurationHours,
          signInMethods: _selectedSignInMethods,
          manualCode: _manualCode,
        );

        Map<String, dynamic> data = newEvent.toJson();

        await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(docId)
            .set(data);

        // Save questions if provided
        if (widget.questions != null && widget.questions!.isNotEmpty) {
          for (EventQuestionModel question in widget.questions!) {
            // Generate a new ID for each question
            String questionId = FirebaseFirestore.instance
                .collection(EventQuestionModel.firebaseKey)
                .doc()
                .id;

            EventQuestionModel questionToSave = EventQuestionModel(
              id: questionId,
              questionTitle: question.questionTitle,
              required: question.required,
            );

            await FirebaseFirestore.instance
                .collection(EventModel.firebaseKey)
                .doc(docId)
                .collection(EventQuestionModel.firebaseKey)
                .doc(questionId)
                .set(questionToSave.toJson());
          }
        }

        debugPrint('Event Uploaded!');
        _btnCtlr.success();
        if (!mounted) return;
        RouterClass.nextScreenAndReplacementAndRemoveUntil(
          context: context,
          page: const DashboardScreen(),
        );
        if (!mounted) return;
        RouterClass.nextScreenNormal(
          context,
          SingleEventScreen(eventModel: newEvent),
        );
      });
    } catch (e) {
      debugPrint('Error uploading event: $e');
      _btnCtlr.error();
      // Show error message to user
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create event: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize sign-in methods
    _selectedSignInMethods =
        widget.selectedSignInMethods ?? ['qr_code', 'manual_code'];
    _manualCode = widget.manualCode;

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

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

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
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
                  'Event Details',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Subtitle
          const Text(
            'Let\'s get started by filling out the form below',
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

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date and Time Summary
              _buildSummaryCard(),
              const SizedBox(height: 24),
              // Private Event Toggle
              _buildPrivateEventToggle(),
              const SizedBox(height: 24),
              // Categories Section
              _buildCategoriesSection(),
              const SizedBox(height: 24),
              // Form Fields
              _buildFormFields(),
              const SizedBox(height: 100), // Space for button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          _buildSummaryItem(
            icon: Icons.calendar_month_rounded,
            label: 'Date',
            value: DateFormat(
              'EEEE, MMMM dd, yyyy',
            ).format(widget.selectedDateTime),
          ),
          const SizedBox(height: 16),
          _buildSummaryItem(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: _timeRangeLabel,
          ),
        ],
      ),
    );
  }

  String get _timeRangeLabel {
    final String start = DateFormat('KK:mm a').format(widget.selectedDateTime);
    final DateTime endDt =
        widget.selectedDateTime.add(Duration(hours: widget.eventDurationHours));
    final String end = DateFormat('KK:mm a').format(endDt);
    final String duration = '${widget.eventDurationHours}h';
    return '$start – $end ($duration)';
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF667EEA), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
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
    );
  }

  Widget _buildPrivateEventToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock, color: Color(0xFF667EEA), size: 20),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Private Event',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
          ),
          Switch(
            value: privateEvent,
            onChanged: (value) {
              setState(() {
                privateEvent = value;
              });
            },
            activeColor: const Color(0xFF667EEA),
            activeTrackColor: const Color(0xFF667EEA).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.category,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
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
              return _buildCategoryChip(category, isSelected);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String category, bool isSelected) {
    return FilterChip(
      label: Text(
        category,
        style: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
          fontWeight: FontWeight.w500,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedCategories.add(category);
          } else {
            _selectedCategories.remove(category);
          }
        });
      },
      backgroundColor: Colors.grey.withValues(alpha: 0.1),
      selectedColor: const Color(0xFF667EEA),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFF667EEA)
            : Colors.grey.withValues(alpha: 0.3),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildFormFields() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Event Information',
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
          // Organizer Field
          _buildTextField(
            controller: groupNameEdtController,
            label: 'Organizer',
            hint: 'Type here...',
            icon: Icons.person,
            enableCapitalization: true,
            validator: (value) {
              if (value!.isEmpty) {
                return 'Enter Organizer first!';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Title Field
          _buildTextField(
            controller: titleEdtController,
            label: 'Title',
            hint: 'Type here...',
            icon: Icons.title,
            enableCapitalization: true,
            validator: (value) {
              if (value!.isEmpty) {
                return 'Enter Title first!';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Image Field
          _buildImageField(),
          const SizedBox(height: 16),
          // Location Field
          _buildTextField(
            controller: locationEdtController,
            label: 'Location',
            hint: 'Type here...',
            icon: Icons.location_on,
            validator: (value) {
              if (value!.isEmpty) {
                return 'Enter Location first!';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Description Field
          _buildTextField(
            controller: descriptionEdtController,
            label: 'Description',
            hint: 'Type here...',
            icon: Icons.description,
            maxLines: 4,
            validator: (value) {
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
    bool enableCapitalization = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          textCapitalization: enableCapitalization
              ? TextCapitalization.words
              : TextCapitalization.none,
          inputFormatters: enableCapitalization
              ? [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[a-zA-Z0-9\s\-_.,!?]'),
                  ),
                  LengthLimitingTextInputFormatter(100),
                ]
              : null,
          onChanged: enableCapitalization
              ? (value) {
                  // Ensure proper capitalization for each word
                  if (value.isNotEmpty) {
                    final words = value.split(' ');
                    final capitalizedWords = words
                        .map((word) {
                          if (word.isNotEmpty) {
                            return word[0].toUpperCase() +
                                word.substring(1).toLowerCase();
                          }
                          return word;
                        })
                        .join(' ');

                    // Only update if the formatted text is different to avoid cursor jumping
                    if (capitalizedWords != value) {
                      final cursorPosition = controller.selection.start;
                      controller.value = TextEditingValue(
                        text: capitalizedWords,
                        selection: TextSelection.collapsed(
                          offset: cursorPosition,
                        ),
                      );
                    }
                  }
                }
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.withValues(alpha: 0.6),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Event Image',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _selectedImagePath != null
                  ? const Color(0xFF667EEA)
                  : Colors.grey.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: _selectedImagePath != null
              ? _buildImagePreview()
              : _buildUploadPlaceholder(),
        ),
        if (_selectedImagePath != null) ...[
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
                          'Image selected',
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
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Stack(
          children: [
            _bodyView(),
            // Continue Button (Fixed at bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      spreadRadius: 0,
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: RoundedLoadingButton(
                  animateOnTap: false,
                  borderRadius: 16,
                  width: double.infinity,
                  height: 56,
                  controller: _btnCtlr,
                  onPressed: () => _handleSubmit(),
                  color: const Color(0xFF667EEA),
                  elevation: 0,
                  child: const Text(
                    'Add New Event',
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
          ],
        ),
      ),
    );
  }
}
