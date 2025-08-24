import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/screens/Events/chose_location_in_map_screen.dart';
import 'package:orgami/screens/Events/add_questions_prompt_screen.dart';
import 'package:orgami/screens/Events/Widget/sign_in_methods_selector.dart';
import 'package:orgami/Utils/router.dart';

class ChoseSignInMethodsScreen extends StatefulWidget {
  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;

  const ChoseSignInMethodsScreen({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
  });

  @override
  State<ChoseSignInMethodsScreen> createState() =>
      _ChoseSignInMethodsScreenState();
}

class _ChoseSignInMethodsScreenState extends State<ChoseSignInMethodsScreen>
    with TickerProviderStateMixin {
  // Default to all three methods selected
  List<String> _selectedSignInMethods = ['geofence', 'qr_code', 'manual_code'];
  String? _manualCode;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize slide animation
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
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
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
                  'Sign-In Methods',
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
            'Choose how attendees can sign in to your event',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sign-In Methods Selector
            SignInMethodsSelector(
              selectedMethods: _selectedSignInMethods,
              onMethodsChanged: (methods) {
                setState(() {
                  _selectedSignInMethods = methods;
                });
              },
              manualCode: _manualCode,
              onManualCodeChanged: (code) {
                setState(() {
                  _manualCode = code;
                });
              },
            ),
            const SizedBox(height: 24),
            // Info Card
            _buildInfoCard(),
            const SizedBox(height: 100), // Space for button
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: const Color(0xFF667EEA),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'What happens next?',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _selectedSignInMethods.contains('geofence')
                ? 'Since you selected geofence tracking, you\'ll need to choose a location and set the distance for automatic sign-in.'
                : 'You can now proceed to add questions and fill out your event details.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
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
          onTap: () {
            if (_selectedSignInMethods.contains('geofence')) {
              // If geofence is selected, go to location selection
              RouterClass.nextScreenNormal(
                context,
                ChoseLocationInMapScreen(
                  selectedDateTime: widget.selectedDateTime,
                  eventDurationHours: widget.eventDurationHours,
                  selectedSignInMethods: _selectedSignInMethods,
                  manualCode: _manualCode,
                  preselectedOrganizationId: widget.preselectedOrganizationId,
                  forceOrganizationEvent: widget.forceOrganizationEvent,
                ),
              );
            } else {
              // If no geofence, go to questions prompt with default location
              RouterClass.nextScreenNormal(
                context,
                AddQuestionsPromptScreen(
                  selectedDateTime: widget.selectedDateTime,
                  eventDurationHours: widget.eventDurationHours,
                  selectedLocation: const LatLng(0, 0), // Default location
                  radios: 10.0, // Default radius
                  selectedSignInMethods: _selectedSignInMethods,
                  manualCode: _manualCode,
                  preselectedOrganizationId: widget.preselectedOrganizationId,
                  forceOrganizationEvent: widget.forceOrganizationEvent,
                ),
              );
            }
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
                child: _buildContinueButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
