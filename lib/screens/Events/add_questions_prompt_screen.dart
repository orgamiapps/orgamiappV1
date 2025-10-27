import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/add_questions_to_event_screen.dart';
import 'package:attendus/screens/Events/create_event_screen.dart';
import 'package:attendus/Utils/router.dart';

class AddQuestionsPromptScreen extends StatefulWidget {
  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final LatLng selectedLocation;
  final double radios;
  final List<String> selectedSignInMethods;
  final String? selectedSignInTier; // New: security tier ('most_secure', 'regular', 'all')
  final String? manualCode;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;

  const AddQuestionsPromptScreen({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    required this.selectedLocation,
    required this.radios,
    required this.selectedSignInMethods,
    this.selectedSignInTier = 'regular', // Default to regular
    this.manualCode,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
  });

  @override
  State<AddQuestionsPromptScreen> createState() =>
      _AddQuestionsPromptScreenState();
}

class _AddQuestionsPromptScreenState extends State<AddQuestionsPromptScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
                  'Sign-In Prompts',
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
          const SizedBox(height: 20),
          // Subtitle
          const Text(
            'Would you like to collect information from attendees when they sign in?',
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
            // Question Options
            _buildQuestionOptions(),
            const SizedBox(height: 24),
            // Info Card
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionOptions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            spreadRadius: 0,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.question_answer_outlined,
                  color: Color(0xFF667EEA),
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Choose Your Option',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Yes Option
          _buildOptionCard(
            title: 'Yes, add prompts',
            subtitle:
                'Collect valuable information from attendees during sign-in',
            icon: Icons.question_answer_outlined,
            color: const Color(0xFF10B981),
            onTap: () {
              // Navigate directly to add questions screen
              RouterClass.nextScreenNormal(
                context,
                AddQuestionsToEventScreen(
                  eventModel: EventModel(
                    id: '', // Temporary ID for questions screen
                    groupName: '',
                    title: '',
                    description: '',
                    location: '',
                    customerUid: '',
                    imageUrl: '',
                    selectedDateTime: widget.selectedDateTime ?? DateTime.now(),
                    eventGenerateTime: DateTime.now(),
                    status: '',
                    getLocation: widget.selectedSignInMethods.contains('geofence') ||
                        widget.selectedSignInTier == 'most_secure' ||
                        widget.selectedSignInTier == 'all',
                    radius: widget.radios,
                    longitude: widget.selectedLocation.longitude,
                    latitude: widget.selectedLocation.latitude,
                    private: false,
                    categories: [],
                    eventDuration: widget.eventDurationHours ?? 1,
                    signInMethods: widget.selectedSignInMethods,
                    signInSecurityTier: widget.selectedSignInTier,
                    manualCode: widget.manualCode,
                  ),
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  eventCreationData: {
                    'selectedDateTime': widget.selectedDateTime,
                    'eventDurationHours': widget.eventDurationHours,
                    'selectedLocation': widget.selectedLocation,
                    'radios': widget.radios,
                    'selectedSignInMethods': widget.selectedSignInMethods,
                    'selectedSignInTier': widget.selectedSignInTier,
                    'manualCode': widget.manualCode,
                    'preselectedOrganizationId':
                        widget.preselectedOrganizationId,
                    'forceOrganizationEvent': widget.forceOrganizationEvent,
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // No Option
          _buildOptionCard(
            title: 'No, skip for now',
            subtitle: 'I\'ll add prompts later if needed',
            icon: Icons.skip_next_outlined,
            color: const Color(0xFF6B7280),
            onTap: () {
              // Navigate directly to event creation
              RouterClass.nextScreenNormal(
                context,
                CreateEventScreen(
                  selectedDateTime: widget.selectedDateTime,
                  eventDurationHours: widget.eventDurationHours,
                  selectedLocation: widget.selectedLocation,
                  radios: widget.radios,
                  selectedSignInMethods: widget.selectedSignInMethods,
                  selectedSignInTier: widget.selectedSignInTier,
                  manualCode: widget.manualCode,
                  preselectedOrganizationId: widget.preselectedOrganizationId,
                  forceOrganizationEvent: widget.forceOrganizationEvent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontFamily: 'Roboto',
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.arrow_forward_ios, color: color, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.15),
          width: 1,
        ),
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
                  Icons.info_outline,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Why add sign-in prompts?',
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
            'Sign-in prompts help you collect valuable information from attendees, such as dietary preferences, special requirements, feedback, or contact preferences. You can always add or modify prompts later.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(opacity: _fadeAnimation, child: _bodyView()),
      ),
    );
  }
}
