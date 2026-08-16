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

  const DiscoverySection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.featured,
    required this.events,
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
      );
}

class DiscoveryHomeResult {
  final List<DiscoverySection> sections;
  final int radiusMiles;
  final bool expandedRadius;
  final int localResultCount;
  final String cacheState;

  const DiscoveryHomeResult({
    required this.sections,
    required this.radiusMiles,
    required this.expandedRadius,
    required this.localResultCount,
    this.cacheState = 'fresh',
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
