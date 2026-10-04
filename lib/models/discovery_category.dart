import 'package:flutter/material.dart';

class DiscoveryCategory {
  final String id;
  final String label;
  final IconData icon;

  const DiscoveryCategory(this.id, this.label, this.icon);

  static const all = <DiscoveryCategory>[
    DiscoveryCategory(
      'music-nightlife',
      'Music & Nightlife',
      Icons.music_note_outlined,
    ),
    DiscoveryCategory('food-drink', 'Food & Drink', Icons.restaurant_outlined),
    DiscoveryCategory(
      'business-networking',
      'Business & Networking',
      Icons.handshake_outlined,
    ),
    DiscoveryCategory(
      'technology-innovation',
      'Technology & Innovation',
      Icons.memory_outlined,
    ),
    DiscoveryCategory(
      'classes-workshops',
      'Classes & Workshops',
      Icons.school_outlined,
    ),
    DiscoveryCategory('arts-culture', 'Arts & Culture', Icons.palette_outlined),
    DiscoveryCategory(
      'film-entertainment',
      'Film & Entertainment',
      Icons.movie_outlined,
    ),
    DiscoveryCategory(
      'sports-fitness',
      'Sports & Fitness',
      Icons.fitness_center_outlined,
    ),
    DiscoveryCategory(
      'health-wellness',
      'Health & Wellness',
      Icons.spa_outlined,
    ),
    DiscoveryCategory(
      'community-causes',
      'Community & Causes',
      Icons.volunteer_activism_outlined,
    ),
    DiscoveryCategory(
      'family-kids',
      'Family & Kids',
      Icons.family_restroom_outlined,
    ),
    DiscoveryCategory(
      'hobbies-games',
      'Hobbies & Games',
      Icons.extension_outlined,
    ),
    DiscoveryCategory(
      'outdoors-adventure',
      'Outdoors & Adventure',
      Icons.terrain_outlined,
    ),
    DiscoveryCategory(
      'faith-spirituality',
      'Faith & Spirituality',
      Icons.self_improvement_outlined,
    ),
    DiscoveryCategory(
      'seasonal-holiday',
      'Seasonal & Holiday',
      Icons.celebration_outlined,
    ),
  ];

  static DiscoveryCategory? fromId(String? id) {
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }

  static List<String> legacyLabels(Iterable<String> ids) {
    const mapping = <String, String>{
      'music-nightlife': 'Entertainment',
      'food-drink': 'Food & Dining',
      'business-networking': 'Social & Networking',
      'technology-innovation': 'Technology',
      'classes-workshops': 'Education & Learning',
      'arts-culture': 'Arts & Culture',
      'film-entertainment': 'Entertainment',
      'sports-fitness': 'Sports & Fitness',
      'health-wellness': 'Sports & Fitness',
      'community-causes': 'Community & Charity',
      'family-kids': 'Community & Charity',
      'hobbies-games': 'Entertainment',
      'outdoors-adventure': 'Sports & Fitness',
      'faith-spirituality': 'Community & Charity',
      'seasonal-holiday': 'Entertainment',
    };
    return ids.map((id) => mapping[id]).whereType<String>().toSet().toList();
  }

  static List<String> fromLegacyLabels(Iterable<String> labels) {
    const mapping = <String, String>{
      'Social & Networking': 'business-networking',
      'Entertainment': 'film-entertainment',
      'Sports & Fitness': 'sports-fitness',
      'Education & Learning': 'classes-workshops',
      'Arts & Culture': 'arts-culture',
      'Food & Dining': 'food-drink',
      'Technology': 'technology-innovation',
      'Community & Charity': 'community-causes',
    };
    return labels
        .map((label) => mapping[label])
        .whereType<String>()
        .toSet()
        .take(3)
        .toList();
  }
}
