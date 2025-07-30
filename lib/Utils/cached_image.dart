import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CustomCacheImage extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final BoxFit? fit;
  final bool? circularShape;
  const CustomCacheImage({
    super.key,
    required this.imageUrl,
    required this.radius,
    this.circularShape,
    this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(circularShape == false ? 0 : radius),
          bottomRight: Radius.circular(circularShape == false ? 0 : radius)),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: fit ?? BoxFit.cover,
        width: double.infinity,
        height: MediaQuery.of(context).size.height,
        placeholder: (context, url) => Container(color: Colors.grey[300]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[300],
          child: const Icon(Icons.error),
        ),
      ),
    );
  }
}
