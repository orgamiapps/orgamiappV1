import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/screens/Events/chose_sign_in_methods_screen.dart';

class SelectOrganizationScreen extends StatefulWidget {
  const SelectOrganizationScreen({super.key});

  @override
  State<SelectOrganizationScreen> createState() =>
      _SelectOrganizationScreenState();
}

class _SelectOrganizationScreenState extends State<SelectOrganizationScreen> {
  bool _loading = true;
  List<Map<String, String>> _orgs = const [];

  @override
  void initState() {
    super.initState();
    _loadOrgs();
  }

  Future<void> _loadOrgs() async {
    final list = await OrganizationHelper().getUserOrganizationsLite();
    if (!mounted) return;
    setState(() {
      _orgs = list;
      _loading = false;
    });
    if (list.length == 1) {
      _goToDateTime(list.first['id']!);
    }
  }

  void _goToDateTime(String organizationId) {
    RouterClass.nextScreenNormal(
      context,
      ChoseSignInMethodsScreen(
        preselectedOrganizationId: organizationId,
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _orgs.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orgs.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final org = _orgs[i];
                        return _orgTile(
                          name: org['name'] ?? 'Organization',
                          onTap: () => _goToDateTime(org['id']!),
                        );
                      },
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
            'Select Organization',
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

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.apartment, size: 56, color: Color(0xFF9CA3AF)),
          SizedBox(height: 12),
          Text('You are not a member of any groups yet.'),
          SizedBox(height: 4),
          Text(
            'Create a public event or join a group to continue.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _orgTile({required String name, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apartment, color: Color(0xFF667EEA)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
