import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared actor avatar widget used across actors_page, actor_detail_page,
/// and favorites_page. Uses Image.file for built-in disk caching.
class ActorAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double placeholderFontSize;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Key? imageKey;

  static final Map<String, bool> _fileExistsCache = {};

  const ActorAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.placeholderFontSize = 32,
    this.width,
    this.height,
    this.cacheWidth,
    this.imageKey,
  });

  /// Evict cached image for [filePath] so the next [Image.file]
  /// call re-decodes the file from disk.
  static void evictCache(String filePath) {
    final provider = FileImage(File(filePath));
    PaintingBinding.instance.imageCache.evict(provider);
  }

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final file = File(avatarUrl!);
      if (_fileExistsCache[avatarUrl!] ??= File(avatarUrl!).existsSync()) {
        return SizedBox(
          width: width ?? double.infinity,
          height: height ?? double.infinity,
          child: Image.file(
            file,
            key: imageKey,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('[ActorAvatar] Failed to load: $avatarUrl, error: $error');
              return _buildPlaceholder();
            },
          ),
        );
      }
      debugPrint('[ActorAvatar] File not found: $avatarUrl');
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.cardColor,
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: placeholderFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}