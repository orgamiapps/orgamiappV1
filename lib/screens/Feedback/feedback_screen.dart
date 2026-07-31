import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
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
        if (mounted) {
          ShowToast().showSnackBar('Thank you for your feedback!', context);
        }
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        _btnCtlr.error();
        if (mounted) {
          ShowToast().showSnackBar('Error submitting feedback: $e', context);
        }
      } finally {
        await Future.delayed(const Duration(seconds: 1));
        _btnCtlr.reset();
      }
    } else {
      _btnCtlr.reset();
    }
  }

  Widget _buildRatingStars() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rate your Attendus experience',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
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
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.outline,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Feedback',
              subtitle: 'Share your experience with us',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Form(
                      key: _formKey,
                      child: AttendUsPageSection(
                        title: 'Product feedback',
                        subtitle:
                            'Tell us what worked, what felt unclear, or what would make Attendus more useful.',
                        icon: Icons.rate_review_outlined,
                        framed: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRatingStars(),
                            const SizedBox(height: 24),
                            AttendUsFormTextField(
                              controller: _commentsController,
                              hintText: 'Tell us about your experience...',
                              labelText: 'Comments',
                              prefixIcon: Icons.notes_outlined,
                              maxLines: 5,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your feedback';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              title: const Text('Submit anonymously'),
                              subtitle: const Text(
                                'Your profile details will not be attached to this feedback.',
                              ),
                              value: _isAnonymous,
                              onChanged: (value) {
                                setState(() {
                                  _isAnonymous = value ?? false;
                                });
                              },
                              activeColor: theme.colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: RoundedLoadingButton(
                                animateOnTap: false,
                                borderRadius: 12,
                                width: 760,
                                controller: _btnCtlr,
                                onPressed: _handleSubmit,
                                color: theme.colorScheme.primary,
                                elevation: 0,
                                child: Text(
                                  'Submit Feedback',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
