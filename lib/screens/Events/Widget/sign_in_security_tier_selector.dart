import 'package:flutter/material.dart';

/// Modern, professional sign-in security tier selector for event creation
/// Provides four tiers: Most Secure, Geofence Only, Regular, and All methods
class SignInSecurityTierSelector extends StatefulWidget {
  final String selectedTier; // 'most_secure', 'geofence_only', 'regular', or 'all'
  final Function(String) onTierChanged;
  final bool isEditing;

  const SignInSecurityTierSelector({
    super.key,
    required this.selectedTier,
    required this.onTierChanged,
    this.isEditing = false,
  });

  @override
  State<SignInSecurityTierSelector> createState() =>
      _SignInSecurityTierSelectorState();
}

class _SignInSecurityTierSelectorState
    extends State<SignInSecurityTierSelector> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<Map<String, dynamic>> _securityTiers = [
    {
      'id': 'most_secure',
      'title': 'Most Secure',
      'subtitle': 'Maximum security verification',
      'icon': Icons.verified_user,
      'gradient': [const Color(0xFFFF6B6B), const Color(0xFFEE5A6F)],
      'description':
          'Requires attendees to be within the geofence AND verify with facial recognition',
      'methods': [
        {'icon': Icons.location_on, 'text': 'Geofence Required'},
        {'icon': Icons.face, 'text': 'Facial Recognition Required'},
      ],
      'badge': 'RECOMMENDED',
      'badgeColor': Color(0xFFFF6B6B),
    },
    {
      'id': 'geofence_only',
      'title': 'Geofence Only',
      'subtitle': 'Location-based verification',
      'icon': Icons.my_location,
      'gradient': [const Color(0xFFF093FB), const Color(0xFFF5576C)],
      'description':
          'Attendees can sign in when they are within the event geofence location',
      'methods': [
        {'icon': Icons.location_on, 'text': 'Geofence'},
      ],
      'badge': null,
      'badgeColor': null,
    },
    {
      'id': 'regular',
      'title': 'Regular',
      'subtitle': 'Standard verification methods',
      'icon': Icons.qr_code_2,
      'gradient': [const Color(0xFF667EEA), const Color(0xFF764BA2)],
      'description':
          'Attendees can sign in using QR code scanning or by entering a manual code',
      'methods': [
        {'icon': Icons.qr_code_scanner, 'text': 'QR Code'},
        {'icon': Icons.keyboard, 'text': 'Manual Code'},
      ],
      'badge': null,
      'badgeColor': null,
    },
    {
      'id': 'all',
      'title': 'All Methods',
      'subtitle': 'Maximum flexibility',
      'icon': Icons.all_inclusive,
      'gradient': [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      'description':
          'All sign-in methods available: secure biometric combo OR QR/manual codes',
      'methods': [
        {'icon': Icons.location_on, 'text': 'Geofence + Face ID'},
        {'icon': Icons.qr_code_scanner, 'text': 'QR Code'},
        {'icon': Icons.keyboard, 'text': 'Manual Code'},
      ],
      'badge': 'FLEXIBLE',
      'badgeColor': Color(0xFF11998E),
    },
  ];

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
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _selectTier(String tierId) {
    // Haptic feedback would be nice here
    widget.onTierChanged(tierId);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildTiersList(),
              const SizedBox(height: 10),
              _buildInfoNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.security, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sign-In Security',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Choose how attendees verify their attendance',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTiersList() {
    return Column(
      children: _securityTiers.map((tier) {
        final isSelected = widget.selectedTier == tier['id'];
        return _buildTierCard(tier, isSelected);
      }).toList(),
    );
  }

  Widget _buildTierCard(Map<String, dynamic> tier, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _selectTier(tier['id']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        tier['gradient'][0].withValues(alpha: 0.1),
                        tier['gradient'][1].withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? tier['gradient'][0]
                    : Colors.grey.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color:
                            tier['gradient'][0].withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge row at the top
                if (tier['badge'] != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tier['badgeColor'].withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: tier['badgeColor'].withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          tier['badge'],
                          style: TextStyle(
                            color: tier['badgeColor'],
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (tier['badge'] != null) const SizedBox(height: 8),
                // Main content row
                Row(
                  children: [
                    // Icon with gradient
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: tier['gradient'],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: tier['gradient'][0]
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        tier['icon'],
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier['title'],
                            style: TextStyle(
                              color: isSelected
                                  ? tier['gradient'][0]
                                  : const Color(0xFF1A1A1A),
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              fontFamily: 'Roboto',
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tier['subtitle'],
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Selection indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: tier['gradient'],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected ? null : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? tier['gradient'][0]
                              : Colors.grey.withValues(alpha: 0.4),
                          width: 2,
                            ),
                          ),
                          child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  tier['description'],
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 11,
                    height: 1.3,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 8),
                // Methods list
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (tier['methods'] as List).map((method) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tier['gradient'][0].withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isSelected
                              ? tier['gradient'][0].withValues(alpha: 0.3)
                              : Colors.grey.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            method['icon'],
                            size: 14,
                            color: isSelected
                                ? tier['gradient'][0]
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              method['text'],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? tier['gradient'][0]
                                    : Colors.grey[700],
                                fontFamily: 'Roboto',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: const Color(0xFF667EEA),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security Tips',
                  style: TextStyle(
                    color: const Color(0xFF667EEA),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Most Secure is recommended for high-value events. Attendees must be physically present within the event geofence and verify their identity with facial recognition.',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 11,
                    height: 1.3,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

