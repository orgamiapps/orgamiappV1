import 'package:flutter/material.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/screens/Events/chose_sign_in_methods_screen.dart';
import 'package:orgami/screens/Events/select_organization_screen.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'dart:async';

class SelectEventTypeScreen extends StatefulWidget {
  const SelectEventTypeScreen({super.key});

  @override
  State<SelectEventTypeScreen> createState() => _SelectEventTypeScreenState();
}

class _SelectEventTypeScreenState extends State<SelectEventTypeScreen> {
  bool _orgExpanded = false;
  bool _loadingOrgs = true;
  List<Map<String, String>> _orgs = const [];
  String? _selectedOrgId;
  String? _errorText;
  StreamSubscription<List<Map<String, String>>>? _orgsSub;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _orgsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    setState(() {
      _loadingOrgs = true;
      _errorText = null;
    });

    final helper = OrganizationHelper();

    // Prime with current snapshot (fast path) while also listening live
    try {
      final items = await helper.getUserOrganizationsLite();
      if (!mounted) return;
      setState(() {
        _orgs = items;
        _loadingOrgs = false;
        if (_orgs.length == 1) {
          _selectedOrgId = _orgs.first['id'];
        } else if (_orgs.every((e) => e['id'] != _selectedOrgId)) {
          _selectedOrgId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOrgs = false;
          _errorText = 'Failed to load groups';
        });
      }
    }

    // Live updates
    _orgsSub?.cancel();
    _orgsSub = helper.streamUserOrganizationsLite().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _orgs = list;
          _loadingOrgs = false;
          _errorText = null;
          if (_orgs.length == 1) {
            _selectedOrgId = _orgs.first['id'];
          } else if (_orgs.every((e) => e['id'] != _selectedOrgId)) {
            _selectedOrgId = null;
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _loadingOrgs = false;
          _errorText = 'Error receiving group updates';
        });
      },
      cancelOnError: false,
    );
  }

  void _goToOrgDateTime() {
    if (_selectedOrgId == null) return;
    RouterClass.nextScreenNormal(
      context,
      ChoseSignInMethodsScreen(
        preselectedOrganizationId: _selectedOrgId,
        forceOrganizationEvent: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _optionCard(
                        context: context,
                        title: 'Create Public Event',
                        subtitle: 'Visible to everyone on Orgami',
                        icon: Icons.public,
                        color: const Color(0xFF667EEA),
                        onTap: () {
                          RouterClass.nextScreenNormal(
                            context,
                            const ChoseSignInMethodsScreen(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _organizationOption(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'New Event',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Visible to everyone on Orgami',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _organizationOption(BuildContext context) {
    const Color color = Color(0xFF10B981);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tappable card that expands/collapses the org selector
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _orgExpanded = !_orgExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.apartment, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Organization Event',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Attach this event to one of your organizations',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _orgExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Organization',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_loadingOrgs)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_errorText != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _errorText!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadOrganizations,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  else if (_orgs.isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'You are not a member of any groups yet.',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            RouterClass.nextScreenNormal(
                              context,
                              const SelectOrganizationScreen(),
                            );
                          },
                          child: const Text('Browse or create groups'),
                        ),
                      ],
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedOrgId,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                      items: _orgs
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m['id'],
                              child: Text(m['name'] ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedOrgId = value),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectedOrgId == null
                              ? null
                              : _goToOrgDateTime,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          crossFadeState: _orgExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}
