import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';

class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget();
    }

    // Guard against non-direct or redirecting links (e.g., images.app.goo.gl)
    if (!_isLikelyDirectImageUrl(imageUrl)) {
      if (kDebugMode) {
        debugPrint('Skipping non-direct image URL: $imageUrl');
      }
      return _buildErrorWidget();
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit ?? BoxFit.cover,
      // PERFORMANCE: Aggressive memory optimization - limit cached image size
      memCacheWidth: width != null ? (width! * 2).toInt() : 600,
      memCacheHeight: height != null ? (height! * 2).toInt() : 400,
      // PERFORMANCE: Limit disk cache size as well
      maxWidthDiskCache: width != null ? (width! * 3).toInt() : 1200,
      maxHeightDiskCache: height != null ? (height! * 3).toInt() : 900,
      // Use lighter fade animation for better perceived performance
      fadeInDuration: const Duration(milliseconds: 150), // Reduced from 200
      fadeOutDuration: const Duration(milliseconds: 50), // Reduced from 100
      placeholder: (context, url) {
        // PERFORMANCE: Simplified placeholder - no debug logging in production
        return placeholder ??
            Container(
              color: Colors.grey[200],
              child: const SizedBox.shrink(), // Minimal placeholder
            );
      },
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          debugPrint('Error loading image: $url - $error');
        }
        return errorWidget ?? _buildErrorWidget();
      },
      // Reduce network calls by using cache-first strategy
      cacheKey: imageUrl,
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

  bool _isLikelyDirectImageUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    const blockedHosts = {'images.app.goo.gl', 'photos.app.goo.gl', 'goo.gl'};
    if (blockedHosts.contains(host) || host.endsWith('.app.goo.gl')) {
      return false;
    }

    final path = uri.path.toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    final hasImageExtension = imageExts.any((ext) => path.endsWith(ext));
    if (hasImageExtension) return true;

    // Allow Firebase Storage direct download links
    if (host.contains('firebasestorage.googleapis.com') &&
        (uri.queryParameters['alt'] == 'media')) {
      return true;
    }

    // Allow Googleusercontent direct CDN images (often used by Google Photos exports)
    if (host.contains('googleusercontent.com')) {
      return true;
    }

    return false;
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
            )
          : errorWidget,
      borderRadius: borderRadius,
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
