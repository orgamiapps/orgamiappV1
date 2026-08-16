import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';

void main() {
  test('discovery marketplace requires an explicit enabled configuration', () {
    expect(resolveUseLegacyDiscovery(null), isTrue);
    expect(resolveUseLegacyDiscovery(const <String, dynamic>{}), isTrue);
    expect(
      resolveUseLegacyDiscovery(const <String, dynamic>{'useLegacyFeed': true}),
      isTrue,
    );
    expect(
      resolveUseLegacyDiscovery(const <String, dynamic>{'useLegacyFeed': false}),
      isFalse,
    );
  });
}
