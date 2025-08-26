import 'package:flutter/material.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/Utils/app_app_bar_view.dart';
import 'package:orgami/Utils/app_constants.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/text_fields.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  FeedbackScreenState createState() => FeedbackScreenState();
}

class FeedbackScreenState extends State<FeedbackScreen> {
  final _btnCtlr = RoundedLoadingButtonController();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _commentsController = TextEditingController();
  int _selectedRating = 0;
  bool _isAnonymous = false;
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();

  @override
  void initState() {
    final customer = CustomerController.logeInCustomer;
    if (customer != null) {
      _nameController.text = customer.name;
      _emailController.text = customer.email;
    }
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedRating == 0) {
        ShowToast().showSnackBar('Please select a rating', context);
        _btnCtlr.reset();
        return;
      }

      _btnCtlr.start();

      try {
        final customer = CustomerController.logeInCustomer;
        String userId = customer?.uid ?? '';
        String name = _nameController.text.trim();
        String email = _emailController.text.trim();
        String contact = _contactController.text.trim();
        String comment = _commentsController.text.trim();

        if (_isAnonymous) {
          userId = '';
          name = '';
          email = '';
          contact = '';
        }

        await _firestoreHelper.submitAppFeedback(
          userId: userId.isEmpty ? null : userId,
          rating: _selectedRating,
          comment: comment.isEmpty ? null : comment,
          isAnonymous: _isAnonymous,
          name: name.isEmpty ? null : name,
          email: email.isEmpty ? null : email,
          contactNumber: contact.isEmpty ? null : contact,
        );

        _btnCtlr.success();
        ShowToast().showSnackBar('Thank you for your feedback!', context);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pop(context);
      } catch (e) {
        _btnCtlr.error();
        ShowToast().showSnackBar('Error submitting feedback: $e', context);
      } finally {
        await Future.delayed(const Duration(seconds: 1));
        _btnCtlr.reset();
      }
    } else {
      _btnCtlr.reset();
    }
  }

  Widget _buildRatingStars() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rate your experience with ${AppConstants.appName}',
          style: TextStyle(
            fontSize: Dimensions.fontSizeExtraLarge,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRating = index + 1;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  index < _selectedRating ? Icons.star : Icons.star_border,
                  size: 48,
                  color: index < _selectedRating
                      ? AppColors.primaryColor
                      : Colors.grey[400],
                ),
              ),
            );
          }),
        ),
        // Remove the SizedBox and Center Text for rating label
        const SizedBox(height: 32),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppAppBarView.appBarWithOnlyBackButton(
          context: context,
          backButtonColor: AppColors.primaryColor,
        ),
        title: Text(
          'Feedback',
          style: TextStyle(
            color: AppColors.primaryColor,
            fontSize: Dimensions.fontSizeLarge,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildRatingStars(),
                // Remove name, contact, email fields
                AppTextFields.textField2(
                  controller: _commentsController,
                  hintText: 'Tell us about your experience...',
                  titleText: 'Comments',
                  width: MediaQuery.of(context).size.width,
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your feedback';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                CheckboxListTile(
                  title: const Text('Submit anonymously'),
                  value: _isAnonymous,
                  onChanged: (value) {
                    setState(() {
                      _isAnonymous = value ?? false;
                    });
                  },
                  activeColor: AppColors.primaryColor,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 24),
                RoundedLoadingButton(
                  animateOnTap: false,
                  borderRadius: 12,
                  width: MediaQuery.of(context).size.width,
                  controller: _btnCtlr,
                  onPressed: _handleSubmit,
                  color: AppColors.primaryColor,
                  elevation: 0,
                  child: const Text(
                    'Submit Feedback',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
