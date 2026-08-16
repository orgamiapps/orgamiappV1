import 'package:attendus/Utils/app_constants.dart';

abstract final class CommunityShareService {
  static Uri communityUri(String organizationId) => Uri.parse(
    '${AppConstants.publicWebDomain}/community/'
    '${Uri.encodeComponent(organizationId.trim())}',
  );

  static String? communityIdFromUri(Uri uri) {
    if (uri.host.isNotEmpty && uri.host != 'attendus.app') return null;
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final canonical = segments.length == 2 && segments.first == 'community';
    final application =
        segments.length == 3 &&
        segments[0] == 'app' &&
        segments[1] == 'community';
    if (!canonical && !application) return null;
    final id = segments.last.trim();
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ? id : null;
  }
}
