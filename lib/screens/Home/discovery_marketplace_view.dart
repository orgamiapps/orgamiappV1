import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Services/discovery_history_coordinator.dart';
import 'package:attendus/models/discovery_route_state.dart';
import 'dart:async';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/discovery_location_service.dart';
import 'package:attendus/Services/discovery_marketplace_service.dart';
import 'package:attendus/Services/places_service.dart';
import 'package:attendus/Services/product_funnel_service.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/models/discovery_marketplace.dart';
import 'package:attendus/models/discovery_category.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

int resolveActiveDiscoveryExperience(
  int configuredVersion,
  int? schemaVersion,
) {
  if (configuredVersion != 2) return 1;
  return schemaVersion == null || schemaVersion == 2 ? 2 : 1;
}

class DiscoveryMarketplaceView extends StatefulWidget {
  final int experienceVersion;
  final DiscoveryLocationService? locationService;

  const DiscoveryMarketplaceView({
    super.key,
    this.experienceVersion = 1,
    this.locationService,
  });

  @override
  State<DiscoveryMarketplaceView> createState() =>
      _DiscoveryMarketplaceViewState();
}

class _DiscoveryMarketplaceViewState extends State<DiscoveryMarketplaceView> {
  DiscoveryHistoryCoordinator? _history;
  final _discoveryScroll = ScrollController(keepScrollOffset: false);
  final _feedCache =
      <String, (List<DiscoveryEvent>, String?, int?, DiscoveryHomeResult?)>{};

  DiscoveryRouteState _routeSnapshot() => DiscoveryRouteState({
    'distanceMode': _fixedMiles == null ? 'auto' : 'fixed',
    if (_fixedMiles != null) 'radius': _fixedMiles.toString(),
    'q': _searchController.text,
    'date': _datePreset ?? '',
    'free': _freeOnly ? '1' : '',
    'online': _onlineOnly ? '1' : '',
    'browse': _browseAll ? '1' : '',
    'category': _selectedCategoryId ?? '',
    if (_location != null) ...{
      'lat': _location!.latitude.toString(),
      'lng': _location!.longitude.toString(),
      'city': _location!.city,
      'region': _location!.regionCode,
      'nationwide': _location!.nationwide ? '1' : '',
    },
  });

  Future<void> _restoreRoute(DiscoveryRouteState route) async {
    if (!mounted) return;
    _debounce?.cancel();
    _requestGeneration++;
    setState(() {
      if (route['distanceMode'] != null || route['radius'] != null) {
        _fixedMiles = route['distanceMode'] == 'auto'
            ? null
            : int.tryParse(route['radius'] ?? '25');
        if (![5, 10, 25, 50, 100].contains(_fixedMiles)) _fixedMiles = null;
      }
      _searchController.text = route['q'] ?? '';
      _datePreset = route['date'];
      _freeOnly = route.enabled('free');
      _onlineOnly = route.enabled('online');
      _browseAll = route.enabled('browse');
      _selectedCategoryId = route['category'];
      if (route['lat'] != null || route.enabled('nationwide')) {
        _location = DiscoveryLocation(
          latitude: double.tryParse(route['lat'] ?? '') ?? 0,
          longitude: double.tryParse(route['lng'] ?? '') ?? 0,
          city: route['city'] ?? 'Selected area',
          regionCode: route['region'] ?? '',
          source: 'shared_link',
          nationwide: route.enabled('nationwide'),
        );
      }
      _location ??= const DiscoveryLocation(
        latitude: 0,
        longitude: 0,
        city: 'United States',
        regionCode: 'US',
        source: 'shared_link',
        nationwide: true,
      );
    });
    final cached = _feedCache[route.uri.toString()];
    if (cached != null) {
      setState(() {
        _feedEvents = cached.$1;
        _feedCursor = cached.$2;
        _resolvedMiles = cached.$3;
        _home = cached.$4;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } else {
      await _loadHome();
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _history?.schedule();
  }

  final _marketplace = DiscoveryMarketplaceService();
  late final _locations = widget.locationService ?? DiscoveryLocationService();
  bool _locationOnboardingPending = false;
  bool _locationOnboardingShowing = false;

  bool get _isForeground =>
      mounted &&
      (ModalRoute.isCurrentOf(context) ?? false) &&
      TickerMode.valuesOf(context).enabled;

  final _searchController = TextEditingController();
  DiscoveryLocation? _location;
  DiscoveryHomeResult? _home;
  Set<String> _savedIds = {};
  bool _loading = true;
  String? _error;
  String? _datePreset;
  bool _freeOnly = false;
  bool _onlineOnly = false;
  String? _selectedCategoryId;
  List<String> _interests = const [];
  Timer? _debounce;
  int _requestGeneration = 0;
  final Set<String> _recordedCategoryNoResults = {};
  bool _browseAll = false;
  bool _loadingMore = false;
  int get _activeExperienceVersion => resolveActiveDiscoveryExperience(
    widget.experienceVersion,
    _home?.schemaVersion,
  );

  // The shared shell keeps notification access visible at every breakpoint.
  // Retain the page action when Discover is used outside that shell.
  bool get _showNotificationButton =>
      context
          .findAncestorWidgetOfExactType<AttendUsScaffold>()
          ?.onNotificationsPressed ==
      null;

  bool get _searchMode =>
      _searchController.text.trim().isNotEmpty ||
      _browseAll ||
      (_activeExperienceVersion == 1 &&
          (_datePreset != null || _freeOnly || _onlineOnly));

  Future<void> _refreshForQuickChoice(String choice) async {
    ProductFunnelService().record(
      'discovery_quick_choice_selected',
      dimensions: {
        'choice': choice,
        'experienceVersion': _activeExperienceVersion.toString(),
      },
    );
    if (_activeExperienceVersion == 2 &&
        _searchController.text.trim().isEmpty &&
        !_browseAll) {
      await _loadHome();
    } else {
      await _runSearch();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route/tab visibility and defer presentation until the event
    // or login route above Discover has closed.
    final foreground = _isForeground;
    if (foreground) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _offerLocationWhenVisible(),
      );
    }
  }

  Future<void> _offerLocationWhenVisible() async {
    if (!_locationOnboardingPending ||
        _locationOnboardingShowing ||
        !_isForeground) {
      return;
    }
    _locationOnboardingPending = false;
    _locationOnboardingShowing = true;
    try {
      await _showLocationOnboarding();
    } finally {
      _locationOnboardingShowing = false;
    }
  }

  @override
  void dispose() {
    _history?.dispose();
    _discoveryScroll.dispose();
    _carouselScroll.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _fixedMiles = preferences.getInt('discovery_fixed_miles');
    if (![5, 10, 25, 50, 100].contains(_fixedMiles)) _fixedMiles = null;
    _interests = await _locations.loadInterests();
    final cached = await _locations.load();
    if (!mounted) return;
    _location = cached;
    _history = DiscoveryHistoryCoordinator(
      snapshot: _routeSnapshot,
      restore: _restoreRoute,
      scrollController: () => _discoveryScroll,
      isActive: () => _isForeground,
    );
    _discoveryScroll.addListener(() => _history?.scheduleScroll());
    await _history!.initialize();
    if (_home != null) return;
    if (_location == null) {
      setState(() => _loading = false);
      _locationOnboardingPending = true;
      await _offerLocationWhenVisible();
      return;
    }
    if (_searchMode) {
      await _runSearch();
    } else {
      await _loadHome();
    }
  }

  Future<void> _showLocationOnboarding() async {
    if (!_isForeground) return;
    final useLocation = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.near_me_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Find events near you',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Attendus uses your location to show relevant local events. Your precise coordinates are never stored in analytics.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              AttendUsButton.primary(
                label: 'Use my location',
                icon: Icons.my_location,
                onPressed: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Choose a city or ZIP code'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    ProductFunnelService().record(
      'discovery_location_prompt',
      dimensions: {
        'result': useLocation == true ? 'device_requested' : 'manual_selected',
      },
    );
    if (useLocation == true) {
      if (mounted) setState(() => _loading = true);
      try {
        final device = await _locations.useDeviceLocation();
        if (device != null) {
          _location = device;
          await _offerInterests();
          await _loadHome();
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
    }
    await _chooseCity();
  }

  Future<void> _chooseCity() async {
    final selection = await showDialog<PlaceDetails>(
      context: context,
      barrierDismissible: _location != null,
      builder: (_) => const _DiscoveryCityDialog(),
    );
    if (selection != null) {
      _location = await _locations.usePlace(selection);
      ProductFunnelService().record(
        'discovery_location_result',
        dimensions: {'result': 'selected', 'source': 'search'},
      );
      await _offerInterests();
      await _loadHome();
      return;
    }
    if (_location == null) {
      _location = await _locations.useNationwide();
      ProductFunnelService().record(
        'discovery_location_result',
        dimensions: {'result': 'nationwide', 'source': 'nationwide'},
      );
      await _offerInterests();
      await _loadHome();
    }
  }

  int? _fixedMiles;
  int? _resolvedMiles;
  String? _feedCursor;
  List<DiscoveryEvent> _feedEvents = [];
  final _carouselScroll = ScrollController();

  Map<String, dynamic> get _feedFilters => {
    // Match shareable URL precision so restored cursors keep their identity.
    'latitude': double.parse((_location?.latitude ?? 0).toStringAsFixed(2)),
    'longitude': double.parse((_location?.longitude ?? 0).toStringAsFixed(2)),
    'nationwide': _location == null || _location!.nationwide,
    'distanceMode': _fixedMiles == null ? 'auto' : 'fixed',
    'radiusMiles': _fixedMiles ?? 25,
    'query': _searchController.text.trim(),
    'categoryId': ?_selectedCategoryId,
    'datePreset': ?_datePreset,
    'freeOnly': _freeOnly,
    'onlineOnly': _onlineOnly,
  };

  void _rememberFeed() {
    if (_feedCache.length >= 12) _feedCache.remove(_feedCache.keys.first);
    _feedCache[_routeSnapshot().uri.toString()] = (
      _feedEvents,
      _feedCursor,
      _resolvedMiles,
      _home,
    );
  }

  Future<Map<String, dynamic>> _readFeedPage(
    Map<String, dynamic> filters,
    int generation, {
    String? cursor,
  }) async {
    final events = <dynamic>[];
    Map<String, dynamic> result;
    do {
      result = await _marketplace.feed({
        ...filters,
        'limit': 20 - events.length,
      }, cursor: cursor);
      if (!mounted || generation != _requestGeneration) return result;
      events.addAll(result['events'] as List? ?? const []);
      cursor = result['nextCursor'] as String?;
      if (cursor != null && events.length < 20) {
        // Sparse scans can require many calls. Stay below the anonymous rate
        // limit while keeping the operation cancellable when filters change.
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted || generation != _requestGeneration) return result;
      }
    } while (cursor != null && events.length < 20);
    return {...result, 'events': events};
  }

  Future<void> _loadHome() async {
    final generation = ++_requestGeneration;
    if (_location == null || _location!.nationwide) _fixedMiles = null;
    final filters = _feedFilters;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _feedEvents = [];
      _feedCursor = null;
      _home = null;
    });
    try {
      final result = await _readFeedPage(filters, generation);
      if (!mounted || generation != _requestGeneration) return;
      final cursor = result['nextCursor'] as String?;
      final saved = await _marketplace.savedEventIds();
      if (!mounted || generation != _requestGeneration) return;
      final ids = <String>{};
      final events = DiscoverySearchResult.fromMap(
        result,
      ).events.where((e) => ids.add(e.event.id)).toList();
      final recommendations = [...events]
        ..sort((a, b) {
          int relevance(DiscoveryEvent item) => item.event.categories
              .where(
                (c) => _interests.any(
                  (interest) => interest.toLowerCase() == c.toLowerCase(),
                ),
              )
              .length;
          final compared = relevance(b).compareTo(relevance(a));
          return compared != 0
              ? compared
              : events.indexOf(a).compareTo(events.indexOf(b));
        });
      setState(() {
        _feedEvents = events;
        _feedCursor = cursor;
        _resolvedMiles = (result['radiusMiles'] as num?)?.toInt();
        _savedIds = saved;
        _loading = false;
        _home = DiscoveryHomeResult(
          sections: [
            DiscoverySection(
              id: 'recommended',
              title: 'For you',
              subtitle: '',
              featured: false,
              events: recommendations.take(12).toList(),
            ),
          ],
          radiusMiles: _resolvedMiles ?? 25,
          expandedRadius: (_resolvedMiles ?? 25) > 25,
          localResultCount: events.length,
          schemaVersion: 2,
        );
      });
      _rememberFeed();
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _loadMoreSearchResults() async {
    if (_feedCursor == null || _loadingMore) return;
    final generation = _requestGeneration;
    final cursor = _feedCursor!;
    setState(() => _loadingMore = true);
    try {
      final result = await _readFeedPage(
        _feedFilters,
        generation,
        cursor: cursor,
      );
      if (!mounted || generation != _requestGeneration) return;
      final ids = _feedEvents.map((e) => e.event.id).toSet();
      setState(() {
        _feedEvents = [
          ..._feedEvents,
          ...DiscoverySearchResult.fromMap(
            result,
          ).events.where((e) => ids.add(e.event.id)),
        ];
        _feedCursor = result['nextCursor'] as String?;
        _loadingMore = false;
      });
      _rememberFeed();
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load more events. Please try again.'),
        ),
      );
    }
  }

  Future<void> _offerInterests() async {
    if (!mounted || _interests.isNotEmpty) return;
    const options = [
      'Music',
      'Business',
      'Community',
      'Food & Drink',
      'Arts',
      'Sports',
      'Technology',
      'Wellness',
    ];
    final chosen = <String>{};
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What are you interested in?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Optional — choose a few to personalize your Discovery page.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options
                      .map(
                        (option) => FilterChip(
                          label: Text(option),
                          selected: chosen.contains(option),
                          onSelected: (selected) => update(
                            () => selected
                                ? chosen.add(option)
                                : chosen.remove(option),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                AttendUsButton.primary(
                  label: chosen.isEmpty ? 'Skip for now' : 'Continue',
                  onPressed: () => Navigator.pop(context, chosen.toList()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      _interests = result;
      await _locations.saveInterests(result);
    }
  }

  void _scheduleSearch() {
    _requestGeneration++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() => _loadHome();

  Future<void> _toggleSave(DiscoveryEvent item) async {
    if (AccountAccessService.isGuest) {
      await showAccountRequiredSheet(
        context: context,
        feature: AccountFeature.favorites,
        saveEventId: item.event.id,
      );
      return;
    }
    final next = !_savedIds.contains(item.event.id);
    setState(
      () =>
          next ? _savedIds.add(item.event.id) : _savedIds.remove(item.event.id),
    );
    try {
      await _marketplace.setSaved(item.event.id, next);
      ProductFunnelService().record(
        'discovery_save',
        dimensions: {'result': next ? 'saved' : 'removed'},
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => next
              ? _savedIds.remove(item.event.id)
              : _savedIds.add(item.event.id),
        );
      }
    }
  }

  void _openEvent(DiscoveryEvent item, String section, int position) {
    unawaited(
      _marketplace.recordBehavior(
        categories: item.event.categories,
        organizerId: item.event.customerUid,
      ),
    );
    ProductFunnelService().record(
      'discovery_card_open',
      dimensions: {
        'section': section,
        'position': position.toString(),
        'radiusBand': (_home?.radiusMiles ?? 100).toString(),
        'category': item.event.categories.firstOrNull ?? 'uncategorized',
      },
    );
    _history?.flush();
    _history?.saveScroll();
    Navigator.of(
      context,
    ).pushNamed('/app/event/${Uri.encodeComponent(item.event.id)}');
  }

  void _createEvent() {
    ProductFunnelService().record('discovery_organizer_create_cta');
    if (AccountAccessService.isGuest) {
      showAccountRequiredSheet(
        context: context,
        feature: AccountFeature.createEvent,
      );
    } else {
      RouterClass.nextScreenNormal(
        context,
        const PremiumEventCreationWrapper(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _buildV2(context);

  Widget _buildV2(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _searchMode ? _runSearch : _loadHome,
      child: CustomScrollView(
        key: const PageStorageKey('discovery-marketplace-v2'),
        controller: _discoveryScroll,
        slivers: [
          SliverToBoxAdapter(child: _v2Header(context)),
          SliverToBoxAdapter(child: _distanceHeading()),
          if (_loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_error != null)
            SliverToBoxAdapter(child: _errorState())
          else ...[
            if (_feedEvents.isNotEmpty)
              SliverToBoxAdapter(child: _recommendations()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  children: [
                    Text(
                      'Upcoming events',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: _createEvent,
                      child: const Text('+ Create event'),
                    ),
                  ],
                ),
              ),
            ),
            if (_feedEvents.isEmpty && _feedCursor == null)
              SliverToBoxAdapter(child: _v2EmptyState()),
            SliverList.builder(
              itemCount: _feedEvents.length,
              itemBuilder: (_, index) =>
                  _upcomingCard(_feedEvents[index], index),
            ),
            if (_feedCursor != null)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: OutlinedButton(
                      onPressed: _loadingMore ? null : _loadMoreSearchResults,
                      child: Text(
                        _loadingMore ? 'Loading events' : 'Load more',
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _v2Header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _locationButton()),
              if (_showNotificationButton)
                IconButton(
                  tooltip: 'Notifications',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () {
                    if (AccountAccessService.isGuest) {
                      showAccountRequiredSheet(
                        context: context,
                        feature: AccountFeature.notifications,
                      );
                    } else {
                      RouterClass.nextScreenNormal(
                        context,
                        const NotificationsScreen(),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_none),
                ),
            ],
          ),
          if (_home?.cacheState == 'stale') ...[
            const SizedBox(height: 8),
            const AttendUsStatusBadge(
              label: 'Showing saved results — reconnect to refresh',
              tone: AttendUsStatusTone.warning,
              icon: Icons.cloud_off_outlined,
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: (_) => _scheduleSearch(),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              hintText: 'Search events, organizers, or venues',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        _scheduleSearch();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    key: const ValueKey('discovery-category-filter'),
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DiscoveryCategory.fromId(
                                _selectedCategoryId ?? '',
                              )?.label ??
                              'Categories',
                        ),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                    selected: _selectedCategoryId != null,
                    onPressed: _showAllCategories,
                    onDeleted: _selectedCategoryId == null
                        ? null
                        : () => _selectCategory(null),
                    deleteButtonTooltipMessage: 'Clear category',
                  ),
                ),
                _choice('Today', _datePreset == 'today', () {
                  setState(
                    () => _datePreset = _datePreset == 'today' ? null : 'today',
                  );
                  _refreshForQuickChoice('today');
                }),
                _choice('This weekend', _datePreset == 'weekend', () {
                  setState(
                    () => _datePreset = _datePreset == 'weekend'
                        ? null
                        : 'weekend',
                  );
                  _refreshForQuickChoice('weekend');
                }),
                _choice('Free', _freeOnly, () {
                  setState(() => _freeOnly = !_freeOnly);
                  _refreshForQuickChoice('free');
                }),
                _choice('Online', _onlineOnly, () {
                  setState(() => _onlineOnly = !_onlineOnly);
                  _refreshForQuickChoice('online');
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationButton() {
    final label = _location?.label ?? 'Choose location';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const ValueKey('discovery-location'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        onPressed: _chooseCity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCategory(String? id) async {
    final clearing = id == null || id == _selectedCategoryId;
    setState(() {
      _selectedCategoryId = clearing ? null : id;
      _browseAll = false;
    });
    ProductFunnelService().record(
      clearing ? 'discovery_category_cleared' : 'discovery_category_selected',
      dimensions: {
        'categoryId': clearing ? 'all' : id,
        'experienceVersion': '2',
      },
    );
    if (_searchController.text.trim().isNotEmpty) {
      await _runSearch();
    } else {
      await _loadHome();
    }
  }

  Future<void> _showAllCategories() async {
    ProductFunnelService().record(
      'discovery_category_view_all',
      dimensions: {'experienceVersion': '2'},
    );
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'All categories',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DiscoveryCategory.all
                        .map(
                          (category) => FilterChip(
                            avatar: Icon(category.icon, size: 17),
                            label: Text(category.label),
                            selected: category.id == _selectedCategoryId,
                            onSelected: (_) =>
                                Navigator.pop(context, category.id),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              if (_selectedCategoryId != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Clear category'),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await _selectCategory(selected.isEmpty ? null : selected);
    }
  }

  double get _cardTextExpansion =>
      (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
        0,
        double.infinity,
      ) *
      14;

  Widget _distanceHeading() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For you', style: Theme.of(context).textTheme.titleLarge),
              if (!_loading)
                Text(
                  _resolvedMiles == null
                      ? 'Showing events nationwide'
                      : _fixedMiles != null || _resolvedMiles == 25
                      ? 'Within $_resolvedMiles miles'
                      : 'Expanded to $_resolvedMiles miles',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _chooseDistance,
          icon: const Icon(Icons.radar, size: 20),
          label: Text(_fixedMiles == null ? 'Auto' : '$_fixedMiles mi'),
        ),
      ],
    ),
  );

  Future<void> _chooseDistance() async {
    int selected = _fixedMiles ?? 0;
    final hasLocation = _location != null && !_location!.nationwide;
    Widget content(BuildContext sheetContext) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event distance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Distance applies to in-person events. Online events are included.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final miles in [0, 5, 10, 25, 50, 100])
                      ChoiceChip(
                        label: Text(miles == 0 ? 'Auto' : '$miles miles'),
                        selected: selected == miles,
                        onSelected: (_) => update(() => selected = miles),
                      ),
                  ],
                ),
                if (!hasLocation) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Choose a location to use a fixed distance. Auto shows events nationwide.',
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, -1),
                    child: const Text('Choose location'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: selected != 0 && !hasLocation
                          ? null
                          : () => Navigator.pop(sheetContext, selected),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final int? result = MediaQuery.sizeOf(context).width < 700
        ? await showModalBottomSheet<int>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: content,
          )
        : await showDialog<int>(
            context: context,
            builder: (context) =>
                Dialog(child: SizedBox(width: 440, child: content(context))),
          );
    if (!mounted || result == null) return;
    if (result == -1) {
      await _chooseCity();
      return;
    }
    _requestGeneration++;
    setState(() => _fixedMiles = result == 0 ? null : result);
    final preferences = await SharedPreferences.getInstance();
    if (result == 0) {
      await preferences.remove('discovery_fixed_miles');
    } else {
      await preferences.setInt('discovery_fixed_miles', result);
    }
    if (mounted) await _loadHome();
  }

  Widget _recommendations() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      children: [
        if (MediaQuery.sizeOf(context).width >= 700)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final forward in [false, true])
                IconButton(
                  tooltip: forward
                      ? 'Next recommendations'
                      : 'Previous recommendations',
                  onPressed: () => _carouselScroll.animateTo(
                    (_carouselScroll.offset + (forward ? 292 : -292)).clamp(
                      0,
                      _carouselScroll.position.maxScrollExtent,
                    ),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                  icon: Icon(
                    forward ? Icons.chevron_right : Icons.chevron_left,
                  ),
                ),
            ],
          ),
        SizedBox(
          height: 360 + _cardTextExpansion,
          child: ListView.separated(
            controller: _carouselScroll,
            scrollDirection: Axis.horizontal,
            itemCount: (_home?.sections.first.events.length ?? 0),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, index) => SizedBox(
              width: 280,
              child: _eventCardV2(
                _home!.sections.first.events[index],
                'recommended',
                index,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _upcomingCard(DiscoveryEvent item, int index) {
    final event = item.event;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openEvent(item, 'upcoming', index),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: event.imageUrl.isEmpty
                      ? const Icon(Icons.event, size: 32)
                      : Image.network(
                          event.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.event),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.schedule.cardLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        event.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        event.locationType == 'online'
                            ? 'Online'
                            : event.locationName?.isNotEmpty == true
                            ? event.locationName!
                            : event.location,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _savedIds.contains(event.id)
                      ? 'Unsave event'
                      : 'Save event',
                  onPressed: () => _toggleSave(item),
                  icon: Icon(
                    _savedIds.contains(event.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventCardV2(DiscoveryEvent item, String section, int index) {
    final event = item.event;
    final category = DiscoveryCategory.fromId(event.primaryDiscoveryCategoryId);
    final remaining = event.maxTickets > 0
        ? event.maxTickets -
              (event.ticketsEnabled
                  ? event.issuedTickets
                  : event.confirmedRegistrationCount)
        : null;
    return AttendUsEventSummaryCard(
      title: event.title,
      imageUrl: event.imageUrl,
      imageAspectRatio: 3 / 2,
      fallbackIcon: category?.icon,
      dateLabel: event.schedule.cardLabel,
      locationLabel: event.locationType == 'online'
          ? 'Online'
          : (event.locationName?.isNotEmpty == true
                ? event.locationName!
                : (event.city.isNotEmpty ? event.city : event.location)),
      organizerLabel: event.groupName,
      distanceLabel: item.distanceMiles == null
          ? null
          : '${item.distanceMiles!.toStringAsFixed(1)} mi',
      priceLabel: !event.ticketsEnabled || (event.ticketPrice ?? 0) <= 0
          ? 'Free'
          : 'From \$${event.ticketPrice!.toStringAsFixed(0)}',
      availabilityLabel: remaining == null
          ? (event.issuedTickets > 0
                ? '${event.issuedTickets} attending'
                : null)
          : remaining <= 0
          ? 'Sold out'
          : '$remaining ${event.ticketsEnabled ? 'tickets' : 'spots'} remaining',
      statusLabel: event.isFeatured ? 'Featured' : null,
      isSaved: _savedIds.contains(event.id),
      onSave: () => _toggleSave(item),
      onTap: () => _openEvent(item, section, index),
    );
  }

  Widget _v2EmptyState() {
    final category = DiscoveryCategory.fromId(_selectedCategoryId);
    if (category == null) return _emptyState();
    if (_recordedCategoryNoResults.add(category.id)) {
      ProductFunnelService().record(
        'discovery_category_no_result',
        dimensions: {'categoryId': category.id, 'experienceVersion': '2'},
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 50),
            const SizedBox(height: 12),
            Text(
              'No ${category.label} events near you yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Try online events, choose another interest, or host the first one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => _selectCategory(null),
                  child: const Text('Clear category'),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _onlineOnly = true);
                    _loadHome();
                  },
                  child: const Text('Explore online'),
                ),
                FilledButton.icon(
                  onPressed: _createEvent,
                  icon: const Icon(Icons.add),
                  label: const Text('Create event'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration_outlined, size: 52),
          const SizedBox(height: 12),
          Text(
            'Be the first to host',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'There are no upcoming local or online events to show for ${_location?.label ?? 'this area'}. Join the Founding Organizer program by publishing the first one.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          AttendUsButton.primary(
            label: 'Create event',
            icon: Icons.add,
            onPressed: _createEvent,
          ),
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: 'Host your next event on Attendus.'),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Invite an organizer'),
          ),
        ],
      ),
    ),
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Discovery is temporarily unavailable',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your connection and try again. Your saved location is still available.',
          ),
          const SizedBox(height: 16),
          AttendUsButton.primary(
            label: 'Try again',
            onPressed: _searchMode ? _runSearch : _loadHome,
          ),
        ],
      ),
    ),
  );
}

class _DiscoveryCityDialog extends StatefulWidget {
  const _DiscoveryCityDialog();

  @override
  State<_DiscoveryCityDialog> createState() => _DiscoveryCityDialogState();
}

class _DiscoveryCityDialogState extends State<_DiscoveryCityDialog> {
  final _places = PlacesService();
  final _controller = TextEditingController();
  late String _sessionToken;
  List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionToken = _places.createSessionToken();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final values = await _places.autocomplete(
          query: query,
          sessionToken: _sessionToken,
          citiesOnly: true,
          discoveryOnly: true,
        );
        if (mounted) {
          setState(() {
            _suggestions = values;
            _loading = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = error.toString();
          });
        }
      }
    });
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() => _loading = true);
    try {
      final details = await _places.details(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
        discoveryOnly: true,
      );
      if (mounted) {
        Navigator.pop(context, details);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose your location'),
    content: SizedBox(
      width: 460,
      height: 360,
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _search,
            decoration: const InputDecoration(
              labelText: 'U.S. city or ZIP code',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (_, index) {
                final item = _suggestions[index];
                return ListTile(
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(item.primaryText),
                  subtitle: Text(item.secondaryText),
                  onTap: () => _select(item),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Browse online and nationwide'),
      ),
    ],
  );
}
