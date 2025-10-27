import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/screens/QRScanner/ans_questions_to_sign_in_event_screen.dart';
import 'package:attendus/screens/QRScanner/modern_qr_scanner_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';

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
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
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
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
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
            child: const Icon(
              Icons.qr_code_scanner,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Check In to Event',
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
        ],
      ),
    );
  }

  Widget _buildSignInMethods() {
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
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.5,
            ),
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
                    colors: [
                      iconColor,
                      iconColor.withValues(alpha: 0.7),
                    ],
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
              Icon(
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
            text: 'QR codes are displayed at the event entrance or by the organizer',
          ),
          const SizedBox(height: 12),
          _buildTipItem(
            icon: Icons.vpn_key,
            text: 'Event codes are shared by organizers via email, text, or announcement',
          ),
          const SizedBox(height: 12),
          _buildTipItem(
            icon: Icons.verified_user,
            text: 'Some events may require facial recognition or location verification',
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF667EEA),
        ),
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
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
            hintStyle: TextStyle(
              color: Colors.grey[400],
              fontFamily: 'Roboto',
            ),
            prefixIcon: Icon(icon, color: const Color(0xFF667EEA), size: 22),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey[300]!,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF667EEA),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFF6B6B),
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFF6B6B),
                width: 2,
              ),
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
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      )
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
        onPressed: _isLoading ? null : () {
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
        ShowToast().showNormalToast(msg: 'Event not found. Please check the code and try again.');
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
}

