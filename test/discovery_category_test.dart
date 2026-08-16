import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/models/discovery_category.dart';

void main() {
  test('discovery category catalog has 15 stable unique identifiers', () {
    expect(DiscoveryCategory.all, hasLength(15));
    expect(
      DiscoveryCategory.all.map((category) => category.id).toSet(),
      hasLength(15),
    );
    expect(
      DiscoveryCategory.fromId('technology-innovation')?.label,
      'Technology & Innovation',
    );
  });

  test('legacy categories map into canonical discovery categories', () {
    expect(
      DiscoveryCategory.fromLegacyLabels(['Technology', 'Food & Dining']),
      ['technology-innovation', 'food-drink'],
    );
    expect(
      DiscoveryCategory.legacyLabels(['technology-innovation', 'food-drink']),
      ['Technology', 'Food & Dining'],
    );
  });
}
