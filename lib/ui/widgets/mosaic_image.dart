import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MosaicImage extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const MosaicImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE8E8E8),
          borderRadius: borderRadius,
        ),
      );
    }

    final imageWidget = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.file(
        File(imagePath!),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: 20,
        filterQuality: FilterQuality.none,
        errorBuilder: AppTheme.imageErrorBuilder,
      ),
    );

    if (width != null && height != null) {
      return SizedBox(width: width, height: height, child: imageWidget);
    }

    return imageWidget;
  }
}
