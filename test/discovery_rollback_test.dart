import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/Home/discovery_marketplace_view.dart';

void main() {
  test('discovery marketplace requires an explicit enabled configuration', () {
    expect(resolveUseLegacyDiscovery(null), isTrue);
    expect(resolveUseLegacyDiscovery(const <String, dynamic>{}), isTrue);
    expect(
      resolveUseLegacyDiscovery(const <String, dynamic>{'useLegacyFeed': true}),
      isTrue,
    );
    expect(
      resolveUseLegacyDiscovery(const <String, dynamic>{
        'useLegacyFeed': false,
      }),
      isFalse,
    );
  });

  test('marketplace V2 requires an explicit version value', () {
    expect(resolveMarketplaceExperienceVersion(null), 1);
    expect(resolveMarketplaceExperienceVersion(const {}), 1);
    expect(
      resolveMarketplaceExperienceVersion(const {
        'marketplaceExperienceVersion': 2,
      }),
      2,
    );
    expect(
      resolveMarketplaceExperienceVersion(const {
        'marketplaceExperienceVersion': 3,
      }),
      1,
    );
  });

  test('a V1 response safely downgrades an explicitly enabled V2 view', () {
    expect(resolveActiveDiscoveryExperience(2, null), 2);
    expect(resolveActiveDiscoveryExperience(2, 2), 2);
    expect(resolveActiveDiscoveryExperience(2, 1), 1);
    expect(resolveActiveDiscoveryExperience(1, 2), 1);
  });
}
