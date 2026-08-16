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
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  const DiscoveryMarketplaceView({super.key, this.experienceVersion = 1});

  @override
  State<DiscoveryMarketplaceView> createState() =>
      _DiscoveryMarketplaceViewState();
}

class _DiscoveryMarketplaceViewState extends State<DiscoveryMarketplaceView> {
  final _marketplace = DiscoveryMarketplaceService();
  final _locations = DiscoveryLocationService();
  final _searchController = TextEditingController();
  DiscoveryLocation? _location;
  DiscoveryHomeResult? _home;
  DiscoverySearchResult? _search;
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
  final Set<String> _recordedSectionImpressions = {};
  final Set<String> _recordedCategoryNoResults = {};
  bool _categoryModuleRecorded = false;
  bool _browseAll = false;
  bool _loadingMore = false;

  int get _activeExperienceVersion => resolveActiveDiscoveryExperience(
    widget.experienceVersion,
    _home?.schemaVersion,
  );

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
        _searchController.text.trim().isEmpty) {
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
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _interests = await _locations.loadInterests();
    final cached = await _locations.load();
    if (!mounted) return;
    if (cached == null) {
      setState(() => _loading = false);
      await _showLocationOnboarding();
      return;
    }
    _location = cached;
    await _loadHome();
  }

  Future<void> _showLocationOnboarding() async {
    if (!mounted) return;
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

  Future<void> _loadHome() async {
    final location = _location;
    if (location == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _search = null;
    });
    try {
      final values = await Future.wait([
        _marketplace.home(
          latitude: location.latitude,
          longitude: location.longitude,
          nationwide: location.nationwide,
          preferredCategories: _interests,
          regionCode: location.regionCode,
          experienceVersion: _activeExperienceVersion,
          selectedCategoryId: _selectedCategoryId,
          datePreset: _activeExperienceVersion == 2 ? _datePreset : null,
          freeOnly: _activeExperienceVersion == 2 && _freeOnly,
          onlineOnly: _activeExperienceVersion == 2 && _onlineOnly,
        ),
        _marketplace.savedEventIds(),
      ]);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _home = values[0] as DiscoveryHomeResult;
        _savedIds = values[1] as Set<String>;
        _loading = false;
      });
      if (_activeExperienceVersion == 2 && !_categoryModuleRecorded) {
        _categoryModuleRecorded = true;
        ProductFunnelService().record(
          'discovery_category_module_impression',
          dimensions: {'experienceVersion': '2'},
        );
      }
      final result = _home!;
      ProductFunnelService().record(
        'discovery_view',
        dimensions: {
          'locationSource': location.source,
          'radiusBand': result.radiusMiles.toString(),
          'resultCount': result.localResultCount.toString(),
          'metro': _metroDimension(location),
          'experienceVersion': _activeExperienceVersion.toString(),
        },
      );
      if (result.expandedRadius) {
        ProductFunnelService().record(
          'discovery_radius_expansion',
          dimensions: {'radiusBand': result.radiusMiles.toString()},
        );
      }
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() async {
    final location = _location;
    if (location == null || !_searchMode) {
      setState(() => _search = null);
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _marketplace.search(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMiles: _home?.radiusMiles ?? 100,
        query: _searchController.text.trim(),
        datePreset: _datePreset,
        freeOnly: _freeOnly,
        onlineOnly: _onlineOnly,
        nationwide: location.nationwide,
        category: _selectedCategoryId,
        experienceVersion: _activeExperienceVersion,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _search = result;
        _loading = false;
      });
      ProductFunnelService().record(
        result.events.isEmpty
            ? 'discovery_search_no_result'
            : 'discovery_search_results',
        dimensions: {
          'resultCount': result.total.toString(),
          'accessMode': _onlineOnly ? 'online' : 'local',
          'radiusBand': (_home?.radiusMiles ?? 100).toString(),
          'metro': _metroDimension(location),
          'categoryId': _selectedCategoryId ?? 'all',
          'experienceVersion': _activeExperienceVersion.toString(),
        },
      );
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
    final location = _location;
    final current = _search;
    final cursor = current?.nextCursor;
    if (location == null || current == null || cursor == null || _loadingMore) {
      return;
    }
    final generation = _requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final next = await _marketplace.search(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMiles: _home?.radiusMiles ?? 100,
        query: _searchController.text.trim(),
        datePreset: _datePreset,
        freeOnly: _freeOnly,
        onlineOnly: _onlineOnly,
        nationwide: location.nationwide,
        category: _selectedCategoryId,
        cursor: cursor,
        experienceVersion: _activeExperienceVersion,
      );
      if (!mounted || generation != _requestGeneration) return;
      final existingIds = current.events.map((item) => item.event.id).toSet();
      setState(() {
        _search = DiscoverySearchResult(
          events: [
            ...current.events,
            ...next.events.where((item) => existingIds.add(item.event.id)),
          ],
          nextCursor: next.nextCursor,
          total: next.total,
        );
        _loadingMore = false;
      });
      ProductFunnelService().record(
        'discovery_search_page_loaded',
        dimensions: {
          'resultCount': next.events.length.toString(),
          'categoryId': _selectedCategoryId ?? 'all',
          'experienceVersion': _activeExperienceVersion.toString(),
        },
      );
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loadingMore = false;
          _error = error.toString();
        });
      }
    }
  }

  String _metroDimension(DiscoveryLocation location) =>
      '${location.city}-${location.regionCode}'.toLowerCase().replaceAll(
        RegExp('[^a-z0-9-]'),
        '-',
      );

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
    RouterClass.nextScreenNormal(
      context,
      SingleEventScreen(eventModel: item.event),
    );
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
  Widget build(BuildContext context) {
    if (_activeExperienceVersion == 2) return _buildV2(context);
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _searchMode ? _runSearch : _loadHome,
      child: CustomScrollView(
        key: const PageStorageKey('discovery-marketplace'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Discover',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.location_on_outlined, size: 18),
                      label: Text(_location?.label ?? 'Choose location'),
                      onPressed: _chooseCity,
                    ),
                  ),
                  if (_home?.cacheState == 'stale') ...[
                    const SizedBox(height: 8),
                    const AttendUsStatusBadge(
                      label: 'Showing saved results — reconnect to refresh',
                      tone: AttendUsStatusTone.warning,
                      icon: Icons.cloud_off_outlined,
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => _scheduleSearch(),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: InputDecoration(
                      hintText:
                          'Search events near ${_location?.city ?? 'you'}',
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
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _choice('Today', _datePreset == 'today', () {
                          setState(
                            () => _datePreset = _datePreset == 'today'
                                ? null
                                : 'today',
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
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _createEvent,
                      icon: const Icon(Icons.add),
                      label: const Text('Create event'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: _errorState())
          else if (_searchMode)
            _searchResults()
          else
            ..._homeSections(),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildV2(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _searchMode ? _runSearch : _loadHome,
      child: CustomScrollView(
        key: const PageStorageKey('discovery-marketplace-v2'),
        slivers: [
          SliverToBoxAdapter(child: _v2Header(context)),
          if (_loading && _home == null)
            const SliverToBoxAdapter(child: _DiscoverySkeleton())
          else if (_error != null && _home == null)
            SliverFillRemaining(hasScrollBody: false, child: _errorState())
          else if (_searchMode)
            _searchResults()
          else ...[
            if (_loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ..._v2Sections(),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(child: _hostFooter()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _v2Header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(_location?.label ?? 'Choose location'),
                onPressed: _chooseCity,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Notifications',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'What are you interested in?',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _showAllCategories,
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _categoryStrip(),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
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

  List<DiscoveryCategoryFacet> get _visibleCategoryFacets {
    final facets = _home?.categoryFacets ?? const <DiscoveryCategoryFacet>[];
    final source = facets.isNotEmpty
        ? facets
        : DiscoveryCategory.all
              .map(
                (category) => DiscoveryCategoryFacet(
                  id: category.id,
                  label: category.label,
                  count: 0,
                ),
              )
              .toList();
    final visible = source.take(6).toList();
    final selected = source
        .where((facet) => facet.id == _selectedCategoryId)
        .firstOrNull;
    if (selected != null && !visible.any((facet) => facet.id == selected.id)) {
      visible[visible.length - 1] = selected;
    }
    return visible;
  }

  Widget _categoryStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = _visibleCategoryFacets
            .map(
              (facet) => _categoryTile(
                facet,
                width: constraints.maxWidth < 700 ? 164 : 178,
              ),
            )
            .toList();
        if (constraints.maxWidth < 700) {
          return SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) => tiles[index],
            ),
          );
        }
        return Wrap(spacing: 10, runSpacing: 10, children: tiles);
      },
    );
  }

  Widget _categoryTile(DiscoveryCategoryFacet facet, {required double width}) {
    final category = DiscoveryCategory.fromId(facet.id);
    final selected = facet.id == _selectedCategoryId;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${facet.label}${facet.count > 0 ? ', ${facet.count} events' : ''}',
      child: InkWell(
        onTap: () => _selectCategory(facet.id),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          width: width,
          height: 78,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                category?.icon ?? Icons.local_activity_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  facet.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
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

  List<Widget> _v2Sections() {
    final sections = _home?.sections ?? const <DiscoverySection>[];
    if (sections.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _v2EmptyState()),
      ];
    }
    return sections
        .map((section) => SliverToBoxAdapter(child: _sectionV2(section)))
        .toList();
  }

  Widget _sectionV2(DiscoverySection section) {
    _recordSectionImpression(section);
    final subtitle =
        section.id == 'recommended' && (_home?.expandedRadius ?? false)
        ? 'Expanded to ${_home!.radiusMiles} miles to find more events'
        : section.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth < 700;
          final columns = mobile
              ? 1
              : (constraints.maxWidth / 300).floor().clamp(2, 4).toInt();
          final visible = mobile
              ? section.events.length
              : section.events.take(columns).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (section.totalAvailable > visible)
                    TextButton(
                      onPressed: () => _showSectionResults(section),
                      child: const Text('See all'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (mobile)
                SizedBox(
                  height: 360,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: section.events.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => SizedBox(
                      width: 280,
                      child: _eventCardV2(
                        section.events[index],
                        section.id,
                        index,
                      ),
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 360,
                    crossAxisSpacing: 14,
                  ),
                  itemBuilder: (_, index) =>
                      _eventCardV2(section.events[index], section.id, index),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showSectionResults(DiscoverySection section) {
    ProductFunnelService().record(
      'discovery_section_view_all',
      dimensions: {'section': section.id, 'experienceVersion': '2'},
    );
    setState(() => _browseAll = true);
    _runSearch();
  }

  Widget _eventCardV2(DiscoveryEvent item, String section, int index) {
    final event = item.event;
    final category = DiscoveryCategory.fromId(event.primaryDiscoveryCategoryId);
    final remaining = event.maxTickets > 0
        ? event.maxTickets - event.issuedTickets
        : null;
    return AttendUsEventSummaryCard(
      title: event.title,
      imageUrl: event.imageUrl,
      imageAspectRatio: 3 / 2,
      fallbackIcon: category?.icon,
      dateLabel: DateFormat(
        'EEE, MMM d · h:mm a',
      ).format(event.selectedDateTime.toLocal()),
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
          : '$remaining tickets left',
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

  Widget _hostFooter() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline),
            const SizedBox(width: 12),
            const Expanded(child: Text('Hosting something? Create an event.')),
            TextButton(onPressed: _createEvent, child: const Text('Create')),
          ],
        ),
      ),
    ),
  );

  void _recordSectionImpression(DiscoverySection section) {
    if (!_recordedSectionImpressions.add(section.id)) return;
    ProductFunnelService().record(
      'discovery_section_impression',
      dimensions: {
        'section': section.id,
        'resultCount': section.events.length.toString(),
        'experienceVersion': _activeExperienceVersion.toString(),
      },
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

  List<Widget> _homeSections() {
    final sections = _home?.sections ?? const <DiscoverySection>[];
    if (sections.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _emptyState())];
    }
    final widgets = <Widget>[];
    var categoriesAdded = false;
    for (final section in sections) {
      if (section.id == 'online' && !categoriesAdded) {
        widgets.add(SliverToBoxAdapter(child: _categories()));
        categoriesAdded = true;
      }
      widgets.add(SliverToBoxAdapter(child: _section(section)));
    }
    if (!categoriesAdded) widgets.add(SliverToBoxAdapter(child: _categories()));
    return widgets;
  }

  Widget _section(DiscoverySection section) {
    _recordSectionImpression(section);
    final subtitle =
        section.id == 'recommended' && (_home?.expandedRadius ?? false)
        ? 'Expanded to ${_home!.radiusMiles} miles to find more events'
        : section.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 356,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: section.events.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) => SizedBox(
                width: 310,
                child: _eventCard(section.events[index], section.id, index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(DiscoveryEvent item, String section, int index) {
    final event = item.event;
    final remaining = event.maxTickets > 0
        ? event.maxTickets - event.issuedTickets
        : null;
    return AttendUsEventSummaryCard(
      title: event.title,
      subtitle: event.description,
      imageUrl: event.imageUrl,
      dateLabel: DateFormat(
        'EEE, MMM d · h:mm a',
      ).format(event.selectedDateTime.toLocal()),
      locationLabel: event.locationType == 'online'
          ? 'Online'
          : (event.city.isNotEmpty ? event.city : event.location),
      organizerLabel: event.groupName,
      distanceLabel: item.distanceMiles == null
          ? null
          : '${item.distanceMiles!.toStringAsFixed(1)} mi',
      priceLabel: !event.ticketsEnabled || (event.ticketPrice ?? 0) <= 0
          ? 'Free'
          : 'From \$${event.ticketPrice!.toStringAsFixed(0)}',
      availabilityLabel: remaining == null
          ? null
          : remaining <= 0
          ? 'Sold out'
          : '$remaining tickets left',
      statusLabel: event.isFeatured ? 'Featured' : null,
      isSaved: _savedIds.contains(event.id),
      onSave: () => _toggleSave(item),
      onTap: () => _openEvent(item, section, index),
    );
  }

  Widget _categories() {
    final categories = (_home?.sections ?? const <DiscoverySection>[])
        .expand((section) => section.events)
        .expand((item) => item.event.categories)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .take(8)
        .toList();
    if (categories.length < 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore by category',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories
                .map(
                  (category) => ActionChip(
                    avatar: const Icon(Icons.local_activity_outlined, size: 17),
                    label: Text(category),
                    onPressed: () {
                      _searchController.text = category;
                      _runSearch();
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _searchResults() {
    final results = _search?.events ?? const <DiscoveryEvent>[];
    if (results.isEmpty) {
      return SliverFillRemaining(hasScrollBody: false, child: _emptySearch());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 980
                ? 3
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            return Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 356,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: results.length,
                  itemBuilder: (_, index) =>
                      _eventCard(results[index], 'search', index),
                ),
                if (_search?.nextCursor != null) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMoreSearchResults,
                    icon: _loadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: Text(_loadingMore ? 'Loading events' : 'Load more'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptySearch() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48),
          const SizedBox(height: 12),
          Text(
            'No matching events yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a broader search, clear a quick choice, or explore online events.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _searchController.clear();
                _datePreset = null;
                _freeOnly = false;
                _onlineOnly = false;
                _search = null;
                _browseAll = false;
              });
            },
            child: const Text('Clear search'),
          ),
        ],
      ),
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

class _DiscoverySkeleton extends StatelessWidget {
  const _DiscoverySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, {double? width}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(22, width: 190),
          const SizedBox(height: 12),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) => block(78, width: 164),
            ),
          ),
          const SizedBox(height: 28),
          block(22, width: 150),
          const SizedBox(height: 14),
          SizedBox(
            height: 340,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => block(340, width: 280),
            ),
          ),
        ],
      ),
    );
  }
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
