import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppImageCacheManager {
  static final BaseCacheManager instance = CacheManager(
    Config(
      'orgamiImageCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 300,
      repo: JsonCacheInfoRepository(databaseName: 'orgamiImageCache'),
      fileService: HttpFileService(),
    ),
  );
}