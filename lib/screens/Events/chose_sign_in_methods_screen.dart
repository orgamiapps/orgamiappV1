import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:attendus/screens/Events/add_questions_prompt_screen.dart';
import 'package:attendus/screens/Events/Widget/sign_in_security_tier_selector.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

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
  // New security tier system
  String _selectedSignInTier = 'regular'; // 'most_secure', 'regular', or 'all'

  // Legacy method list for backward compatibility
  List<String> _selectedSignInMethods = ['qr_code', 'manual_code'];
  String? _manualCode;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Scroll controller for header visibility
  final ScrollController _scrollController = ScrollController();
  bool _showHeader = true;
  double _lastScrollOffset = 0;

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

    // Listen to scroll events to hide/show header
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final currentOffset = _scrollController.offset;
    final delta = currentOffset - _lastScrollOffset;

    // Hide header when scrolling down, show when scrolling up
    if (delta > 5 && _showHeader) {
      setState(() {
        _showHeader = false;
      });
    } else if (delta < -5 && !_showHeader) {
      setState(() {
        _showHeader = true;
      });
    }

    // Also show header when at the top
    if (currentOffset <= 0 && !_showHeader) {
      setState(() {
        _showHeader = true;
      });
    }

    _lastScrollOffset = currentOffset;
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Subtitle
            Text(
              'Choose how attendees can sign in to your event',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontFamily: 'Roboto',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            // New Sign-In Security Tier Selector
            SignInSecurityTierSelector(
              selectedTier: _selectedSignInTier,
              onTierChanged: (tier) {
                setState(() {
                  _selectedSignInTier = tier;

                  // Update legacy methods list based on tier
                  switch (tier) {
                    case 'most_secure':
                      _selectedSignInMethods = [
                        'geofence',
                        'facial_recognition',
                      ];
                      break;
                    case 'regular':
                      _selectedSignInMethods = ['qr_code', 'manual_code'];
                      break;
                    case 'all':
                      _selectedSignInMethods = [
                        'geofence',
                        'facial_recognition',
                        'qr_code',
                        'manual_code',
                      ];
                      break;
                  }
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
        color: const Color(0xFF667EEA).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.2),
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
            'You can now proceed to add questions and then fill out your event details, including picking the event\'s location.',
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
            // Proceed directly to questions prompt. Location will be picked on Event Details.
            // Pass the security tier info to the next screen
            RouterClass.nextScreenNormal(
              context,
              AddQuestionsPromptScreen(
                selectedDateTime: widget.selectedDateTime,
                eventDurationHours: widget.eventDurationHours,
                selectedLocation: const LatLng(0, 0), // Placeholder
                radios: 10.0, // Default radius
                selectedSignInMethods: _selectedSignInMethods,
                selectedSignInTier: _selectedSignInTier, // Pass the tier
                manualCode: _manualCode,
                preselectedOrganizationId: widget.preselectedOrganizationId,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Column(
          children: [
            // Modern header with animation for hide/show
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showHeader ? null : 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showHeader ? 1.0 : 0.0,
                child: AppAppBarView.modernHeader(
                  context: context,
                  title: 'Create Event',
                  subtitle: 'Step 1 of 3',
                ),
              ),
            ),
            // Content
            Expanded(child: _contentView()),
            // Continue Button (Fixed at bottom)
            Container(
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
              child: _buildContinueButton(),
            ),
          ],
        ),
      ),
    );
  }
}
