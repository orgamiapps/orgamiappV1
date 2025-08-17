import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final BaseCacheManager? cacheManager;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.cacheManager,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget();
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit ?? BoxFit.cover,
      cacheManager: cacheManager,
      placeholder: (context, url) {
        if (kDebugMode) {
          debugPrint('Loading image: $url');
        }
        return placeholder ?? const Center(child: CircularProgressIndicator());
      },
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          debugPrint('Error loading image: $url - $error');
        }
        return errorWidget ?? _buildErrorWidget();
      },
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: borderRadius,
      ),
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
}

class CachedImageWithFallback extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final BaseCacheManager? cacheManager;

  const CachedImageWithFallback({
    super.key,
    this.imageUrl,
    this.fallbackUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.cacheManager,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      if (fallbackUrl != null && fallbackUrl!.isNotEmpty) {
        return SafeNetworkImage(
          imageUrl: fallbackUrl!,
          width: width,
          height: height,
          fit: fit,
          placeholder: placeholder,
          errorWidget: errorWidget,
          borderRadius: borderRadius,
          cacheManager: cacheManager,
        );
      }
      return _buildErrorWidget();
    }

    return SafeNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder,
      errorWidget: fallbackUrl != null && fallbackUrl!.isNotEmpty
          ? SafeNetworkImage(
              imageUrl: fallbackUrl!,
              width: width,
              height: height,
              fit: fit,
              placeholder: placeholder,
              errorWidget: errorWidget,
              borderRadius: borderRadius,
              cacheManager: cacheManager,
            )
          : errorWidget,
      borderRadius: borderRadius,
      cacheManager: cacheManager,
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: borderRadius,
      ),
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
}
