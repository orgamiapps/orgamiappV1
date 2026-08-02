import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/screens/Legal/legal_document_layout.dart';
import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _version = '2026.08.02';
  static const _effectiveDate = 'August 2, 2026';

  @override
  Widget build(BuildContext context) {
    return LegalDocumentLayout(
      title: 'Privacy Policy',
      subtitle: 'How Attendus handles personal information',
      version: _version,
      effectiveDate: _effectiveDate,
      reviewNotice:
          'Interim notice: this document has been aligned with the current '
          'product while formal legal review is completed. It does not claim '
          'features, retention periods, or compliance contacts that are not '
          'currently in place.',
      introduction:
          'This policy describes the information ${AppConstants.appName} '
          'processes, why it is used, when it is shared, and the choices '
          'available to you.',
      sections: const [
        LegalSection(
          title: '1. Information we process',
          body:
              '- Account details such as name, email address, authentication '
              'identifiers, profile information, and notification settings.\n'
              '- Event, group, ticket, attendance, check-in, message, and '
              'content records created through the service.\n'
              '- Images and files you choose to upload.\n'
              '- Location information only when you grant permission and use '
              'a location-dependent feature.\n'
              '- Device, diagnostic, security, and usage data needed to run, '
              'protect, and improve the service.',
        ),
        LegalSection(
          title: '2. How information is used',
          body:
              'We use information to authenticate accounts, provide event and '
              'group features, deliver messages and notifications, support '
              'check-in, prevent abuse, troubleshoot failures, improve '
              'reliability, and comply with applicable legal obligations. '
              'Organizer analytics should be limited to information the '
              'organizer is authorized to access.',
        ),
        LegalSection(
          title: '3. Sharing and service providers',
          body:
              'Information may be visible to people you intentionally interact '
              'with, such as an event organizer, group members, conversation '
              'participants, or viewers of content you make public. Attendus '
              'uses Firebase and Google Cloud for application infrastructure, '
              'Google Maps for mapping features, and platform notification '
              'services. Stripe may process payment details if paid features '
              'are re-enabled. Attendus does not need to store full payment '
              'card numbers. We may disclose information when legally required '
              'or to protect users and the service.',
        ),
        LegalSection(
          title: '4. Payments and entitlements',
          body:
              'Paid upgrades, event featuring, and client-confirmed payment '
              'flows are currently unavailable while server-authoritative '
              'payment processing is completed. If payments are re-enabled, '
              'the payment provider and Attendus server records—not client '
              'input—will determine transaction and entitlement status.',
        ),
        LegalSection(
          title: '5. Biometrics',
          body:
              'Facial enrollment and facial check-in are currently disabled. '
              'Client access to existing facial-template records is denied '
              'while those records are inventoried and removed under the '
              'project retention plan. Do not submit biometric information to '
              'Attendus. Any future biometric feature would require a separate '
              'notice, explicit consent, security and retention controls, and '
              'independent privacy and security review before release.',
        ),
        LegalSection(
          title: '6. Retention and deletion',
          body:
              'We retain information only while it is needed to provide the '
              'service, protect users, resolve disputes, meet legal '
              'obligations, or complete a requested deletion. Retention '
              'depends on the record type and applicable requirements; this '
              'policy does not promise unsupported fixed periods. Account '
              'deletion is processed by an auditable server job covering the '
              'account and associated application records. Some transaction '
              'references may be anonymized or retained where legally '
              'required.',
        ),
        LegalSection(
          title: '7. Security',
          body:
              'Attendus uses authentication, authorization rules, validated '
              'server operations, transport security, rate limits, and '
              'restricted file uploads. No system can guarantee absolute '
              'security. Please protect your account credentials and report '
              'suspected unauthorized access promptly.',
        ),
        LegalSection(
          title: '8. Your choices and rights',
          body:
              'You can update profile and notification preferences, decline '
              'optional camera or location permissions, and request account '
              'deletion. Depending on where you live, applicable law may also '
              'provide rights to access, correct, export, restrict, object to, '
              'or delete personal information. We may need to verify your '
              'identity before completing a request.',
        ),
        LegalSection(
          title: '9. Children',
          body:
              'Attendus is not directed to children under 13. If you believe a '
              'child has provided personal information without appropriate '
              'authorization, contact us so the account and data can be '
              'reviewed.',
        ),
        LegalSection(
          title: '10. International processing',
          body:
              'Service providers may process information in countries other '
              'than your own. Where required, Attendus will use an appropriate '
              'legal mechanism for that processing. This policy does not claim '
              'a transfer mechanism that has not been formally established.',
        ),
        LegalSection(
          title: '11. Changes and contact',
          body:
              'Material changes will be published with a new version and fixed '
              'effective date. Questions and privacy requests can be sent to '
              '${AppConstants.companyEmail}. Support information is available '
              'at ${AppConstants.supportUrl}.',
        ),
      ],
    );
  }
}
