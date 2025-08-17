import 'package:flutter/material.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/Utils/app_app_bar_view.dart';
import 'package:orgami/Utils/app_constants.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/images.dart';
import 'package:orgami/Utils/text_fields.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:url_launcher/url_launcher.dart';

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
  double _sliderValue = 1.0;
  String _experience = "Worst";

  Future<void> _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text;
      final contact = _contactController.text;
      final email = _emailController.text;
      final experience = _experience;
      final comments = _commentsController.text;

      final subject = Uri.encodeComponent('New Feedback Submission');
      final body = Uri.encodeComponent(
        'Name: $name\n'
        'Contact: $contact\n'
        'Email: $email\n'
        'Experience: $experience\n'
        'Comments: $comments',
      );

      final url =
          'mailto:${AppConstants.companyEmail}?subject=$subject&body=$body';

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        throw 'Could not launch $url';
      }
    }
  }

  @override
  void initState() {
    _nameController.text = CustomerController.logeInCustomer!.name;
    _emailController.text = CustomerController.logeInCustomer!.email;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
        child: RoundedLoadingButton(
          animateOnTap: false,
          borderRadius: 5,
          width: MediaQuery.of(context).size.width,
          controller: _btnCtlr,
          onPressed: () => _handleSubmit(),
          color: AppThemeColor.darkGreenColor,
          elevation: 0,
          child: const Wrap(
            children: [
              Text(
                'Submit Feedback',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppAppBarView.appBarView(context: context, title: 'Feedback'),
                  const SizedBox(height: 20),
                  AppTextFields.textField2(
                    hintText: 'Type here...',
                    titleText: 'Name',
                    width: MediaQuery.of(context).size.width,
                    controller: _nameController,
                    validator: (value) {
                      if (value!.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextFields.textField2(
                    hintText: '+92 00000 00000',
                    titleText: 'Contact Number',
                    width: MediaQuery.of(context).size.width,
                    controller: _contactController,
                    validator: (value) {
                      if (value!.isEmpty) {
                        return 'Please enter your contact number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextFields.textField2(
                    hintText: 'xyz123@gmail.com',
                    titleText: 'Email Address',
                    enabled: false,
                    width: MediaQuery.of(context).size.width,
                    controller: _emailController,
                    validator: (value) {
                      if (value!.isEmpty) {
                        return 'Please enter your email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Share your experience with ${AppConstants.appName}',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _singleIconView(
                        label: 'Worst',
                        activeImage: Images.worstActive,
                        nonActiveImage: Images.worstNonActive,
                        numberValue: 1.0,
                      ),
                      _singleIconView(
                        label: 'Not Good',
                        activeImage: Images.fineActive,
                        nonActiveImage: Images.fineNonActive,
                        numberValue: 2.0,
                      ),
                      _singleIconView(
                        label: 'Fine',
                        activeImage: Images.neutralActive,
                        nonActiveImage: Images.neutralNonActive,
                        numberValue: 3.0,
                      ),
                      _singleIconView(
                        label: 'Look Good',
                        activeImage: Images.goodActive,
                        nonActiveImage: Images.goodNonActive,
                        numberValue: 4.0,
                      ),
                      _singleIconView(
                        label: 'Very Good',
                        activeImage: Images.loveActive,
                        nonActiveImage: Images.loveNonActive,
                        numberValue: 5.0,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(0.0),
                    child: Slider(
                      value: _sliderValue,
                      min: 1,
                      max: 5,
                      divisions: 4,
                      onChanged: (value) {
                        setState(() {
                          _sliderValue = value;
                          switch (value.toInt()) {
                            case 1:
                              _experience = "Worst";
                              break;
                            case 2:
                              _experience = "Not Good";
                              break;
                            case 3:
                              _experience = "Fine";
                              break;
                            case 4:
                              _experience = "Look Good";
                              break;
                            case 5:
                              _experience = "Very Good";
                              break;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextFields.textField2(
                    controller: _commentsController,
                    hintText: 'Add your comments...',
                    titleText: 'Your Comments',
                    width: MediaQuery.of(context).size.width,
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your comments';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _singleIconView({
    required String activeImage,
    required String nonActiveImage,
    required String label,
    required double numberValue,
  }) {
    String imageToShow = _experience == label ? activeImage : nonActiveImage;
    return SizedBox(
      width: 50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(imageToShow, width: 40),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _sliderValue == numberValue
                  ? AppThemeColor.pureBlackColor
                  : AppThemeColor.dullFontColor,
            ),
          ),
        ],
      ),
    );
  }
}
