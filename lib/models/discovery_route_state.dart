import 'dart:collection';

/// Canonical, bounded public discovery filters. Unknown/tracking parameters are
/// ignored; credentials and exact device coordinates are never serialized.
class DiscoveryRouteState {
  DiscoveryRouteState(Map<String, String> values) : values = _normalize(values);
  final Map<String, String> values;
  factory DiscoveryRouteState.fromUri(Uri uri) =>
      DiscoveryRouteState(uri.queryParameters);
  String? operator [](String key) => values[key];
  bool enabled(String key) => values[key] == '1';
  Uri get uri => Uri(
    path: '/app/discover',
    queryParameters: values.isEmpty ? null : values,
  );
  static bool matches(Uri uri) => uri.path == '/app/discover';

  static Map<String, String> _normalize(Map<String, String> input) {
    final output = SplayTreeMap<String, String>();
    for (final key in ['q', 'city', 'region']) {
      final value = (input[key] ?? '').trim();
      if (value.isNotEmpty) {
        output[key] = value.substring(
          0,
          value.length.clamp(0, key == 'q' ? 160 : 80),
        );
      }
    }
    for (final key in ['free', 'online', 'browse', 'nationwide']) {
      if (input[key] == '1' || input[key] == 'true') output[key] = '1';
    }
    if (['today', 'weekend'].contains(input['date'])) {
      output['date'] = input['date']!;
    }
    final categories =
        (input['categories'] ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s.length <= 80)
            .toSet()
            .toList()
          ..sort();
    if (categories.isNotEmpty) {
      output['categories'] = categories.take(20).join(',');
    }
    if (RegExp(r'^[a-z][a-z0-9-]{0,79}$').hasMatch(input['category'] ?? '')) {
      output['category'] = input['category']!;
    }
    if ([
      'dateAddedAsc',
      'dateAddedDesc',
      'titleAsc',
      'titleDesc',
      'eventDateAsc',
      'eventDateDesc',
    ].contains(input['sort'])) {
      output['sort'] = input['sort']!;
    }
    if (input['type'] == 'users') output['type'] = 'users';
    final lat = double.tryParse(input['lat'] ?? '');
    final lng = double.tryParse(input['lng'] ?? '');
    if (output['nationwide'] != '1' &&
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180) {
      output['lat'] = lat.toStringAsFixed(2);
      output['lng'] = lng.toStringAsFixed(2);
    }
    final radius = double.tryParse(input['radius'] ?? '');
    if (radius != null && radius.isFinite && radius > 0 && radius <= 1000) {
      output['radius'] = radius.round().toString();
    }
    return Map.unmodifiable(output);
  }
}
