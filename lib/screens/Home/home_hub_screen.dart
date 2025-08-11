import 'package:flutter/material.dart';
import 'package:orgami/Screens/Home/home_screen.dart' as legacy;
import 'package:orgami/firebase/organization_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  int _tabIndex = 0; // 0: Public, 1: Org Events
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
          _segButton('Org Events', 1, primary, Icons.event),
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
      child: _orgEventsList(),
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
      chunks.add(orgIds.sublist(i, i + 10 > orgIds.length ? orgIds.length : i + 10));
    }

    return StreamBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      stream: Stream.fromFutures(chunks.map((chunk) => FirebaseFirestore.instance
              .collection('Events')
              .where('organizationId', whereIn: chunk)
              .orderBy('selectedDateTime', descending: false)
              .snapshots()
              .first)) ,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDeco(),
              child: const Text('No upcoming org events'),
            ),
          );
        }

        // Merge docs, map to simple list with sort
        final docs = snapshot.data!
            .expand((qs) => qs.docs)
            .toList()
            ..sort((a, b) {
              final ad = (a.data()['selectedDateTime'] as Timestamp?)?.toDate() ?? DateTime(2100);
              final bd = (b.data()['selectedDateTime'] as Timestamp?)?.toDate() ?? DateTime(2100);
              return ad.compareTo(bd);
            });

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

  dynamic _getOrDefault(Map<String, dynamic> map, String key, dynamic fallback) {
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
      selectedDateTime: (_getOrDefault(map, 'selectedDateTime', null) as Timestamp?)?.toDate() ?? DateTime.now(),
      eventGenerateTime: (_getOrDefault(map, 'eventGenerateTime', null) as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _getOrDefault(map, 'status', ''),
      getLocation: _getOrDefault(map, 'getLocation', true) == true,
      radius: (_getOrDefault(map, 'radius', 0) as num).toDouble(),
      longitude: (_getOrDefault(map, 'longitude', 0) as num).toDouble(),
      latitude: (_getOrDefault(map, 'latitude', 0) as num).toDouble(),
      private: _getOrDefault(map, 'private', false) == true,
      categories: List<String>.from(_getOrDefault(map, 'categories', const [])),
      eventDuration: _getOrDefault(map, 'eventDuration', 2),
      signInMethods: List<String>.from(_getOrDefault(map, 'signInMethods', const ['qr_code', 'manual_code'])),
      manualCode: map['manualCode'],
      organizationId: map['organizationId'],
      accessList: List<String>.from(_getOrDefault(map, 'accessList', const [])),
    );
  }

  Widget _eventTile(EventModel model) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(model.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(model.location),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Reuse legacy event item navigation
          // For simplicity, we navigate to the single event screen if available through Router
          // The SingleEventListViewItem handles this normally; here we keep it minimal.
          // You can replace this with the actual SingleEventListViewItem for richer UI.
          RouterClass.nextScreenNormal(context, SingleEventScreen(eventModel: model));
        },
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
