import 'package:attendus/Services/community_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds and parses public and application community URLs', () {
    expect(
      CommunityShareService.communityUri('org-123').toString(),
      'https://attendus.app/community/org-123',
    );
    expect(
      CommunityShareService.communityIdFromUri(
        Uri.parse('/app/community/org-123'),
      ),
      'org-123',
    );
  });
}
