import 'package:flutter/material.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/app_constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
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
                    'Privacy Policy',
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
                    'Your privacy is important to us. This Privacy Policy explains how ${AppConstants.appName} collects, uses, and protects your information.',
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

            // Privacy policy content
            _buildSection(
              '1. Information We Collect',
              'We collect several types of information to provide and improve our services:\n\n**Personal Information:**\n• Name, email address, and phone number\n• Profile picture and bio information\n• Account credentials and authentication data\n• Payment information (processed securely by third parties)\n\n**Event Data:**\n• Events you create, attend, or interact with\n• Event check-in and attendance records\n• Event feedback and ratings\n• Communication within event groups\n\n**Location Information:**\n• Precise location data when using location-based features\n• Venue check-in locations\n• Dwell time tracking (when enabled by event organizers)\n• Geographic preferences for event discovery\n\n**Device and Usage Information:**\n• Device identifiers and hardware information\n• Operating system and app version\n• App usage patterns and feature interactions\n• Crash reports and performance data\n• Network information and IP address\n\n**Camera and Media:**\n• Photos and videos uploaded to events\n• QR code scan data\n• Profile pictures and event images\n\n**Communications:**\n• Messages sent through the app\n• Push notification preferences\n• Customer support interactions',
            ),

            _buildSection(
              '2. How We Use Your Information',
              'We use your information for the following purposes:\n\n**Service Provision:**\n• Create and manage your account\n• Process event registrations and payments\n• Enable event check-ins and attendance tracking\n• Facilitate communication between users\n• Provide customer support\n\n**Personalization:**\n• Recommend relevant events based on your interests\n• Customize your app experience\n• Show location-based event suggestions\n• Provide personalized notifications\n\n**Analytics and Improvement:**\n• Analyze app usage patterns to improve functionality\n• Generate aggregated event analytics for organizers\n• Conduct research and development\n• Monitor app performance and fix bugs\n\n**Security and Safety:**\n• Verify user identity and prevent fraud\n• Detect and prevent unauthorized access\n• Enforce our Terms of Service\n• Protect against spam and abuse\n\n**Legal and Compliance:**\n• Comply with applicable laws and regulations\n• Respond to legal requests and court orders\n• Protect our rights and property\n• Resolve disputes',
            ),

            _buildSection(
              '3. Information Sharing and Disclosure',
              'We may share your information in the following circumstances:\n\n**With Event Organizers:**\n• Attendance and check-in data for events you join\n• Contact information for event communication\n• Feedback and ratings you provide\n• Dwell time data (when tracking is enabled)\n\n**With Other Users:**\n• Public profile information (name, picture, bio)\n• Event participation (when events are public)\n• Messages and communications within events\n• Shared photos and content\n\n**With Service Providers:**\n• Payment processors (Stripe) for transaction processing\n• Cloud storage providers (Firebase) for data hosting\n• Analytics services for app improvement\n• Customer support tools\n• Push notification services\n\n**For Legal Reasons:**\n• To comply with legal obligations\n• To protect and defend our rights\n• To prevent fraud or security threats\n• In connection with legal proceedings\n\n**Business Transfers:**\n• In case of merger, acquisition, or sale of assets\n• During business restructuring or bankruptcy\n\n**With Your Consent:**\n• Any other sharing with your explicit permission\n• Third-party integrations you authorize',
            ),

            _buildSection(
              '4. Data Retention',
              'We retain your information for different periods based on the type of data and our business needs:\n\n**Account Information:**\n• Retained while your account is active\n• Deleted within 30 days of account deletion request\n• Some data may be retained longer for legal compliance\n\n**Event Data:**\n• Event attendance records: 7 years for tax and legal purposes\n• Event content and messages: Until event deletion or account closure\n• Analytics data: Aggregated data retained indefinitely\n\n**Location Data:**\n• Real-time location: Not stored permanently\n• Check-in locations: Retained with event records\n• Dwell tracking data: Deleted after event conclusion unless required for analytics\n\n**Technical Data:**\n• Device and usage logs: 2 years\n• Crash reports: 1 year\n• Security logs: 3 years\n\n**Communication Records:**\n• Customer support: 3 years\n• Legal communications: 7 years or as required by law\n\nYou can request deletion of your data at any time through your account settings or by contacting us.',
            ),

            _buildSection(
              '5. Your Privacy Rights',
              'Depending on your location, you may have the following rights:\n\n**Access and Portability:**\n• Request a copy of your personal data\n• Download your data in a portable format\n• View what information we have about you\n\n**Correction and Updates:**\n• Correct inaccurate personal information\n• Update your profile and preferences\n• Modify privacy settings\n\n**Deletion and Erasure:**\n• Delete your account and associated data\n• Request removal of specific information\n• Withdraw consent for data processing\n\n**Restriction and Objection:**\n• Limit how we process your data\n• Object to certain types of processing\n• Opt out of marketing communications\n\n**GDPR Rights (EU Residents):**\n• Right to be forgotten\n• Data portability\n• Right to object to automated decision-making\n• Right to lodge complaints with supervisory authorities\n\n**CCPA Rights (California Residents):**\n• Right to know what personal information is collected\n• Right to delete personal information\n• Right to opt-out of sale (we do not sell personal information)\n• Right to non-discrimination\n\nTo exercise these rights, contact us at ${AppConstants.companyEmail} or through the app settings.',
            ),

            _buildSection(
              '6. Children\'s Privacy (COPPA Compliance)',
              '${AppConstants.appName} is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13.\n\n**If We Discover Child Data:**\n• We will delete the information immediately\n• We will terminate the account\n• We will notify parents/guardians if possible\n\n**Parental Rights:**\n• Parents can request to review their child\'s information\n• Parents can request deletion of their child\'s data\n• Parents can refuse further collection of their child\'s information\n\n**Teen Users (13-17):**\n• Parental consent may be required for certain features\n• Enhanced privacy protections apply\n• Limited data sharing with third parties\n• Special consideration for location tracking\n\nIf you believe we have collected information from a child under 13, please contact us immediately at ${AppConstants.companyEmail}.',
            ),

            _buildSection(
              '7. International Data Transfers',
              'Your information may be transferred to and processed in countries other than your own:\n\n**Data Transfer Safeguards:**\n• We use appropriate safeguards for international transfers\n• Standard Contractual Clauses (SCCs) for EU data\n• Adequacy decisions where applicable\n• Binding Corporate Rules for internal transfers\n\n**Primary Data Locations:**\n• United States (Firebase, Google Cloud)\n• European Union (for EU users where possible)\n• Other regions as needed for service provision\n\n**Your Consent:**\n• By using the app, you consent to these transfers\n• You can withdraw consent and request data deletion\n• We will inform you of any changes to data locations',
            ),

            _buildSection(
              '8. Data Security',
              'We implement comprehensive security measures to protect your information:\n\n**Technical Safeguards:**\n• Encryption in transit and at rest\n• Secure authentication protocols\n• Regular security audits and assessments\n• Intrusion detection and prevention systems\n• Secure development practices\n\n**Administrative Safeguards:**\n• Employee training on privacy and security\n• Access controls and authorization procedures\n• Background checks for personnel with data access\n• Incident response and breach notification procedures\n\n**Physical Safeguards:**\n• Secure data centers with restricted access\n• Environmental controls and monitoring\n• Backup and disaster recovery procedures\n\n**Third-Party Security:**\n• Due diligence on service providers\n• Contractual security requirements\n• Regular security assessments of vendors\n\n**Data Breach Response:**\n• Immediate containment and investigation\n• Notification to authorities within 72 hours (where required)\n• User notification for high-risk breaches\n• Remediation and prevention measures\n\nWhile we implement strong security measures, no system is 100% secure. We encourage you to use strong passwords and enable two-factor authentication.',
            ),

            _buildSection(
              '9. Cookies and Tracking Technologies',
              'We use various technologies to collect and store information:\n\n**Types of Technologies:**\n• Cookies and local storage\n• Device identifiers and advertising IDs\n• Pixel tags and web beacons\n• Analytics and measurement tools\n• Push notification tokens\n\n**Purposes:**\n• Maintain your login session\n• Remember your preferences and settings\n• Analyze app usage and performance\n• Provide personalized content and recommendations\n• Deliver relevant notifications\n\n**Third-Party Analytics:**\n• Firebase Analytics for app usage insights\n• Crash reporting for stability improvements\n• Performance monitoring for optimization\n\n**Your Choices:**\n• Disable analytics through app settings\n• Reset advertising ID on your device\n• Opt out of personalized ads\n• Clear local data through device settings\n\nSome features may not function properly if you disable certain technologies.',
            ),

            _buildSection(
              '10. Third-Party Services and Integrations',
              'Our app integrates with various third-party services, each with their own privacy practices:\n\n**Authentication Services:**\n• Google Sign-In: Google Privacy Policy applies\n• Apple Sign-In: Apple Privacy Policy applies\n• Facebook Login: Facebook Privacy Policy applies\n\n**Payment Processing:**\n• Stripe: Handles payment information securely\n• We do not store full credit card numbers\n• PCI DSS compliant processing\n\n**Mapping and Location:**\n• Google Maps: For location services and venue mapping\n• Location data shared as necessary for functionality\n\n**Cloud Services:**\n• Firebase (Google): Data storage and authentication\n• Google Cloud: Backend services and analytics\n\n**Communication Services:**\n• Push notification providers\n• Email service providers\n• SMS services for verification\n\n**Social Media:**\n• Sharing to social platforms (with your permission)\n• Social login integration\n\n**Your Control:**\n• You can disconnect third-party integrations\n• Review permissions granted to external services\n• Contact third parties directly about their practices\n\nWe are not responsible for third-party privacy practices. Please review their policies independently.',
            ),

            _buildSection(
              '11. Marketing and Communications',
              'We may communicate with you about our services:\n\n**Types of Communications:**\n• Event notifications and updates\n• Account and security notifications\n• Product updates and new features\n• Marketing messages and promotions\n• Customer support communications\n\n**Opt-Out Options:**\n• Unsubscribe from marketing emails\n• Disable push notifications in app settings\n• Adjust notification preferences by category\n• Contact us to opt out of all non-essential communications\n\n**Transactional Messages:**\n• Some messages are necessary for service operation\n• Account security notifications\n• Payment confirmations and receipts\n• Legal notices and policy updates\n\n**Personalization:**\n• We may personalize communications based on your activity\n• Location-based event recommendations\n• Interest-based content suggestions\n\nYou can manage your communication preferences in the app settings or by contacting us.',
            ),

            _buildSection(
              '12. California Privacy Rights (CCPA)',
              'California residents have additional privacy rights under the California Consumer Privacy Act:\n\n**Right to Know:**\n• Categories of personal information collected\n• Sources of personal information\n• Business purposes for collection\n• Categories of third parties with whom we share information\n• Specific pieces of personal information collected\n\n**Right to Delete:**\n• Request deletion of personal information\n• Exceptions for legal compliance and legitimate business needs\n• Confirmation of deletion upon request\n\n**Right to Opt-Out:**\n• We do not sell personal information\n• We do not share for cross-context behavioral advertising\n• You can still opt out of data sharing for marketing\n\n**Right to Non-Discrimination:**\n• We will not discriminate against you for exercising your rights\n• Same service quality regardless of privacy choices\n• No penalties for privacy requests\n\n**Authorized Agents:**\n• You can designate an agent to make requests on your behalf\n• Agent must provide proof of authorization\n• You may need to verify your identity directly\n\n**Verification Process:**\n• We verify your identity before processing requests\n• May require additional information for sensitive requests\n• Response within 45 days (extendable to 90 days)\n\nTo exercise your CCPA rights, email us at ${AppConstants.companyEmail} with "CCPA Request" in the subject line.',
            ),

            _buildSection(
              '13. European Privacy Rights (GDPR)',
              'If you are in the European Union, you have additional rights under the General Data Protection Regulation:\n\n**Legal Basis for Processing:**\n• Consent: For optional features and marketing\n• Contract: For service provision and account management\n• Legitimate Interest: For analytics and security\n• Legal Obligation: For compliance and safety\n\n**Enhanced Rights:**\n• Right of access to your personal data\n• Right to rectification of inaccurate data\n• Right to erasure ("right to be forgotten")\n• Right to restrict processing\n• Right to data portability\n• Right to object to processing\n• Rights related to automated decision-making\n\n**Data Protection Officer:**\n• Contact our DPO for privacy concerns: ${AppConstants.companyEmail}\n• DPO oversees compliance and responds to inquiries\n• Independent authority to investigate privacy matters\n\n**Supervisory Authority:**\n• You have the right to lodge a complaint with your local data protection authority\n• Contact information available at your national DPA website\n• We will cooperate fully with regulatory investigations\n\n**International Transfers:**\n• Appropriate safeguards for transfers outside the EU\n• Standard Contractual Clauses where applicable\n• Adequacy decisions for certain countries\n\n**Data Breach Notification:**\n• Notification to supervisory authorities within 72 hours\n• Individual notification for high-risk breaches\n• Regular breach risk assessments',
            ),

            _buildSection(
              '14. Changes to This Privacy Policy',
              'We may update this Privacy Policy from time to time:\n\n**Notification of Changes:**\n• In-app notification for material changes\n• Email notification to registered users\n• Updated "Last Modified" date at the top\n• Prominent notice on app launch\n\n**Types of Changes:**\n• New features or services\n• Changes in data practices\n• Legal or regulatory requirements\n• Business structure changes\n• Enhanced privacy protections\n\n**Your Continued Use:**\n• Continued use after changes constitutes acceptance\n• You can delete your account if you disagree with changes\n• We will seek consent for material changes where required\n\n**Version History:**\n• Previous versions available upon request\n• Documentation of significant changes\n• Effective dates for each version\n\nWe encourage you to review this policy periodically to stay informed about how we protect your privacy.',
            ),

            _buildSection(
              '15. Contact Us',
              'If you have questions, concerns, or requests regarding this Privacy Policy or our privacy practices:\n\n**Email:** ${AppConstants.companyEmail}\n**Subject Line:** Privacy Policy Inquiry\n\n**Support Center:** ${AppConstants.supportUrl}\n\n**Response Time:**\n• General inquiries: Within 5 business days\n• Privacy rights requests: Within 30 days\n• Urgent security matters: Within 24 hours\n\n**What to Include:**\n• Your name and contact information\n• Description of your inquiry or request\n• Account information (if applicable)\n• Preferred method of response\n\n**Data Protection Officer:**\n• For EU residents and GDPR-related inquiries\n• Email: ${AppConstants.companyEmail} with "DPO" in subject\n• Independent review of privacy concerns\n\n**Regulatory Contacts:**\n• We will provide relevant regulatory contact information upon request\n• Assistance with filing complaints with supervisory authorities\n• Cooperation with official investigations\n\nWe are committed to addressing your privacy concerns promptly and thoroughly.',
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
                    'Your Privacy Matters',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This Privacy Policy is effective as of ${_getFormattedDate()}. We are committed to protecting your privacy and handling your personal information responsibly.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By using ${AppConstants.appName}, you acknowledge that you have read, understood, and agree to this Privacy Policy.',
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
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}
