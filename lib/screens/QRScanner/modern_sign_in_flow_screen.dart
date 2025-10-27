import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/QRScanner/ans_questions_to_sign_in_event_screen.dart';
import 'package:attendus/screens/QRScanner/modern_qr_scanner_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/Services/geofence_event_detector.dart';
import 'package:attendus/Utils/location_helper.dart';
import 'package:attendus/screens/FaceRecognition/face_recognition_scanner_screen.dart';
import 'package:attendus/Services/face_recognition_service.dart';
import 'package:attendus/screens/FaceRecognition/face_enrollment_screen.dart';
import 'package:attendus/Services/guest_mode_service.dart';

/// Modern, streamlined sign-in flow screen
/// Professional UI/UX following Material Design 3 principles
class ModernSignInFlowScreen extends StatefulWidget {
  const ModernSignInFlowScreen({super.key});

  @override
  State<ModernSignInFlowScreen> createState() => _ModernSignInFlowScreenState();
}

class _ModernSignInFlowScreenState extends State<ModernSignInFlowScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isAnonymousSignIn = false;
  bool _isLoading = false;
  bool _isLocationCheckLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildModernHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildWelcomeSection(),
                        const SizedBox(height: 32),
                        _buildSignInMethods(),
                        const SizedBox(height: 32),
                        _buildQuickTips(),
                      ],
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

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const Expanded(
            child: Column(
              children: [
                Text(
                  'Event Sign-In',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Roboto',
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Quick & Secure',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667EEA),
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 40), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final isLoggedIn = CustomerController.logeInCustomer != null;
    final isGuestMode = GuestModeService().isGuestMode;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isGuestMode
              ? const [Color(0xFF10B981), Color(0xFF059669)]
              : const [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isGuestMode
                    ? const Color(0xFF10B981)
                    : const Color(0xFF667EEA))
                .withValues(alpha: 0.3),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGuestMode ? Icons.explore_outlined : Icons.qr_code_scanner,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sign In to Event',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Roboto',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isLoggedIn
                ? 'Welcome back, ${CustomerController.logeInCustomer!.name}!'
                : isGuestMode
                    ? 'Enter your name for each sign-in'
                    : 'Choose your sign-in method below',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.9),
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          if (isLoggedIn) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Signed In',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isGuestMode && !isLoggedIn) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Guest Mode',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignInMethods() {
    final isGuestMode = GuestModeService().isGuestMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Sign-In Method',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
            fontFamily: 'Roboto',
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select how you\'d like to check in',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 20),
        // Location + facial recognition available to all (guests need to input name)
        _buildMethodCard(
          icon: Icons.location_on,
          iconColor: const Color(0xFF10B981),
          title: 'Location & Facial Recognition',
          subtitle: isGuestMode
              ? 'Secure verification (name required)'
              : 'Automatic detection & biometric',
          badge: 'MOST SECURE',
          badgeColor: const Color(0xFF10B981),
          isLoading: _isLocationCheckLoading,
          onTap: _handleLocationFacialSignIn,
        ),
        const SizedBox(height: 16),
        _buildMethodCard(
          icon: Icons.qr_code_scanner,
          iconColor: const Color(0xFF667EEA),
          title: 'Scan QR Code',
          subtitle: 'Quick camera scan',
          badge: 'FASTEST',
          badgeColor: const Color(0xFF667EEA),
          onTap: () async {
            final result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (context) => const ModernQRScannerScreen(),
              ),
            );

            if (result != null && mounted) {
              _codeController.text = result;
              _handleSignIn();
            }
          },
        ),
        const SizedBox(height: 16),
        _buildMethodCard(
          icon: Icons.keyboard_alt,
          iconColor: const Color(0xFF764BA2),
          title: 'Enter Code',
          subtitle: 'Type event code manually',
          onTap: () {
            _showManualCodeDialog();
          },
        ),
      ],
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    bool isLoading = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [iconColor, iconColor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.3),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            fontFamily: 'Roboto',
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor!.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.grey[400]!,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: Colors.grey[400],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickTips() {
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Quick Tips',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            icon: Icons.qr_code_2,
            text:
                'QR codes are displayed at the event entrance or by the organizer',
          ),
          const SizedBox(height: 12),
          _buildTipItem(
            icon: Icons.vpn_key,
            text:
                'Event codes are shared by organizers via email, text, or announcement',
          ),
          const SizedBox(height: 12),
          _buildTipItem(
            icon: Icons.verified_user,
            text:
                'Some events may require facial recognition or location verification',
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667EEA)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
              fontFamily: 'Roboto',
            ),
          ),
        ),
      ],
    );
  }

  void _showManualCodeDialog() {
    final isLoggedIn = CustomerController.logeInCustomer != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    const Text(
                      'Enter Event Code',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                        fontFamily: 'Roboto',
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type the code provided by the event organizer',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Event Code Input
                    _buildModernTextField(
                      controller: _codeController,
                      label: 'Event Code',
                      hint: 'e.g., ABC123 or EVENT-ID',
                      icon: Icons.qr_code,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter the event code';
                        }
                        return null;
                      },
                    ),

                    // Name Input (if not logged in)
                    if (!isLoggedIn) ...[
                      const SizedBox(height: 16),
                      _buildModernTextField(
                        controller: _nameController,
                        label: 'Your Name',
                        hint: 'Enter your full name',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (!_isAnonymousSignIn &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Anonymous Toggle
                      _buildAnonymousCheckbox(),
                    ],

                    const SizedBox(height: 24),

                    // Sign In Button
                    _buildSignInButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF1A1A1A),
            fontFamily: 'Roboto',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontFamily: 'Roboto'),
            prefixIcon: Icon(icon, color: const Color(0xFF667EEA), size: 22),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnonymousCheckbox() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _isAnonymousSignIn = !_isAnonymousSignIn;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isAnonymousSignIn
                ? const Color(0xFF667EEA).withValues(alpha: 0.05)
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isAnonymousSignIn
                  ? const Color(0xFF667EEA).withValues(alpha: 0.3)
                  : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _isAnonymousSignIn
                      ? const Color(0xFF667EEA)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isAnonymousSignIn
                        ? const Color(0xFF667EEA)
                        : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: _isAnonymousSignIn
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign in anonymously',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your name will be hidden from public view',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () {
                if (_formKey.currentState?.validate() ?? false) {
                  Navigator.pop(context); // Close the modal
                  _handleSignIn();
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF667EEA),
          disabledBackgroundColor: Colors.grey[300],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Sign In to Event',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleSignIn() async {
    if (_codeController.text.isEmpty) {
      ShowToast().showNormalToast(msg: 'Please enter an event code!');
      return;
    }

    if (CustomerController.logeInCustomer == null &&
        _nameController.text.isEmpty &&
        !_isAnonymousSignIn) {
      ShowToast().showNormalToast(msg: 'Please enter your name!');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String docId;
      if (CustomerController.logeInCustomer != null) {
        docId =
            '${_codeController.text}-${CustomerController.logeInCustomer!.uid}';
      } else {
        docId = FirebaseFirestore.instance
            .collection(AttendanceModel.firebaseKey)
            .doc()
            .id;
      }

      AttendanceModel newAttendanceModel = AttendanceModel(
        id: docId,
        eventId: _codeController.text,
        userName: _isAnonymousSignIn
            ? 'Anonymous'
            : (CustomerController.logeInCustomer?.name ?? _nameController.text),
        customerUid: CustomerController.logeInCustomer?.uid ?? 'without_login',
        attendanceDateTime: DateTime.now(),
        answers: [],
        isAnonymous: _isAnonymousSignIn,
        signInMethod: 'qr_code', // or 'manual_code'
        realName: _isAnonymousSignIn
            ? (CustomerController.logeInCustomer?.name ?? _nameController.text)
            : null,
      );

      final eventExist = await FirebaseFirestoreHelper().getSingleEvent(
        newAttendanceModel.eventId,
      );

      if (eventExist != null) {
        // Check for sign-in prompts
        final questions = await FirebaseFirestoreHelper().getEventQuestions(
          eventId: eventExist.id,
        );

        if (questions.isNotEmpty) {
          _codeController.text = '';
          if (!mounted) return;
          RouterClass.nextScreenAndReplacement(
            context,
            AnsQuestionsToSignInEventScreen(
              eventModel: eventExist,
              newAttendance: newAttendanceModel,
              nextPageRoute: 'qrScannerFlow',
            ),
          );
        } else {
          // No prompts, sign in directly
          await FirebaseFirestore.instance
              .collection(AttendanceModel.firebaseKey)
              .doc(newAttendanceModel.id)
              .set(newAttendanceModel.toJson());

          ShowToast().showNormalToast(msg: 'Signed In Successfully!');

          // Navigate to event details after a short delay
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;
          RouterClass.nextScreenAndReplacement(
            context,
            SingleEventScreen(eventModel: eventExist),
          );
        }
      } else {
        ShowToast().showNormalToast(
          msg: 'Event not found. Please check the code and try again.',
        );
      }
    } catch (e) {
      debugPrint('Error signing in: $e');
      ShowToast().showNormalToast(msg: 'Failed to sign in. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Handle Location and Facial Recognition Sign-In
  /// This is the most secure method combining geofence and biometric verification
  Future<void> _handleLocationFacialSignIn() async {
    // Prevent multiple simultaneous requests
    if (_isLocationCheckLoading) return;

    setState(() => _isLocationCheckLoading = true);

    try {
      // Step 1: Get user location
      ShowToast().showNormalToast(msg: 'Checking your location...');

      final position = await LocationHelper.getCurrentLocation(
        showErrorDialog: true,
        context: context,
      );

      if (position == null) {
        ShowToast().showNormalToast(
          msg: 'Unable to get your location. Please enable location services.',
        );
        setState(() => _isLocationCheckLoading = false);
        return;
      }

      // Step 2: Find events with active geofence that user is within
      final geofenceDetector = GeofenceEventDetector();
      final nearbyEvents = await geofenceDetector.findNearbyGeofencedEvents(
        userPosition: position,
      );

      if (nearbyEvents.isEmpty) {
        if (!mounted) return;
        setState(() => _isLocationCheckLoading = false);

        // Show helpful dialog
        _showNoEventsFoundDialog();
        return;
      }

      // Step 3: If multiple events found, let user choose
      EventWithDistance selectedEvent;
      if (nearbyEvents.length > 1) {
        final selected = await _showEventSelectionDialog(nearbyEvents);
        if (selected == null) {
          setState(() => _isLocationCheckLoading = false);
          return;
        }
        selectedEvent = selected;
      } else {
        selectedEvent = nearbyEvents.first;
      }

      // Step 4: Location verified, now proceed to facial recognition
      if (!mounted) return;
      setState(() => _isLocationCheckLoading = false);

      ShowToast().showNormalToast(
        msg:
            'Location verified at ${selectedEvent.event.title}! Preparing facial recognition...',
      );

      await Future.delayed(const Duration(milliseconds: 800));

      // Step 5: Launch facial recognition
      await _handleFacialRecognitionForEvent(selectedEvent.event);
    } catch (e) {
      if (mounted) {
        setState(() => _isLocationCheckLoading = false);
        ShowToast().showNormalToast(
          msg: 'Error during location check: ${e.toString()}',
        );
      }
    }
  }

  /// Show dialog when no nearby events are found
  void _showNoEventsFoundDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_off,
                color: Color(0xFFFF6B6B),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'No Events Nearby',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We couldn\'t find any events with active geofence at your current location.',
              style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'Roboto'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF667EEA),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Possible reasons:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoItem('You\'re not at an event venue yet'),
                  _buildInfoItem('The event hasn\'t started'),
                  _buildInfoItem('Geofence is not enabled for this event'),
                  _buildInfoItem(
                    'You\'re outside the event\'s check-in radius',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Trigger a retry
              _handleLocationFacialSignIn();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Try Again',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: Colors.grey[700], fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show event selection dialog when multiple events are found
  Future<EventWithDistance?> _showEventSelectionDialog(
    List<EventWithDistance> events,
  ) async {
    return showDialog<EventWithDistance>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.event_available,
                color: Color(0xFF10B981),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Multiple Events Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You\'re near multiple events. Select which one you want to sign in to:',
                style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
              ),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final eventWithDistance = events[index];
                  final event = eventWithDistance.event;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(context, eventWithDistance),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF667EEA,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF667EEA),
                                      Color(0xFF764BA2),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.event,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Roboto',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          eventWithDistance.formattedDistance,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[600],
                                            fontFamily: 'Roboto',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            eventWithDistance.timeUntilEvent,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                              fontFamily: 'Roboto',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Handle facial recognition for a specific event
  Future<void> _handleFacialRecognitionForEvent(EventModel event) async {
    try {
      final isGuestMode = GuestModeService().isGuestMode;

      // For guests, show name input dialog before proceeding
      if (isGuestMode) {
        final guestName = await _showGuestNameInputDialog();
        if (guestName == null || guestName.trim().isEmpty) {
          ShowToast().showNormalToast(
            msg: 'Name is required for guest sign-in',
          );
          return;
        }

        // Show facial recognition enrollment/scan for guest
        _showGuestFacialRecognitionDialog(event, guestName);
        return;
      }

      // Check if user is logged in (for non-guest users)
      if (CustomerController.logeInCustomer == null) {
        ShowToast().showNormalToast(
          msg: 'Please log in to use facial recognition.',
        );
        return;
      }

      // Check if user is enrolled for facial recognition for this event
      final faceService = FaceRecognitionService();
      final isEnrolled = await faceService.isUserEnrolled(
        userId: CustomerController.logeInCustomer!.uid,
        eventId: event.id,
      );

      if (!mounted) return;

      if (isEnrolled) {
        // Navigate to face recognition scanner
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                FaceRecognitionScannerScreen(eventModel: event),
          ),
        );

        if (result == true && mounted) {
          // Successful sign-in
          ShowToast().showNormalToast(
            msg: 'Successfully signed in to ${event.title}!',
          );

          // Navigate to event details after a short delay
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;

          RouterClass.nextScreenAndReplacement(
            context,
            SingleEventScreen(eventModel: event),
          );
        }
      } else {
        // Show enrollment dialog
        _showFaceEnrollmentDialogForEvent(event);
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Error during facial recognition: ${e.toString()}',
      );
    }
  }

  /// Show face enrollment dialog for a specific event
  void _showFaceEnrollmentDialogForEvent(EventModel event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.face, color: Color(0xFF10B981), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Face Recognition Setup',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.face_retouching_natural,
              size: 64,
              color: Color(0xFF10B981),
            ),
            const SizedBox(height: 16),
            Text(
              'To use facial recognition sign-in for ${event.title}, you need to enroll your face first.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.security,
                    color: Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a one-time setup. Your face data is encrypted and stored securely.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToFaceEnrollment(event);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Enroll Now',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to face enrollment screen
  void _navigateToFaceEnrollment(EventModel event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceEnrollmentScreen(eventModel: event),
      ),
    );
  }

  /// Show name input dialog for guest users
  Future<String?> _showGuestNameInputDialog() async {
    final TextEditingController guestNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.person_outline,
                color: Color(0xFF10B981),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enter Your Name',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please provide your name for event sign-in verification.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: guestNameController,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
                decoration: InputDecoration(
                  hintText: 'e.g., John Smith',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontFamily: 'Roboto',
                  ),
                  prefixIcon: const Icon(
                    Icons.person,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF10B981),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, guestNameController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show guest facial recognition dialog with enrollment option
  void _showGuestFacialRecognitionDialog(EventModel event, String guestName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.face_retouching_natural,
                color: Color(0xFF10B981),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Facial Recognition',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.face,
              size: 64,
              color: Color(0xFF10B981),
            ),
            const SizedBox(height: 16),
            Text(
              'Hi $guestName!',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete facial recognition to sign in to ${event.title}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.security,
                        color: Color(0xFF667EEA),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your face data is stored securely and temporarily for this event only.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: Color(0xFF667EEA),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Signed in as: $guestName',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToGuestFaceEnrollment(event, guestName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Start Verification',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to guest face enrollment screen
  void _navigateToGuestFaceEnrollment(EventModel event, String guestName) {
    // For guests, we'll use a special guest ID based on timestamp
    final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceEnrollmentScreen(
          eventModel: event,
          guestUserId: guestId,
          guestUserName: guestName,
        ),
      ),
    );
  }
}
