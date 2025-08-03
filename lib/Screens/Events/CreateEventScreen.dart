import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Screens/Home/DashboardScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/TextFields.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class CreateEventScreen extends StatefulWidget {
  final DateTime selectedDateTime;
  final LatLng selectedLocation;
  final double radios;

  const CreateEventScreen({
    super.key,
    required this.selectedDateTime,
    required this.selectedLocation,
    required this.radios,
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
  List<String> _selectedCategories = [];

  final TextEditingController groupNameEdtController = TextEditingController();
  final TextEditingController titleEdtController = TextEditingController();
  final TextEditingController locationEdtController = TextEditingController();
  final TextEditingController thumbnailUrlCtlr = TextEditingController();
  final TextEditingController descriptionEdtController =
      TextEditingController();

  String? _selectedImagePath;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  Future _pickImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxHeight: 600,
      maxWidth: 1000,
    );
    if (image != null) {
      setState(() {
        _selectedImagePath = image.path;
        thumbnailUrlCtlr.text = image.path;
      });
    }
  }

  Future<String?> _uploadToFirebaseHosting() async {
    //return download link
    String? imageUrl;
    Uint8List imageData = await XFile(_selectedImagePath!).readAsBytes();
    final Reference storageReference = FirebaseStorage.instance.ref().child(
      'events_images/${_selectedImagePath.hashCode}.png',
    );
    final SettableMetadata metadata = SettableMetadata(
      contentType: 'image/png',
    );
    final UploadTask uploadTask = storageReference.putData(imageData, metadata);
    await uploadTask.whenComplete(() async {
      imageUrl = await storageReference.getDownloadURL();
    });
    return imageUrl;
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      _btnCtlr.start();
      if (_selectedImagePath != null) {
        //local image
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
          }
        });
      } else {
        //network image
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
        );

        Map<String, dynamic> data = newEvent.toJson();

        await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(docId)
            .set(data);

        debugPrint('Event Uploaded!');
        _btnCtlr.success();
        RouterClass.nextScreenAndReplacementAndRemoveUntil(
          context: context,
          page: const DashboardScreen(),
        );
        RouterClass.nextScreenNormal(
          context,
          SingleEventScreen(eventModel: newEvent),
          // AddQuestionsToEventScreen(eventModel: newEvent),
        );
      });
    } catch (e) {
      debugPrint('Error uploading event: $e');
      _btnCtlr.error();
      // Show error message to user
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
            color: Colors.black.withOpacity(0.08),
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
            value: DateFormat('KK:mm a').format(widget.selectedDateTime),
          ),
        ],
      ),
    );
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
            color: const Color(0xFF667EEA).withOpacity(0.1),
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
            color: Colors.black.withOpacity(0.08),
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
              color: const Color(0xFF667EEA).withOpacity(0.1),
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
            activeTrackColor: const Color(0xFF667EEA).withOpacity(0.3),
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
      backgroundColor: Colors.grey.withOpacity(0.1),
      selectedColor: const Color(0xFF667EEA),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFF667EEA)
            : Colors.grey.withOpacity(0.3),
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
              color: Colors.grey.withOpacity(0.6),
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
          'Image',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: thumbnailUrlCtlr,
                decoration: InputDecoration(
                  hintText: 'Enter Image URL or Select Image',
                  hintStyle: TextStyle(
                    color: Colors.grey.withOpacity(0.6),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF667EEA),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                validator: (value) {
                  if (value!.isEmpty) return 'Value is empty';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickImage,
                  child: const Icon(
                    Icons.image,
                    color: Color(0xFF667EEA),
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
                      color: Colors.black.withOpacity(0.1),
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
