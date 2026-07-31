import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:attendus/screens/Events/add_questions_prompt_screen.dart';
import 'package:attendus/screens/Events/Widget/sign_in_security_tier_selector.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

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
  String _selectedSignInTier =
      ''; // no default selected; 'most_secure', 'geofence_only', 'regular', or 'all'

  // Legacy method list for backward compatibility
  List<String> _selectedSignInMethods = [];
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
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: AttendUsPageSection(
              title: 'Access & sign-in security',
              subtitle:
                  'Choose how attendees verify attendance. You can still adjust these settings later.',
              icon: Icons.verified_user_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SignInSecurityTierSelector(
                    selectedTier: _selectedSignInTier,
                    onTierChanged: (tier) {
                      setState(() {
                        _selectedSignInTier = tier;

                        switch (tier) {
                          case 'most_secure':
                            _selectedSignInMethods = [
                              'geofence',
                              'facial_recognition',
                            ];
                            break;
                          case 'geofence_only':
                            _selectedSignInMethods = ['geofence'];
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
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return AttendUsActionTile(
      icon: Icons.info_outline,
      title: 'What happens next?',
      subtitle:
          'Add optional sign-in prompts, then complete event basics, schedule, location, and review.',
      tone: AttendUsStatusTone.info,
    );
  }

  void _continueToQuestions() {
    RouterClass.nextScreenNormal(
      context,
      AddQuestionsPromptScreen(
        selectedDateTime: widget.selectedDateTime,
        eventDurationHours: widget.eventDurationHours,
        selectedLocation: const LatLng(0, 0),
        radios: 10.0,
        selectedSignInMethods: _selectedSignInMethods,
        selectedSignInTier: _selectedSignInTier.isEmpty
            ? null
            : _selectedSignInTier,
        manualCode: _manualCode,
        preselectedOrganizationId: widget.preselectedOrganizationId,
        forceOrganizationEvent: widget.forceOrganizationEvent,
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: AttendUsButton.primary(
        label: 'Continue',
        icon: Icons.arrow_forward,
        onPressed: _continueToQuestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showHeader ? null : 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showHeader ? 1.0 : 0.0,
                child: AttendUsTopBar(
                  title: 'Create event',
                  subtitle: 'Step 1: access and sign-in security',
                  actions: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _contentView()),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: _buildContinueButton(),
            ),
          ],
        ),
      ),
    );
  }
}
