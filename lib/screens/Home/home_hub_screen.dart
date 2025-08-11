import 'package:flutter/material.dart';
import 'package:orgami/Screens/Home/home_screen.dart' as legacy;
import 'package:orgami/firebase/organization_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  int _tabIndex = 0; // 0: Public, 1: Orgs
  final TextEditingController _searchCtlr = TextEditingController();
  bool _searching = false;
  List<Map<String, String>> _myOrgs = [];
  List<Map<String, dynamic>> _discoverOrgs = [];
  String? _selectedCategoryLower;
  final List<Map<String, String>> _categoryOptions = const [
    {'label': 'All', 'value': ''},
    {'label': 'Business', 'value': 'business'},
    {'label': 'Club', 'value': 'club'},
    {'label': 'School', 'value': 'school'},
    {'label': 'Sports', 'value': 'sports'},
    {'label': 'Other', 'value': 'other'},
  ];

  @override
  void initState() {
    super.initState();
    _loadOrgs();
  }

  Future<void> _loadOrgs() async {
    final helper = OrganizationHelper();
    final my = await helper.getUserOrganizationsLite();
    setState(() => _myOrgs = my);
    _discover();
  }

  Future<void> _discover() async {
    setState(() => _searching = true);
    try {
      Query query = FirebaseFirestore.instance.collection('Organizations').limit(25);
      final q = _searchCtlr.text.trim().toLowerCase();
      if (_selectedCategoryLower != null && _selectedCategoryLower!.isNotEmpty) {
        query = query.where('category_lowercase', isEqualTo: _selectedCategoryLower);
      }
      if (q.isNotEmpty) {
        final String end = q.substring(0, q.length - 1) + String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
        query = query.orderBy('name_lowercase').startAt([q]).endBefore([end]);
      } else {
        query = query.orderBy('name_lowercase');
      }
      final snap = await query.get();
      final list = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
      }).toList();
      setState(() => _discoverOrgs = list);
    } finally {
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildSegmentedTabs(),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _tabIndex == 0 ? const legacy.HomeScreen() : _buildOrgsTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Text(
            'Discover',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_tabIndex == 1) ...[
            SizedBox(
              width: 200,
              child: TextField(
                controller: _searchCtlr,
                decoration: InputDecoration(
                  hintText: 'Search organizations',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _discover(),
              ),
            ),
            IconButton(onPressed: _searching ? null : _discover, icon: const Icon(Icons.refresh)),
          ]
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    final Color primary = const Color(0xFF667EEA);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          _segButton('Public', 0, primary, Icons.public),
          _segButton('Orgs', 1, primary, Icons.apartment),
        ],
      ),
    );
  }

  Widget _segButton(String label, int idx, Color primary, IconData icon) {
    final selected = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? primary : const Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? primary : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrgsTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Organizations', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _myOrgs.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDeco(),
                        child: const Text('You have not joined any organizations yet'),
                      )
                    : SizedBox(
                        height: 110,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _myOrgs.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final org = _myOrgs[i];
                            return _pill(org['name'] ?? '', icon: Icons.apartment);
                          },
                        ),
                      ),
                const SizedBox(height: 16),
                const Text('Discover Organizations', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _buildCategoryChips(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SliverList.separated(
            itemCount: _discoverOrgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final o = _discoverOrgs[i];
              return Container(
                decoration: _cardDeco(),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.apartment)),
                  title: Text(o['name']?.toString() ?? ''),
                  subtitle: Text(o['category']?.toString() ?? 'Other'),
                ),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _categoryOptions.map((opt) {
          final selected = (_selectedCategoryLower ?? '') == (opt['value'] ?? '');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt['label'] ?? ''),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedCategoryLower = (opt['value'] ?? '').isEmpty ? null : opt['value'];
                });
                _discover();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8))],
      );

  Widget _pill(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _cardDeco(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(text),
        ],
      ),
    );
  }
}
