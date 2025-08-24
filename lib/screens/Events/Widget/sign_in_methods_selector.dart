import 'package:flutter/material.dart';

class SignInMethodsSelector extends StatefulWidget {
  final List<String> selectedMethods;
  final Function(List<String>) onMethodsChanged;
  final String? manualCode;
  final Function(String)? onManualCodeChanged;
  final bool isEditing;

  const SignInMethodsSelector({
    super.key,
    required this.selectedMethods,
    required this.onMethodsChanged,
    this.manualCode,
    this.onManualCodeChanged,
    this.isEditing = false,
  });

  @override
  State<SignInMethodsSelector> createState() => _SignInMethodsSelectorState();
}

class _SignInMethodsSelectorState extends State<SignInMethodsSelector>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<Map<String, dynamic>> _availableMethods = [
    {
      'id': 'geofence',
      'title': 'Geofence',
      'subtitle': 'Auto-sign-in when near event',
      'icon': Icons.location_on,
      'color': const Color(0xFFF093FB),
      'description':
          'Automatic sign-in when attendees are near the event location',
    },
    {
      'id': 'qr_code',
      'title': 'QR Code',
      'subtitle': 'Scan QR codes for quick sign-in',
      'icon': Icons.qr_code_scanner,
      'color': const Color(0xFF667EEA),
      'description': 'Attendees can scan QR codes to sign in instantly',
    },
    {
      'id': 'manual_code',
      'title': 'Manual Code',
      'subtitle': 'Enter event code manually',
      'icon': Icons.keyboard,
      'color': const Color(0xFF764BA2),
      'description': 'Attendees can enter a code to sign in',
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

  void _toggleMethod(String methodId) {
    final List<String> newMethods = List.from(widget.selectedMethods);
    if (newMethods.contains(methodId)) {
      newMethods.remove(methodId);
    } else {
      newMethods.add(methodId);
    }
    widget.onMethodsChanged(newMethods);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
              const SizedBox(height: 20),
              _buildMethodsList(),
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.login, color: Color(0xFF667EEA), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sign-In Methods',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how attendees can sign in to your event',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMethodsList() {
    return Column(
      children: _availableMethods.map((method) {
        final isSelected = widget.selectedMethods.contains(method['id']);
        return _buildMethodCard(method, isSelected);
      }).toList(),
    );
  }

  Widget _buildMethodCard(Map<String, dynamic> method, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleMethod(method['id']),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? method['color'].withOpacity(0.1)
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? method['color']
                    : Colors.grey.withOpacity(0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? method['color']
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    method['icon'],
                    color: isSelected ? Colors.white : Colors.grey[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method['title'],
                        style: TextStyle(
                          color: isSelected
                              ? method['color']
                              : const Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        method['subtitle'],
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        method['description'],
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? method['color'] : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? method['color']
                          : Colors.grey.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
