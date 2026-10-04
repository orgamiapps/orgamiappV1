import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/screens/Legal/legal_document_layout.dart';
import 'package:flutter/material.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const _version = '2026.08.02';
  static const _effectiveDate = 'August 2, 2026';

  @override
  Widget build(BuildContext context) {
    return LegalDocumentLayout(
      title: 'Terms of Service',
      subtitle: 'Rules for using Attendus',
      version: _version,
      effectiveDate: _effectiveDate,
      reviewNotice:
          'Interim notice: jurisdiction-specific governing-law, arbitration, '
          'and consumer-rights language is pending formal legal review. No '
          'placeholder jurisdiction or unapproved arbitration term is '
          'presented as binding.',
      introduction:
          'These terms apply when you access or use ${AppConstants.appName}. '
          'If you do not agree, do not use the service.',
      sections: const [
        LegalSection(
          title: '1. Accounts',
          body:
              'Provide accurate account information, protect your credentials, '
              'and notify us if you suspect unauthorized access. You are '
              'responsible for activity performed through your account. Do '
              'not create accounts to impersonate another person or evade '
              'safety restrictions.',
        ),
        LegalSection(
          title: '2. Service availability',
          body:
              'Attendus provides event discovery, groups, messaging, '
              'attendance, check-in, organizer tools, and related features. '
              'Features may change or be temporarily unavailable for security, '
              'maintenance, legal, or reliability reasons. Facial check-in and '
              'legacy paid-feature flows are currently unavailable.',
        ),
        LegalSection(
          title: '3. Acceptable use',
          body:
              'Do not break the law, harass others, distribute malicious or '
              'illegal content, impersonate another person, access data you '
              'are not authorized to see, interfere with the service, evade '
              'rate limits, exploit security defects, or use automated systems '
              'in a way that harms Attendus or its users.',
        ),
        LegalSection(
          title: '4. Your content',
          body:
              'You retain ownership of content you submit. You grant Attendus '
              'a non-exclusive license to host, process, display, and transmit '
              'that content only as needed to operate and improve the service. '
              'You must have the right to submit the content and remain '
              'responsible for it.',
        ),
        LegalSection(
          title: '5. Organizer responsibilities',
          body:
              'Organizers are responsible for their events, invitations, '
              'attendance practices, communications, permissions, refunds, '
              'and compliance obligations. Organizer access to attendee or '
              'group data must be used only for an authorized purpose.',
        ),
        LegalSection(
          title: '6. Payments',
          body:
              'Paid upgrades and event featuring are unavailable while the '
              'payment system is hardened. If paid features are re-enabled, '
              'prices and entitlements will be determined by Attendus servers '
              'and payment-provider records. Purchase-specific refund and '
              'renewal terms must be shown before a charge is authorized.',
        ),
        LegalSection(
          title: '7. Privacy and permissions',
          body:
              'The Privacy Policy explains current data practices. Optional '
              'camera, location, notification, and media permissions can be '
              'managed through your device. Some features will not work when '
              'their required permission is declined.',
        ),
        LegalSection(
          title: '8. Third-party services',
          body:
              'Attendus depends on third-party infrastructure and platform '
              'services. Their own terms may apply when you use them. Attendus '
              'does not control an external provider’s availability or '
              'independent practices.',
        ),
        LegalSection(
          title: '9. Suspension and termination',
          body:
              'We may restrict or suspend access when reasonably necessary to '
              'protect users, investigate abuse, comply with law, or preserve '
              'service integrity. You may stop using Attendus and request '
              'account deletion. Obligations that by their nature survive '
              'termination remain applicable.',
        ),
        LegalSection(
          title: '10. Disclaimers and liability',
          body:
              'The service is provided on an “as available” basis. Nothing in '
              'these terms excludes warranties, remedies, or liability that '
              'applicable law does not allow to be excluded. Any limitation of '
              'liability must be interpreted subject to those mandatory '
              'rights.',
        ),
        LegalSection(
          title: '11. Disputes and applicable law',
          body:
              'Applicable law and available dispute procedures depend on the '
              'parties and location. This interim version does not impose a '
              'placeholder jurisdiction or mandatory arbitration provision. '
              'A reviewed update will identify the service operator and any '
              'jurisdiction-specific process before such terms take effect.',
        ),
        LegalSection(
          title: '12. Changes and contact',
          body:
              'Material changes will be published with a new version and fixed '
              'effective date. Contact ${AppConstants.companyEmail} with '
              'questions. Support information is available at '
              '${AppConstants.supportUrl}.',
        ),
      ],
    );
  }
}
