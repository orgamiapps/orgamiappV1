import 'package:flutter/material.dart';
import 'package:orgami/Screens/Home/home_screen.dart' as legacy;
import 'package:orgami/screens/Home/search_screen.dart';
import 'package:orgami/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/screens/Events/select_event_type_screen.dart';
import 'package:orgami/screens/Home/calendar_screen.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  int _tabIndex = 0; // 0: Public, 1: Private
  final TextEditingController _searchCtlr = TextEditingController();
  bool _searching = false;
  List<Map<String, String>> _myOrgs = [];
  List<Map<String, dynamic>> _discoverOrgs = [];
  String? _selectedCategoryLower;
  // Removed unused _categoryOptions (old UI)

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
      Query query = FirebaseFirestore.instance
          .collection('Organizations')
          .limit(25);
      final q = _searchCtlr.text.trim().toLowerCase();
      if (_selectedCategoryLower != null &&
          _selectedCategoryLower!.isNotEmpty) {
        query = query.where(
          'category_lowercase',
          isEqualTo: _selectedCategoryLower,
        );
      }
      if (q.isNotEmpty) {
        final String end =
            q.substring(0, q.length - 1) +
            String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
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
      floatingActionButton: _tabIndex == 1 ? _buildCreateFab() : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildSimpleHeader(),
            const SizedBox(height: 12),
            _buildSegmentedTabs(),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _tabIndex == 0
                    ? const legacy.HomeScreen(showHeader: false)
                    : _buildOrgsTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateFab() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            RouterClass.nextScreenNormal(
              context,
              const SelectEventTypeScreen(),
            );
          },
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildSimpleHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Discover',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F172A), // slate-900
                        Color(0xFF667EEA), // primary accent
                      ],
                    ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    );
                  },
                  blendMode: BlendMode.srcIn,
                  child: const Text(
                    'Amazing Events',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      fontFamily: 'Roboto',
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _roundIconButton(
            icon: Icons.event,
            onTap: () {
              RouterClass.nextScreenNormal(context, const CalendarScreen());
            },
          ),
          const SizedBox(width: 8),
          _roundIconButton(
            icon: Icons.qr_code_scanner,
            onTap: () {
              RouterClass.nextScreenNormal(
                context,
                const QRScannerFlowScreen(),
              );
            },
          ),
          const SizedBox(width: 8),
          _roundIconButton(
            icon: Icons.search,
            onTap: () {
              RouterClass.nextScreenNormal(context, const SearchScreen());
            },
          ),
        ],
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(icon, color: const Color(0xFF1E293B), size: 20),
        ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _segButton('Public', 0, primary, Icons.public),
          _segButton('Private', 1, primary, Icons.diversity_3),
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
              Icon(
                icon,
                size: 18,
                color: selected ? primary : const Color(0xFF6B7280),
              ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_discoverOrgs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Organizations: ${_discoverOrgs.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ),
          Expanded(child: _orgEventsList()),
        ],
      ),
    );
  }

  // Empty state matching the Public tab's "No Events Yet" design
  Widget _buildNoEventsYet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.event_busy,
                size: 40,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Events Yet',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Events will appear here once they are created.\nCheck back soon!',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _orgEventsList() {
    if (_myOrgs.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDeco(),
          child: const Text('Join an organization to see its events here'),
        ),
      );
    }

    final List<String> orgIds = _myOrgs.map((o) => o['id']!).toList();

    // Firestore whereIn supports up to 10 items; split into chunks and merge streams.
    List<List<String>> chunks = [];
    for (var i = 0; i < orgIds.length; i += 10) {
      chunks.add(
        orgIds.sublist(i, i + 10 > orgIds.length ? orgIds.length : i + 10),
      );
    }

    return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: Future.wait(
        chunks.map(
          (chunk) => FirebaseFirestore.instance
              .collection('Events')
              .where('organizationId', whereIn: chunk)
              .limit(100)
              .get(),
        ),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildNoEventsYet();
        }

        // Merge docs, filter to upcoming, then sort by selectedDateTime
        final DateTime threshold = DateTime.now().subtract(
          const Duration(hours: 3),
        );
        final docs =
            snapshot.data!.expand((qs) => qs.docs).where((d) {
              final dt = (d.data()['selectedDateTime'] as Timestamp?)?.toDate();
              return dt == null || dt.isAfter(threshold);
            }).toList()..sort((a, b) {
              final ad =
                  (a.data()['selectedDateTime'] as Timestamp?)?.toDate() ??
                  DateTime(2100);
              final bd =
                  (b.data()['selectedDateTime'] as Timestamp?)?.toDate() ??
                  DateTime(2100);
              return ad.compareTo(bd);
            });

        if (docs.isEmpty) {
          return _buildNoEventsYet();
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final model = _eventFromMap(docs[i].id, data);
            return _eventTile(model);
          },
        );
      },
    );
  }

  Map<String, dynamic> _safe(Map<String, dynamic>? input) => input ?? {};

  dynamic _getOrDefault(
    Map<String, dynamic> map,
    String key,
    dynamic fallback,
  ) {
    return map.containsKey(key) ? map[key] : fallback;
  }

  EventModel _eventFromMap(String id, Map<String, dynamic>? raw) {
    final map = _safe(raw);
    return EventModel(
      id: id,
      groupName: _getOrDefault(map, 'groupName', ''),
      title: _getOrDefault(map, 'title', ''),
      description: _getOrDefault(map, 'description', ''),
      location: _getOrDefault(map, 'location', ''),
      customerUid: _getOrDefault(map, 'customerUid', ''),
      imageUrl: _getOrDefault(map, 'imageUrl', ''),
      selectedDateTime:
          (_getOrDefault(map, 'selectedDateTime', null) as Timestamp?)
              ?.toDate() ??
          DateTime.now(),
      eventGenerateTime:
          (_getOrDefault(map, 'eventGenerateTime', null) as Timestamp?)
              ?.toDate() ??
          DateTime.now(),
      status: _getOrDefault(map, 'status', ''),
      getLocation: _getOrDefault(map, 'getLocation', true) == true,
      radius: (_getOrDefault(map, 'radius', 0) as num).toDouble(),
      longitude: (_getOrDefault(map, 'longitude', 0) as num).toDouble(),
      latitude: (_getOrDefault(map, 'latitude', 0) as num).toDouble(),
      private: _getOrDefault(map, 'private', false) == true,
      categories: List<String>.from(_getOrDefault(map, 'categories', const [])),
      eventDuration: _getOrDefault(map, 'eventDuration', 2),
      signInMethods: List<String>.from(
        _getOrDefault(map, 'signInMethods', const ['qr_code', 'manual_code']),
      ),
      manualCode: map['manualCode'],
      organizationId: map['organizationId'],
      accessList: List<String>.from(_getOrDefault(map, 'accessList', const [])),
    );
  }

  Widget _eventTile(EventModel model) {
    return SingleEventListViewItem(
      eventModel: model,
      onTap: () {
        RouterClass.nextScreenNormal(
          context,
          SingleEventScreen(eventModel: model),
        );
      },
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.06),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );

  // Removed unused _pill helper
}
