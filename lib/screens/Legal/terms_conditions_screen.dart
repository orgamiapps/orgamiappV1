import 'package:flutter/material.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Terms & Conditions',
              subtitle: 'Please read carefully',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryColor.withValues(alpha: 0.1),
                            AppColors.primaryColor.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Terms of Service',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Last Updated: ${_getFormattedDate()}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Please read these Terms and Conditions carefully before using ${AppConstants.appName}.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Terms content
                    _buildSection(
                      '1. Acceptance of Terms',
                      'By downloading, installing, accessing, or using the ${AppConstants.appName} mobile application ("App"), you agree to be bound by these Terms and Conditions ("Terms"). If you do not agree to these Terms, do not use the App.\n\nThese Terms constitute a legally binding agreement between you ("User," "you," or "your") and Storm Development ("Company," "we," "us," or "our"), the developer and operator of the App.',
                    ),

                    _buildSection(
                      '2. Description of Service',
                      '${AppConstants.appName} is an event attendance management application that allows users to:\n\n• Create and manage events\n• Track event attendance\n• Scan QR codes and NFC badges for check-ins\n• Manage event-related communications\n• Process payments for event features\n• Share event information\n\nThe App may include additional features and services that are subject to these Terms.',
                    ),

                    _buildSection(
                      '3. User Accounts and Registration',
                      'To use certain features of the App, you must create an account. You agree to:\n\n• Provide accurate, current, and complete information\n• Maintain the security of your account credentials\n• Accept responsibility for all activities under your account\n• Notify us immediately of any unauthorized use\n• Not share your account with others\n• Not create multiple accounts to circumvent restrictions\n\nWe reserve the right to suspend or terminate accounts that violate these Terms.',
                    ),

                    _buildSection(
                      '4. User Conduct and Prohibited Uses',
                      'You agree not to use the App to:\n\n• Violate any applicable laws or regulations\n• Infringe on intellectual property rights\n• Upload malicious code or viruses\n• Engage in harassment, abuse, or harmful behavior\n• Share inappropriate, offensive, or illegal content\n• Attempt to gain unauthorized access to our systems\n• Interfere with the App\'s functionality\n• Use automated tools to access the App\n• Engage in commercial activities without permission\n• Impersonate others or provide false information',
                    ),

                    _buildSection(
                      '5. Content and Intellectual Property',
                      'User Content: You retain ownership of content you create or upload. By using the App, you grant us a worldwide, non-exclusive, royalty-free license to use, display, and distribute your content as necessary to provide our services.\n\nApp Content: All App content, including but not limited to text, graphics, logos, software, and design, is owned by us or our licensors and protected by copyright, trademark, and other intellectual property laws.\n\nYou may not copy, modify, distribute, or create derivative works from our proprietary content without explicit written permission.',
                    ),

                    _buildSection(
                      '6. Privacy and Data Protection',
                      'Your privacy is important to us. Our collection, use, and protection of your personal information is governed by our Privacy Policy, which is incorporated into these Terms by reference.\n\nBy using the App, you consent to:\n\n• Collection and processing of your personal data\n• Use of cookies and similar technologies\n• International transfer of data for service provision\n• Data retention as outlined in our Privacy Policy\n\nWe implement appropriate security measures to protect your information, but cannot guarantee absolute security.',
                    ),

                    _buildSection(
                      '7. Payments and Subscriptions',
                      'Certain App features may require payment. By making a purchase, you agree to:\n\n• Provide accurate payment information\n• Pay all applicable fees and taxes\n• Comply with your payment provider\'s terms\n• Accept that all sales are final unless otherwise stated\n\nSubscriptions automatically renew unless cancelled. You may cancel subscriptions through your device\'s app store settings.\n\nWe use third-party payment processors and are not responsible for their actions or omissions.',
                    ),

                    _buildSection(
                      '8. Third-Party Services and Integrations',
                      'The App may integrate with third-party services, including:\n\n• Social media platforms (Google, Facebook, Apple)\n• Payment processors (Stripe)\n• Mapping services (Google Maps)\n• Cloud storage services (Firebase)\n• Analytics services\n\nThese integrations are subject to the respective third parties\' terms and privacy policies. We are not responsible for third-party services\' availability, security, or practices.',
                    ),

                    _buildSection(
                      '9. Device Permissions and Features',
                      'The App may request access to device features such as:\n\n• Camera (for QR code scanning)\n• Location services (for event location features)\n• Notifications (for event updates)\n• NFC (for badge scanning)\n• Storage (for saving event data)\n\nYou can manage these permissions through your device settings. Some features may not function properly if permissions are denied.',
                    ),

                    _buildSection(
                      '10. Disclaimers and Limitation of Liability',
                      'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.\n\nWE DO NOT WARRANT THAT:\n• The App will be uninterrupted or error-free\n• All errors will be corrected\n• The App is free from viruses or harmful components\n• Results obtained from the App will be accurate or reliable\n\nTO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR LIABILITY SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP IN THE PRECEDING 12 MONTHS. WE SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES.',
                    ),

                    _buildSection(
                      '11. Indemnification',
                      'You agree to indemnify, defend, and hold harmless the Company, its officers, directors, employees, and agents from any claims, damages, losses, or expenses (including reasonable attorney fees) arising from:\n\n• Your use of the App\n• Your violation of these Terms\n• Your violation of any third-party rights\n• Your content or conduct on the App\n\nThis indemnification obligation survives termination of these Terms.',
                    ),

                    _buildSection(
                      '12. Termination',
                      'We may terminate or suspend your access to the App immediately, without prior notice, for any reason, including:\n\n• Violation of these Terms\n• Fraudulent or illegal activity\n• Extended periods of inactivity\n• Technical or security concerns\n\nUpon termination, your right to use the App ceases immediately. Provisions that should survive termination will remain in effect.',
                    ),

                    _buildSection(
                      '13. Updates and Modifications',
                      'We reserve the right to:\n\n• Update or modify the App at any time\n• Change or discontinue features\n• Update these Terms with notice\n• Require app updates for continued use\n\nContinued use of the App after changes constitutes acceptance of the modifications. If you disagree with changes, discontinue use of the App.',
                    ),

                    _buildSection(
                      '14. Geographic Restrictions and Compliance',
                      'The App is intended for use in jurisdictions where it is legal. You are responsible for ensuring your use complies with local laws and regulations.\n\nCertain features may not be available in all regions due to legal or technical restrictions.\n\nBy using the App, you represent that you are not located in a country subject to a U.S. Government embargo or designated as a "terrorist supporting" country.',
                    ),

                    _buildSection(
                      '15. Age Requirements',
                      'The App is not intended for children under 13 years of age. If you are between 13 and 18 years old, you may use the App only with parental consent and supervision.\n\nWe do not knowingly collect personal information from children under 13. If we become aware of such collection, we will delete the information promptly.',
                    ),

                    _buildSection(
                      '16. Dispute Resolution and Governing Law',
                      'These Terms are governed by and construed in accordance with the laws of [Your Jurisdiction], without regard to conflict of law principles.\n\nAny disputes arising from these Terms or your use of the App shall be resolved through binding arbitration, except for claims that may be brought in small claims court.\n\nThe arbitration shall be conducted by a single arbitrator in accordance with the rules of the American Arbitration Association.',
                    ),

                    _buildSection(
                      '17. Severability and Waiver',
                      'If any provision of these Terms is found to be unenforceable, the remaining provisions will remain in full force and effect.\n\nOur failure to enforce any right or provision of these Terms will not be considered a waiver of those rights.',
                    ),

                    _buildSection(
                      '18. Contact Information',
                      'If you have questions about these Terms, please contact us at:\n\nEmail: ${AppConstants.companyEmail}\nSupport: ${AppConstants.supportUrl}\n\nWe will respond to inquiries within a reasonable time frame.',
                    ),

                    _buildSection(
                      '19. Apple App Store Additional Terms',
                      'If you downloaded the App from the Apple App Store, the following additional terms apply:\n\n• Apple is not a party to these Terms and has no responsibility for the App\n• Your license to use the App is limited to a non-transferable license to use the App on Apple-branded products\n• Apple has no obligation to provide maintenance or support services\n• Apple is not responsible for addressing any claims relating to the App\n• In case of third-party claims that the App infringes intellectual property rights, Apple will not be responsible for investigation or defense',
                    ),

                    _buildSection(
                      '20. Google Play Store Additional Terms',
                      'If you downloaded the App from Google Play, you agree to the Google Play Terms of Service, and the following additional terms apply:\n\n• Google is not a party to these Terms and has no responsibility for the App\n• Your use of the App must comply with Google Play\'s Content Policy\n• Google may remove the App from your device in certain circumstances as outlined in the Google Play Terms of Service',
                    ),

                    // Footer
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Effective Date',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'These Terms and Conditions are effective as of ${_getFormattedDate()} and were last updated on ${_getFormattedDate()}.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'By continuing to use ${AppConstants.appName}, you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.6,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}
