import 'package:attendus/Utils/app_constants.dart';

abstract final class CommunityShareService {
  static Uri communityUri(
    String organizationId, {
    PublicLinkConfiguration? links,
  }) => Uri.parse(
    '${(links ?? AppConstants.publicLinks).canonicalOrigin}/community/'
    '${Uri.encodeComponent(organizationId.trim())}',
  );

  static String? communityIdFromUri(Uri uri, {PublicLinkConfiguration? links}) {
    if (!(links ?? AppConstants.publicLinks).accepts(uri)) return null;
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
