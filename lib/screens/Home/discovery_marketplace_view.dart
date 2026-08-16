import 'dart:async';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/discovery_location_service.dart';
import 'package:attendus/Services/discovery_marketplace_service.dart';
import 'package:attendus/Services/places_service.dart';
import 'package:attendus/Services/product_funnel_service.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/models/discovery_marketplace.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class DiscoveryMarketplaceView extends StatefulWidget {
  const DiscoveryMarketplaceView({super.key});

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
  List<String> _interests = const [];
  Timer? _debounce;

  bool get _searchMode =>
      _searchController.text.trim().isNotEmpty ||
      _datePreset != null ||
      _freeOnly ||
      _onlineOnly;

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
        ),
        _marketplace.savedEventIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _home = values[0] as DiscoveryHomeResult;
        _savedIds = values[1] as Set<String>;
        _loading = false;
      });
      final result = _home!;
      ProductFunnelService().record(
        'discovery_view',
        dimensions: {
          'locationSource': location.source,
          'radiusBand': result.radiusMiles.toString(),
          'resultCount': result.localResultCount.toString(),
          'metro': _metroDimension(location),
        },
      );
      if (result.expandedRadius) {
        ProductFunnelService().record(
          'discovery_radius_expansion',
          dimensions: {'radiusBand': result.radiusMiles.toString()},
        );
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
      );
      if (!mounted) return;
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
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
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
                          _runSearch();
                        }),
                        _choice('This weekend', _datePreset == 'weekend', () {
                          setState(
                            () => _datePreset = _datePreset == 'weekend'
                                ? null
                                : 'weekend',
                          );
                          _runSearch();
                        }),
                        _choice('Free', _freeOnly, () {
                          setState(() => _freeOnly = !_freeOnly);
                          _runSearch();
                        }),
                        _choice('Online', _onlineOnly, () {
                          setState(() => _onlineOnly = !_onlineOnly);
                          _runSearch();
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
    ProductFunnelService().record(
      'discovery_section_impression',
      dimensions: {
        'section': section.id,
        'resultCount': section.events.length.toString(),
      },
    );
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
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.crossAxisExtent >= 980
              ? 3
              : constraints.crossAxisExtent >= 620
              ? 2
              : 1;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 356,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, index) => _eventCard(results[index], 'search', index),
              childCount: results.length,
            ),
          );
        },
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
