import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/models/event_model.dart';

class SignInMethodsDisplay extends StatelessWidget {
  final EventModel eventModel;
  final bool isEventCreator;
  final VoidCallback? onCopyCode;

  const SignInMethodsDisplay({
    super.key,
    required this.eventModel,
    this.isEventCreator = false,
    this.onCopyCode,
  });

  @override
  Widget build(BuildContext context) {
    final availableMethods = eventModel.getAvailableSignInMethods();
    
    if (availableMethods.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.security,
                  color: Color(0xFF667EEA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Sign-In Security',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
              const Spacer(),
              if (isEventCreator)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Host',
                    style: TextStyle(
                      color: Color(0xFF667EEA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Show security tier badge if using new system
          if (eventModel.signInSecurityTier != null)
            _buildSecurityTierBadge(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableMethods.map((method) {
              return _buildMethodChip(method);
            }).toList(),
          ),
          if (eventModel.isSignInMethodEnabled('manual_code'))
            _buildManualCodeSection(),
        ],
      ),
    );
  }
  
  Widget _buildSecurityTierBadge() {
    String tierText;
    Color tierColor;
    IconData tierIcon;
    
    switch (eventModel.signInSecurityTier) {
      case 'most_secure':
        tierText = 'Most Secure';
        tierColor = const Color(0xFFFF6B6B);
        tierIcon = Icons.verified_user;
        break;
      case 'regular':
        tierText = 'Regular Security';
        tierColor = const Color(0xFF667EEA);
        tierIcon = Icons.shield;
        break;
      case 'all':
        tierText = 'All Methods Available';
        tierColor = const Color(0xFF11998E);
        tierIcon = Icons.all_inclusive;
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.15),
            tierColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tierIcon, color: tierColor, size: 16),
          const SizedBox(width: 8),
          Text(
            tierText,
            style: TextStyle(
              color: tierColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodChip(String method) {
    final methodInfo = _getMethodInfo(method);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: methodInfo['color'].withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: methodInfo['color'].withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(methodInfo['icon'], color: methodInfo['color'], size: 16),
          const SizedBox(width: 6),
          Text(
            methodInfo['title'],
            style: TextStyle(
              color: methodInfo['color'],
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualCodeSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF764BA2).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF764BA2).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard, color: const Color(0xFF764BA2), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual Code',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eventModel.getManualCode(),
                  style: const TextStyle(
                    color: Color(0xFF764BA2),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          if (isEventCreator)
            GestureDetector(
              onTap: () {
                // Copy code to clipboard
                Clipboard.setData(
                  ClipboardData(text: eventModel.getManualCode()),
                );
                onCopyCode?.call();
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF764BA2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.copy, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getMethodInfo(String method) {
    switch (method) {
      case 'most_secure':
        return {
          'title': 'Most Secure',
          'icon': Icons.verified_user,
          'color': const Color(0xFFFF6B6B),
        };
      case 'facial_recognition':
        return {
          'title': 'Facial Recognition',
          'icon': Icons.face,
          'color': const Color(0xFFFF6B6B),
        };
      case 'qr_code':
        return {
          'title': 'QR Code',
          'icon': Icons.qr_code_scanner,
          'color': const Color(0xFF667EEA),
        };
      case 'manual_code':
        return {
          'title': 'Manual Code',
          'icon': Icons.keyboard,
          'color': const Color(0xFF764BA2),
        };
      case 'geofence':
        return {
          'title': 'Geofence',
          'icon': Icons.location_on,
          'color': const Color(0xFFF093FB),
        };
      default:
        return {'title': 'Unknown', 'icon': Icons.help, 'color': Colors.grey};
    }
  }
}
