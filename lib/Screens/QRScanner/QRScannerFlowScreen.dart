import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Permissions/PermssionsHelper.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Screens/QRScanner/ModernQRScannerScreen.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';


class QRScannerFlowScreen extends StatefulWidget {
  const QRScannerFlowScreen({super.key});

  @override
  State<QRScannerFlowScreen> createState() => _QRScannerFlowScreenState();
}

class _QRScannerFlowScreenState extends State<QRScannerFlowScreen> {
  int _currentStep = 0;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isAnonymousSignIn = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.pureBlackColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildStepContent()),
            _buildStepIndicator(),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_ios,
                color: AppThemeColor.pureWhiteColor,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Event Sign In',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor,
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(width: 40),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildMethodSelectionStep();
      case 2:
        return _buildManualEntryStep();
      default:
        return _buildWelcomeStep();
    }
  }

  Widget _buildWelcomeStep() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: AppThemeColor.buttonGradient,
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: AppThemeColor.darkBlueColor.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.qr_code_scanner,
              size: 60,
              color: AppThemeColor.pureWhiteColor,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Welcome to Event Sign In',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor,
              fontSize: Dimensions.fontSizeOverLarge,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'Choose how you\'d like to sign in to your event',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor.withOpacity(0.8),
              fontSize: Dimensions.fontSizeDefault,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          if (CustomerController.logeInCustomer != null) ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppThemeColor.pureWhiteColor.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppThemeColor.darkBlueColor,
                    child: Text(
                      CustomerController.logeInCustomer!.name.isNotEmpty
                          ? CustomerController.logeInCustomer!.name[0]
                                .toUpperCase()
                          : 'U',
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Signed in as',
                          style: TextStyle(
                            color: AppThemeColor.pureWhiteColor.withOpacity(
                              0.7,
                            ),
                            fontSize: Dimensions.fontSizeSmall,
                          ),
                        ),
                        Text(
                          CustomerController.logeInCustomer!.name,
                          style: TextStyle(
                            color: AppThemeColor.pureWhiteColor,
                            fontSize: Dimensions.fontSizeDefault,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _buildMethodSelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          // Header
          Container(
            margin: const EdgeInsets.only(bottom: 30),
            child: Column(
              children: [
                Text(
                  'Choose Sign In Method',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor,
                    fontSize: Dimensions.fontSizeOverLarge,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                Text(
                  'Select how you would like to sign in to your event',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor.withOpacity(0.8),
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Method selection cards
          Container(
            margin: const EdgeInsets.symmetric(vertical: 15),
            child: Column(
              children: [
                _buildMethodCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan QR Code',
                  subtitle: 'Use camera to scan event QR code',
                  description:
                      'Point your camera at the event QR code to automatically sign in',
                  onTap: () async {
                    // Navigate to QR scanner
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ModernQRScannerScreen(),
                      ),
                    );

                    // Handle return from QR scanner
                    if (result != null && result is String) {
                      _codeController.text = result;
                      _nextStep(); // Go to manual entry step
                    }
                  },
                ),
                const SizedBox(height: 20),
                _buildMethodCard(
                  icon: Icons.keyboard,
                  title: 'Enter Code Manually',
                  subtitle: 'Type the event code directly',
                  description: 'Enter the event code manually if you have it',
                  onTap: _nextStep,
                ),
              ],
            ),
          ),

          // Instructions
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppThemeColor.darkBlueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: AppThemeColor.darkBlueColor.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppThemeColor.darkBlueColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Instructions',
                      style: TextStyle(
                        color: AppThemeColor.darkBlueColor,
                        fontSize: Dimensions.fontSizeDefault,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildInstructionItem(
                  icon: Icons.qr_code_scanner,
                  text: 'QR Code: Ask the event organizer for the QR code',
                ),
                const SizedBox(height: 8),
                _buildInstructionItem(
                  icon: Icons.keyboard,
                  text:
                      'Manual Entry: Enter the event code provided by the organizer',
                ),
                const SizedBox(height: 8),
                _buildInstructionItem(
                  icon: Icons.phone_android,
                  text: 'Use your phone camera to scan QR codes',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppThemeColor.pureWhiteColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppThemeColor.pureWhiteColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppThemeColor.darkBlueColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: AppThemeColor.pureWhiteColor, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor,
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor.withOpacity(0.7),
                      fontSize: Dimensions.fontSizeDefault,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor.withOpacity(0.6),
                        fontSize: Dimensions.fontSizeSmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: AppThemeColor.pureWhiteColor.withOpacity(0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntryStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Text(
            'Enter Event Code',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor,
              fontSize: Dimensions.fontSizeExtraLarge,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          _buildTextField(
            controller: _codeController,
            hintText: 'Enter event code',
            icon: Icons.qr_code,
          ),
          const SizedBox(height: 20),
          if (CustomerController.logeInCustomer == null) ...[
            _buildTextField(
              controller: _nameController,
              hintText: 'Enter your name',
              icon: Icons.person,
            ),
            const SizedBox(height: 20),
          ],
          _buildAnonymousToggle(),
          const SizedBox(height: 30),
          _buildSignInButton(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppThemeColor.pureBlackColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(
          color: AppThemeColor.pureBlackColor,
          fontSize: Dimensions.fontSizeDefault,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: Dimensions.fontSizeDefault,
          ),
          prefixIcon: Icon(icon, color: AppThemeColor.darkBlueColor, size: 24),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          filled: true,
          fillColor: AppThemeColor.pureWhiteColor,
        ),
      ),
    );
  }

  Widget _buildAnonymousToggle() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppThemeColor.pureWhiteColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.9,
            child: Checkbox(
              value: _isAnonymousSignIn,
              onChanged: (value) {
                setState(() {
                  _isAnonymousSignIn = value ?? false;
                });
              },
              activeColor: AppThemeColor.darkGreenColor,
              side: BorderSide(
                color: AppThemeColor.pureWhiteColor.withOpacity(0.5),
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sign in anonymously',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor,
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Your name will be hidden from public view',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor.withOpacity(0.7),
                    fontSize: Dimensions.fontSizeSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleSignIn,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: AppThemeColor.buttonGradient,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: AppThemeColor.darkBlueColor.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppThemeColor.pureWhiteColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              _isLoading ? 'Signing In...' : 'Sign In to Event',
              style: TextStyle(
                color: AppThemeColor.pureWhiteColor,
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Column(
        children: [
          // Step labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStepLabel('Welcome', 0),
              _buildStepLabel('Choose Method', 1),
              _buildStepLabel('Enter Code', 2),
            ],
          ),
          const SizedBox(height: 15),
          // Step dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: index == _currentStep ? 16 : 12,
                height: index == _currentStep ? 16 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index <= _currentStep
                      ? AppThemeColor.darkBlueColor
                      : AppThemeColor.pureWhiteColor.withOpacity(0.3),
                  border: index == _currentStep
                      ? Border.all(
                          color: AppThemeColor.pureWhiteColor,
                          width: 2,
                        )
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLabel(String label, int stepIndex) {
    final isActive = stepIndex == _currentStep;
    final isCompleted = stepIndex < _currentStep;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: isActive
                ? AppThemeColor.darkBlueColor
                : isCompleted
                ? AppThemeColor.pureWhiteColor.withOpacity(0.8)
                : AppThemeColor.pureWhiteColor.withOpacity(0.4),
            fontSize: Dimensions.fontSizeSmall,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: AppThemeColor.darkBlueColor.withOpacity(0.7),
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppThemeColor.darkBlueColor.withOpacity(0.8),
              fontSize: Dimensions.fontSizeSmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: GestureDetector(
                onTap: _previousStep,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: AppThemeColor.pureWhiteColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: AppThemeColor.pureWhiteColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_back_ios,
                        color: AppThemeColor.pureWhiteColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Back',
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor,
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
          ],
          if (_currentStep == 0) ...[
            Expanded(
              child: GestureDetector(
                onTap: _nextStep,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: AppThemeColor.buttonGradient,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeColor.darkBlueColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor,
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: AppThemeColor.pureWhiteColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
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

    setState(() {
      _isLoading = true;
    });

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
          Future.delayed(const Duration(seconds: 1), () {
            RouterClass.nextScreenAndReplacement(
              context,
              SingleEventScreen(eventModel: eventExist),
            );
          });
        }
      } else {
        ShowToast().showNormalToast(msg: 'Entered an incorrect code!');
      }
    } catch (e) {
      print('Error signing in: $e');
      ShowToast().showNormalToast(msg: 'Failed to sign in. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
