import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:attendus/screens/Home/home_screen.dart' as legacy;
import 'package:attendus/screens/Home/search_screen.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Home/calendar_screen.dart';
import 'package:attendus/Utils/firebase_retry_helper.dart';
import 'package:attendus/screens/Events/global_events_map_screen.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class HomeHubScreen extends StatefulWidget {
  final bool? _guestModeOverride;
  final Widget? _publicContentOverride;
  final Widget? _privateContentOverride;
  final bool _loadDiscoveryData;

  const HomeHubScreen({super.key})
    : _guestModeOverride = null,
      _publicContentOverride = null,
      _privateContentOverride = null,
      _loadDiscoveryData = true;

  @visibleForTesting
  const HomeHubScreen.test({
    super.key,
    required bool isGuestMode,
    required Widget publicContent,
    Widget? privateContent,
  }) : _guestModeOverride = isGuestMode,
       _publicContentOverride = publicContent,
       _privateContentOverride = privateContent,
       _loadDiscoveryData = false;

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
  String? _discoverError;
  // Removed unused _categoryOptions (old UI)

  @override
  void initState() {
    super.initState();
    Logger.debug('🏠 HomeHubScreen: initState started');
    // PERFORMANCE FIX: Defer data loading to after first frame to prevent blocking
    // This prevents the heavy Firestore query from blocking app startup
    if (widget._loadDiscoveryData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadOrgs();
        }
      });
    }
    Logger.debug('🏠 HomeHubScreen: initState finished');
  }

  Future<void> _loadOrgs() async {
    if (!mounted) return;
    Logger.debug('🏠 HomeHubScreen: _loadOrgs started');

    try {
      // Set initial empty state for immediate UI render
      if (mounted) {
        setState(() {
          _myOrgs = [];
          _searching = true; // Show loading indicator
          _discoverError = null;
        });
      }

      // Defer discover query slightly to allow UI to render first
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        Logger.debug('🏠 HomeHubScreen: Starting _discover...');
        _discover();
      }

      // Load user orgs in background after discover starts
      _loadUserOrgsInBackground();
    } catch (e) {
      Logger.error('Error in _loadOrgs', e);
      if (mounted) {
        setState(() {
          _myOrgs = [];
          _searching = false;
        });
      }
    }
  }

  /// Load user organizations in background after initial UI render
  void _loadUserOrgsInBackground() {
    // OPTIMIZATION: Reduced delay from 2s to 1s for faster user org loading
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;

      try {
        Logger.debug('🏠 HomeHubScreen: Loading user orgs in background...');
        final helper = OrganizationHelper();

        final my = await helper.getUserOrganizationsLite();

        Logger.debug(
          '🏠 HomeHubScreen: Background load completed, got ${my.length} orgs',
        );

        if (mounted && my.isNotEmpty) {
          setState(() => _myOrgs = my);
          Logger.debug(
            '🏠 HomeHubScreen: Background state updated with user orgs',
          );
        }
      } catch (e) {
        Logger.error('Error loading user orgs in background', e);
      }
    });
  }

  Future<void> _discover() async {
    if (!mounted) return;
    Logger.debug('🏠 HomeHubScreen: _discover started');

    setState(() => _searching = true);
    try {
      Logger.debug('🏠 HomeHubScreen: Creating Firestore query...');
      Query query = FirebaseFirestore.instance
          .collection('Organizations')
          .limit(
            20,
          ); // OPTIMIZATION: Increased from 10 to 20 for better initial content

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

      Logger.debug('🏠 HomeHubScreen: Executing Firestore query...');
      final snap = await FirebaseRetryHelper.executeQueryWithRetry(
        query,
        timeout: const Duration(seconds: 10),
        operationName: 'Organizations discovery',
      );

      Logger.debug(
        '🏠 HomeHubScreen: Query completed, got ${snap.docs.length} organizations',
      );

      final list = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _discoverOrgs = list;
          _discoverError = null;
        });
        Logger.debug('🏠 HomeHubScreen: State updated with discovered orgs');
      }
    } catch (e) {
      Logger.error('❌ ERROR: Error discovering organizations');
      Logger.error('Error details: $e');
      if (mounted) {
        setState(() {
          _discoverOrgs = [];
          _discoverError = FirebaseRetryHelper.getUserFriendlyErrorMessage(e);
        });
      }
      // Show user-friendly error message
      final errorMessage = FirebaseRetryHelper.getUserFriendlyErrorMessage(e);
      Logger.info('User-friendly error: $errorMessage');
    } finally {
      if (mounted) {
        setState(() => _searching = false);
        Logger.debug('🏠 HomeHubScreen: _discover completed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuestMode = _isGuestMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _tabIndex == 1 ? _buildCreateFab() : null,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AttendUsTokens.pageMaxWidth,
            ),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: _buildDiscoveryHeader(isGuestMode: isGuestMode),
                ),
                if (isGuestMode) SliverToBoxAdapter(child: _buildGuestBanner()),
                if (!isGuestMode)
                  SliverToBoxAdapter(child: _buildSegmentedTabs()),
              ],
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: (_tabIndex == 0 || isGuestMode)
                    ? (widget._publicContentOverride ??
                          const legacy.HomeScreen(
                            key: ValueKey('public-events'),
                            showHeader: false,
                            coordinateWithParentScroll: true,
                          ))
                    : KeyedSubtree(
                        key: const ValueKey('private-groups'),
                        child:
                            widget._privateContentOverride ?? _buildOrgsTab(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateFab() {
    final isGuestMode = _isGuestMode;
    final theme = Theme.of(context);

    return FloatingActionButton.extended(
      onPressed: () {
        if (isGuestMode) {
          _showGuestRestrictionDialog(GuestFeature.createEvent);
        } else {
          RouterClass.nextScreenNormal(
            context,
            const PremiumEventCreationWrapper(),
          );
        }
      },
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      icon: const Icon(Icons.add),
      label: const Text('Create event'),
    );
  }

  Widget _buildDiscoveryHeader({required bool isGuestMode}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildQuickActionRow(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AttendUsStatusBadge(
                    label: isGuestMode ? 'Guest discovery' : 'Signed in',
                    tone: isGuestMode
                        ? AttendUsStatusTone.warning
                        : AttendUsStatusTone.success,
                    icon: isGuestMode
                        ? Icons.visibility_outlined
                        : Icons.verified_user_outlined,
                  ),
                  AttendUsStatusBadge(
                    label: _tabIndex == 0 || isGuestMode
                        ? 'Public events'
                        : 'Private groups',
                    tone: AttendUsStatusTone.info,
                    icon: _tabIndex == 0 || isGuestMode
                        ? Icons.public
                        : Icons.apartment_outlined,
                  ),
                  if (_discoverError != null)
                    AttendUsStatusBadge(
                      label: 'Discovery limited',
                      tone: AttendUsStatusTone.danger,
                      icon: Icons.cloud_off_outlined,
                    ),
                ],
              ),
              if (_discoverError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _discoverError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActionRow() {
    final actions = [
      _DiscoveryQuickAction(
        key: const ValueKey('discover-shortcut-search'),
        icon: Icons.search,
        title: 'Search',
        tone: AttendUsStatusTone.info,
        onTap: () {
          RouterClass.nextScreenNormal(context, const SearchScreen());
        },
      ),
      _DiscoveryQuickAction(
        key: const ValueKey('discover-shortcut-map'),
        icon: Icons.public,
        title: 'Map',
        tone: AttendUsStatusTone.info,
        onTap: () {
          RouterClass.nextScreenNormal(context, const GlobalEventsMapScreen());
        },
      ),
      _DiscoveryQuickAction(
        key: const ValueKey('discover-shortcut-check-in'),
        icon: Icons.fact_check_outlined,
        title: 'Check in',
        tone: AttendUsStatusTone.success,
        onTap: () {
          RouterClass.nextScreenNormal(context, const QRScannerFlowScreen());
        },
      ),
      _DiscoveryQuickAction(
        key: const ValueKey('discover-shortcut-calendar'),
        icon: Icons.calendar_month_outlined,
        title: 'Calendar',
        tone: AttendUsStatusTone.warning,
        onTap: () {
          RouterClass.nextScreenNormal(context, const CalendarScreen());
        },
      ),
      _DiscoveryQuickAction(
        key: const ValueKey('discover-shortcut-create'),
        icon: Icons.add_circle_outline,
        title: 'Create',
        tone: AttendUsStatusTone.neutral,
        onTap: () {
          if (_isGuestMode) {
            _showGuestRestrictionDialog(GuestFeature.createEvent);
          } else {
            RouterClass.nextScreenNormal(
              context,
              const PremiumEventCreationWrapper(),
            );
          }
        },
      ),
    ];

    return SizedBox(
      key: const ValueKey('discover-shortcut-row'),
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            SizedBox(width: 112, child: actions[index]),
      ),
    );
  }

  bool get _isGuestMode =>
      widget._guestModeOverride ?? GuestModeService().isGuestMode;

  Widget _buildSegmentedTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AttendUsFilterChipGroup<int>(
        multiSelect: false,
        selectedValues: {_tabIndex},
        options: const [
          AttendUsFilterOption(
            value: 0,
            label: 'Public events',
            icon: Icons.public,
          ),
          AttendUsFilterOption(
            value: 1,
            label: 'Private groups',
            icon: Icons.apartment_outlined,
          ),
        ],
        onChanged: (values) {
          if (values.isEmpty) return;
          setState(() => _tabIndex = values.first);
        },
      ),
    );
  }

  Widget _buildOrgsTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttendUsPageSection(
            title: 'Private group events',
            subtitle: _discoverOrgs.isEmpty
                ? 'Upcoming events from organizations you belong to.'
                : '${_discoverOrgs.length} public groups available for discovery.',
            icon: Icons.apartment_outlined,
            framed: true,
            padding: const EdgeInsets.all(16),
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _orgEventsList()),
        ],
      ),
    );
  }

  Widget _buildNoEventsYet() {
    return AttendUsEmptyState(
      icon: Icons.event_busy_outlined,
      title: 'No events yet',
      message:
          'Private group events will appear here after your organizations publish them.',
    );
  }

  Widget _orgEventsList() {
    if (_myOrgs.isEmpty) {
      return AttendUsEmptyState(
        icon: Icons.apartment_outlined,
        title: 'Join a group',
        message: 'Join an organization to see its private events here.',
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
          return const AttendUsLoadingState(label: 'Loading group events');
        }
        if (snapshot.hasError) {
          return AttendUsEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Events unavailable',
            message: 'Attendus could not load private group events right now.',
            action: AttendUsButton.secondary(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: () => setState(() {}),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildNoEventsYet();
        }

        final DateTime now = DateTime.now();
        final DateTime cutoffTime = now.subtract(const Duration(hours: 3));

        final docs =
            snapshot.data!.expand((qs) => qs.docs).where((d) {
              final data = d.data();
              final startTime = (data['selectedDateTime'] as Timestamp?)
                  ?.toDate();

              if (startTime == null) {
                return false;
              }

              final eventDuration =
                  (data['eventDuration'] as num?)?.toInt() ?? 2;
              final eventEndTime = startTime.add(
                Duration(hours: eventDuration),
              );

              return eventEndTime.isAfter(cutoffTime);
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

        final events = docs
            .map((doc) => _eventFromMap(doc.id, doc.data()))
            .toList(growable: false);

        return _PrivateEventsGrid(
          events: events,
          onOpenEvent: (model) {
            RouterClass.nextScreenNormal(
              context,
              SingleEventScreen(eventModel: model),
            );
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

  /// Build guest mode banner with account creation CTA
  Widget _buildGuestBanner() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AttendUsCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AttendUsStatusBadge(
              label: 'Guest',
              tone: AttendUsStatusTone.warning,
              icon: Icons.visibility_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Create an account to create events, join groups, and access private attendance tools.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            AttendUsButton.primary(
              label: 'Sign up',
              onPressed: () {
                RouterClass.nextScreenNormal(
                  context,
                  const CreateAccountScreen(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Show dialog explaining guest mode restrictions
  void _showGuestRestrictionDialog(GuestFeature feature) {
    final message = GuestModeService().getFeatureRestrictionMessage(feature);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFF667EEA),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Account Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_add_outlined,
              size: 64,
              color: Color(0xFF667EEA),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF10B981),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free account with instant access',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF10B981),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Create events, join groups & more',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              RouterClass.nextScreenNormal(
                context,
                const CreateAccountScreen(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Create Account',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryQuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final AttendUsStatusTone tone;
  final VoidCallback onTap;

  const _DiscoveryQuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AttendUsStatusBadge(label: '', icon: icon, tone: tone),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PrivateEventsGrid extends StatelessWidget {
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpenEvent;

  const _PrivateEventsGrid({required this.events, required this.onOpenEvent});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 680) {
          return ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _EventSummary(
              event: events[index],
              onTap: () => onOpenEvent(events[index]),
            ),
          );
        }

        final crossAxisCount = width >= 1040 ? 3 : 2;
        return GridView.builder(
          itemCount: events.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 320,
          ),
          itemBuilder: (context, index) => _EventSummary(
            event: events[index],
            onTap: () => onOpenEvent(events[index]),
          ),
        );
      },
    );
  }
}

class _EventSummary extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _EventSummary({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AttendUsEventSummaryCard(
      title: event.title.isEmpty ? 'Untitled event' : event.title,
      subtitle: event.groupName.isEmpty ? event.description : event.groupName,
      imageUrl: event.imageUrl,
      dateLabel: DateFormat('MMM d, h:mm a').format(event.selectedDateTime),
      locationLabel: event.location.isEmpty ? 'Location TBD' : event.location,
      statusLabel: event.private ? 'Private' : 'Public',
      onTap: onTap,
    );
  }
}
