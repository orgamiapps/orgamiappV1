import 'package:attendus/models/event_model.dart';

class DiscoveryEvent {
  final EventModel event;
  final double? distanceMiles;

  const DiscoveryEvent({required this.event, this.distanceMiles});

  factory DiscoveryEvent.fromMap(Map<String, dynamic> map) => DiscoveryEvent(
    event: EventModel.fromJson(map),
    distanceMiles: (map['distanceMiles'] as num?)?.toDouble(),
  );
}

class DiscoverySection {
  final String id;
  final String title;
  final String subtitle;
  final bool featured;
  final List<DiscoveryEvent> events;
  final int totalAvailable;

  const DiscoverySection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.featured,
    required this.events,
    this.totalAvailable = 0,
  });

  factory DiscoverySection.fromMap(Map<String, dynamic> map) =>
      DiscoverySection(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        subtitle: map['subtitle']?.toString() ?? '',
        featured: map['featured'] == true,
        events: (map['events'] as List? ?? const [])
            .map(
              (item) => DiscoveryEvent.fromMap(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        totalAvailable:
            (map['totalAvailable'] as num?)?.round() ??
            (map['events'] as List? ?? const []).length,
      );
}

class DiscoveryCategoryFacet {
  final String id;
  final String label;
  final int count;
  final String? representativeImageUrl;

  const DiscoveryCategoryFacet({
    required this.id,
    required this.label,
    required this.count,
    this.representativeImageUrl,
  });

  factory DiscoveryCategoryFacet.fromMap(Map<String, dynamic> map) =>
      DiscoveryCategoryFacet(
        id: map['id']?.toString() ?? '',
        label: map['label']?.toString() ?? '',
        count: (map['count'] as num?)?.round() ?? 0,
        representativeImageUrl: map['representativeImageUrl']?.toString(),
      );
}

class DiscoveryHomeResult {
  final List<DiscoverySection> sections;
  final int radiusMiles;
  final bool expandedRadius;
  final int localResultCount;
  final String cacheState;
  final List<DiscoveryCategoryFacet> categoryFacets;
  final String? selectedCategoryId;
  final int schemaVersion;

  const DiscoveryHomeResult({
    required this.sections,
    required this.radiusMiles,
    required this.expandedRadius,
    required this.localResultCount,
    this.cacheState = 'fresh',
    this.categoryFacets = const [],
    this.selectedCategoryId,
    this.schemaVersion = 1,
  });

  factory DiscoveryHomeResult.fromMap(
    Map<String, dynamic> map,
  ) => DiscoveryHomeResult(
    sections: (map['sections'] as List? ?? const [])
        .map(
          (item) =>
              DiscoverySection.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    radiusMiles: (map['radiusMiles'] as num?)?.round() ?? 25,
    expandedRadius: map['expandedRadius'] == true,
    localResultCount: (map['localResultCount'] as num?)?.round() ?? 0,
    cacheState: map['_cacheState']?.toString() ?? 'fresh',
    categoryFacets: (map['categoryFacets'] as List? ?? const [])
        .map(
          (item) => DiscoveryCategoryFacet.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    selectedCategoryId: map['selectedCategoryId']?.toString(),
    schemaVersion: (map['schemaVersion'] as num?)?.round() ?? 1,
  );
}

class DiscoverySearchResult {
  final List<DiscoveryEvent> events;
  final String? nextCursor;
  final int total;

  const DiscoverySearchResult({
    required this.events,
    required this.nextCursor,
    required this.total,
  });

  factory DiscoverySearchResult.fromMap(Map<String, dynamic> map) =>
      DiscoverySearchResult(
        events: (map['events'] as List? ?? const [])
            .map(
              (item) => DiscoveryEvent.fromMap(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        nextCursor: map['nextCursor']?.toString(),
        total: (map['total'] as num?)?.round() ?? 0,
      );
}
