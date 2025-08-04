import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomCacheImage extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final BoxFit? fit;
  final bool? circularShape;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CustomCacheImage({
    super.key,
    required this.imageUrl,
    required this.radius,
    this.circularShape,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildErrorContainer();
    }

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
        bottomLeft: Radius.circular(circularShape == false ? 0 : radius),
        bottomRight: Radius.circular(circularShape == false ? 0 : radius),
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: fit ?? BoxFit.cover,
        width: width ?? double.infinity,
        height: height ?? MediaQuery.of(context).size.height,
        memCacheWidth: 400, // Optimize memory usage
        memCacheHeight: 300,
        maxWidthDiskCache: 800, // Limit disk cache size
        maxHeightDiskCache: 600,
        placeholder: (context, url) =>
            placeholder ??
            Container(
              color: Colors.grey[300],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        errorWidget: (context, url, error) {
          print('Image loading error for URL: $url, Error: $error');
          return errorWidget ?? _buildErrorContainer();
        },
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 300),
        // Add retry mechanism and better error handling
        httpHeaders: const {
          'Cache-Control': 'max-age=3600',
          'User-Agent': 'OrgamiApp/1.0',
        },
      ),
    );
  }

  Widget _buildErrorContainer() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.grey),
            SizedBox(height: 4),
            Text(
              'Image not available',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced image widget with better error handling
class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: 400,
      memCacheHeight: 300,
      maxWidthDiskCache: 800,
      maxHeightDiskCache: 600,
      placeholder: (context, url) =>
          placeholder ??
          Container(
            color: Colors.grey[300],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      errorWidget: (context, url, error) {
        print('SafeNetworkImage error for URL: $url, Error: $error');
        return errorWidget ?? _buildDefaultErrorWidget();
      },
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 300),
      httpHeaders: const {
        'Cache-Control': 'max-age=3600',
        'User-Agent': 'OrgamiApp/1.0',
      },
    );
  }

  Widget _buildDefaultErrorWidget() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey, size: 32),
            SizedBox(height: 4),
            Text(
              'Image not available',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
