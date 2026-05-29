import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../../core/models/models.dart';
import '../../core/services/smart_sort_service.dart';
import '../theme/app_theme.dart';
import 'mosaic_image.dart';

class VideoGrid extends ConsumerWidget {
  final List<Video> videos;
  final ViewMode viewMode;
  final bool isFixedColumnCount;
  final int? fixedColumnCount;
  final Function(Video)? onVideoTap;
  final Function(Video)? onVideoDoubleTap;
  final Function(Video, Offset)? onVideoSecondaryTap;
  final Function(Video)? onFavoriteToggle;
  final PaginationMode paginationMode;
  final int currentPage;
  final int? pageSize;
  final Function(int)? onPageChanged;

  const VideoGrid({
    super.key,
    required this.videos,
    this.viewMode = ViewMode.poster,
    this.isFixedColumnCount = false,
    this.fixedColumnCount,
    this.onVideoTap,
    this.onVideoDoubleTap,
    this.onVideoSecondaryTap,
    this.onFavoriteToggle,
    this.paginationMode = PaginationMode.waterfall,
    this.currentPage = 1,
    this.pageSize,
    this.onPageChanged,
  });

  List<Video> _getPaginatedVideos(int effectivePageSize) {
    if (paginationMode == PaginationMode.waterfall || effectivePageSize <= 0) {
      return videos;
    }
    final start = (currentPage - 1) * effectivePageSize;
    final end = start + effectivePageSize;
    return videos.sublist(start.clamp(0, videos.length), end.clamp(0, videos.length));
  }

  int _getTotalPages(int effectivePageSize) {
    if (effectivePageSize <= 0) return 1;
    return (videos.length / effectivePageSize).ceil().clamp(1, 9999);
  }

  int _calculateEffectivePageSize(double availableHeight, double availableWidth, int crossAxisCount) {
    final spacing = GlassConstants.spacingMedium;
    final itemWidth = (availableWidth - spacing * (crossAxisCount + 1)) / crossAxisCount;
    double itemHeight;
    switch (viewMode) {
      case ViewMode.posterWall:
        itemHeight = itemWidth / 1.5 + 40;
        break;
      case ViewMode.posterWithTitle:
        itemHeight = itemWidth / 0.7 + 24;
        break;
      default:
        itemHeight = itemWidth / 0.7;
        break;
    }
    final rows = ((availableHeight - spacing) / (itemHeight + spacing)).floor().clamp(1, 20);
    return rows * crossAxisCount;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(fontSizeProvider);
    final enableAnimation = ref.watch(enableGridAnimationProvider);

    if (videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无视频',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(
          constraints.maxWidth,
          viewMode,
          isFixedColumnCount,
          fixedColumnCount,
        );

        final effectivePageSize = paginationMode == PaginationMode.paginated
            ? (pageSize ?? _calculateEffectivePageSize(constraints.maxHeight, constraints.maxWidth, crossAxisCount))
            : 0;
        final displayVideos = _getPaginatedVideos(effectivePageSize);
        final totalPages = _getTotalPages(effectivePageSize);

        return Column(
          children: [
            Expanded(
              child: switch (viewMode) {
                ViewMode.list => _buildListView(displayVideos, fontSize),
                _ => _buildGridView(displayVideos, crossAxisCount, fontSize, enableAnimation),
              },
            ),
            if (paginationMode == PaginationMode.paginated && totalPages > 1)
              _PaginationBar(
                currentPage: currentPage,
                totalPages: totalPages,
                onPageChanged: onPageChanged ?? (_) {},
              ),
          ],
        );
      },
    );
  }

  int _calculateCrossAxisCount(
    double width,
    ViewMode mode,
    bool isFixed,
    int? fixedCount,
  ) {
    if (isFixed && fixedCount != null) {
      return fixedCount;
    }

    switch (mode) {
      case ViewMode.poster:
        return (width / LayoutConstants.posterWidth).floor().clamp(2, 7);
      case ViewMode.posterWithTitle:
        return (width / 200).floor().clamp(2, 6);
      case ViewMode.posterWall:
        return (width / 300).floor().clamp(1, 3);
      default:
        return 4;
    }
  }

  Widget _buildGridView(List<Video> displayVideos, int crossAxisCount, double fontSize, bool enableAnimation) {
    final ratio = viewMode == ViewMode.posterWall ? 1.5 : 0.7;
    return GridView.builder(
      padding: const EdgeInsets.all(GlassConstants.spacingMedium),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: ratio,
        crossAxisSpacing: GlassConstants.spacingMedium,
        mainAxisSpacing: GlassConstants.spacingMedium,
      ),
      itemCount: displayVideos.length,
      itemBuilder: (context, index) {
        final card = _VideoCard(
          video: displayVideos[index],
          viewMode: viewMode,
          onTap: onVideoTap,
          onDoubleTap: onVideoDoubleTap,
          onSecondaryTap: onVideoSecondaryTap,
          onFavoriteToggle: onFavoriteToggle,
          fontSize: fontSize,
        );
        final child = enableAnimation
            ? StaggeredItem(index: index, child: card)
            : card;
        return RepaintBoundary(child: child);
      },
    );
  }

  Widget _buildListView(List<Video> displayVideos, double fontSize) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: displayVideos.length,
      itemBuilder: (context, index) {
        return _VideoListItem(
          video: displayVideos[index],
          onTap: onVideoTap,
          onDoubleTap: onVideoDoubleTap,
          onSecondaryTap: onVideoSecondaryTap,
          onFavoriteToggle: onFavoriteToggle,
          fontSize: fontSize,
        );
      },
    );
  }
}

class _VideoCard extends ConsumerStatefulWidget {
  final Video video;
  final ViewMode viewMode;
  final Function(Video)? onTap;
  final Function(Video)? onDoubleTap;
  final Function(Video, Offset)? onSecondaryTap;
  final Function(Video)? onFavoriteToggle;
  final double fontSize;

  const _VideoCard({
    required this.video,
    required this.viewMode,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onFavoriteToggle,
    this.fontSize = 13.0,
  });

  @override
  ConsumerState<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends ConsumerState<_VideoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pureMode = ref.watch(pureModeProvider);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTap: () => widget.onTap?.call(widget.video),
        onDoubleTap: () => widget.onDoubleTap?.call(widget.video),
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTap?.call(widget.video, details.globalPosition),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: pureMode ? _buildPureModeCard() : _buildCardContent(),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    final showTitle = widget.viewMode == ViewMode.posterWithTitle;
    final showWall = widget.viewMode == ViewMode.posterWall;

    if (showWall) {
      return _buildWallCard();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              _buildPoster(showTitle),
              if (widget.video.isWatched || widget.video.watchCount > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility,
                          size: 14,
                          color: AppTheme.successColor,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '已看',
                          style: TextStyle(
                            color: AppTheme.successColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.video.isDeleted && widget.video.isFavorite)
                Positioned(
                  top: (widget.video.isWatched || widget.video.watchCount > 0) ? 38 : 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done, size: 14, color: AppTheme.primaryColor),
                        SizedBox(width: 4),
                        Text('备份', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: _buildFavoriteButton(),
              ),
            ],
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 8),
          Text(
            widget.video.title ?? '未知标题',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.fontSize * 0.93,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWallCard() {
    if (widget.video.isDeleted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildDeletedPlaceholder()),
          const SizedBox(height: 4),
          Text(
            widget.video.title ?? '未知标题',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.fontSize * 0.93,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.video.fanartPath != null)
                  Image.file(
                    File(widget.video.fanartPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 600,
                    gaplessPlayback: true,
                    errorBuilder: AppTheme.imageErrorBuilder,
                  )
                else if (widget.video.posterPath != null)
                  Image.file(
                    File(widget.video.posterPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    gaplessPlayback: true,
                    errorBuilder: AppTheme.imageErrorBuilder,
                  )
                else
                  Container(
                    color: AppTheme.cardColor,
                    child: const Center(
                        child: Icon(Icons.movie,
                            size: 32, color: AppTheme.textSecondary)),
                  ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: _buildFavoriteButton(),
                ),
                if (widget.video.isWatched || widget.video.watchCount > 0)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility,
                              size: 12, color: AppTheme.successColor),
                          SizedBox(width: 3),
                          Text('已看',
                              style: TextStyle(
                                  color: AppTheme.successColor, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                if (widget.video.isDeleted && widget.video.isFavorite)
                  Positioned(
                    top: (widget.video.isWatched || widget.video.watchCount > 0) ? 30 : 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done, size: 12, color: AppTheme.primaryColor),
                          SizedBox(width: 3),
                          Text('备份', style: TextStyle(color: AppTheme.primaryColor, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.video.title ?? '未知标题',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: widget.fontSize * 0.86,
          ),
        ),
      ],
    );
  }

  Widget _buildPoster(bool showTitle) {
    if (widget.video.isDeleted) {
      return _buildDeletedPlaceholder(preferPoster: true);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: _isHovered
                ? AppTheme.primaryColor.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: _isHovered ? 20 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        child: widget.video.posterPath != null
            ? Image.file(
                File(widget.video.posterPath!),
                fit: BoxFit.cover,
                cacheWidth: 400,
                gaplessPlayback: true,
                errorBuilder: AppTheme.imageErrorBuilder,
              )
            : Container(
                color: AppTheme.cardColor,
                child: const Center(
                  child: Icon(
                    Icons.movie,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDeletedPlaceholder({bool preferPoster = false}) {
    final hasBackupPoster = widget.video.posterPath != null;
    final hasBackupFanart = widget.video.fanartPath != null;

    if (hasBackupPoster || hasBackupFanart) {
      final primaryPath = preferPoster
          ? (hasBackupPoster ? widget.video.posterPath! : widget.video.fanartPath!)
          : (hasBackupFanart ? widget.video.fanartPath! : widget.video.posterPath!);

      return ClipRRect(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(primaryPath),
              fit: BoxFit.cover,
              cacheWidth: 400,
              gaplessPlayback: true,
              errorBuilder: AppTheme.imageErrorBuilder,
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '该影片已被删除',
                style: TextStyle(
                  color: AppTheme.warningColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '只能展示部分信息',
                style: TextStyle(
                  color: AppTheme.warningColor.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteButton() {
    return GestureDetector(
      onTap: () => widget.onFavoriteToggle?.call(widget.video),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.video.isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: widget.video.isFavorite
              ? AppTheme.accentColor
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _buildPureModeCard() {
    final showTitle = widget.viewMode == ViewMode.posterWithTitle;
    final showWall = widget.viewMode == ViewMode.posterWall;

    if (widget.video.isDeleted) {
      if (showWall) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildDeletedPlaceholder()),
            const SizedBox(height: 8),
            Text(
              widget.video.extractCode(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: widget.fontSize * 0.93,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildDeletedPlaceholder()),
          if (showTitle) ...[
            const SizedBox(height: 8),
            Text(
              widget.video.extractCode(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: widget.fontSize * 0.93,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    if (showWall) {
      return _buildPureModeWallCard();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(GlassConstants.radiusLarge),
                child: MosaicImage(
                  imagePath:
                      widget.video.fanartPath ?? widget.video.posterPath,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _buildFavoriteButton(),
              ),
            ],
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 8),
          Text(
            widget.video.extractCode(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.fontSize * 0.93,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPureModeWallCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MosaicImage(
                  imagePath:
                      widget.video.fanartPath ?? widget.video.posterPath,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: _buildFavoriteButton(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.video.extractCode(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: widget.fontSize * 0.86,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _VideoListItem extends ConsumerWidget {
  final Video video;
  final Function(Video)? onTap;
  final Function(Video)? onDoubleTap;
  final Function(Video, Offset)? onSecondaryTap;
  final Function(Video)? onFavoriteToggle;
  final double fontSize;

  const _VideoListItem({
    required this.video,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onFavoriteToggle,
    this.fontSize = 12.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pureMode = ref.watch(pureModeProvider);

    if (video.isDeleted) {
      return _buildDeletedListItem();
    }

    if (pureMode) {
      return GestureDetector(
        onTap: () => onTap?.call(video),
        onDoubleTap: () => onDoubleTap?.call(video),
        onSecondaryTapUp: (details) =>
            onSecondaryTap?.call(video, details.globalPosition),
        child: GlassContainer(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 360,
                  height: 202,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MosaicImage(
                        imagePath: video.fanartPath ?? video.posterPath,
                        fit: BoxFit.cover,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(video.extractCode(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600))),
              if (video.isWatched)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility,
                              size: 14, color: AppTheme.successColor),
                          const SizedBox(width: 4),
                          Text('${video.watchCount}',
                              style: const TextStyle(
                                  color: AppTheme.successColor, fontSize: 12))
                        ])),
              const SizedBox(width: 8),
              IconButton(
                  icon: Icon(
                      video.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: video.isFavorite
                          ? AppTheme.accentColor
                          : AppTheme.textSecondary),
                  onPressed: () => onFavoriteToggle?.call(video)),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => onTap?.call(video),
      onDoubleTap: () => onDoubleTap?.call(video),
      onSecondaryTapUp: (details) =>
          onSecondaryTap?.call(video, details.globalPosition),
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 360,
                height: 202,
                child: video.fanartPath != null
                    ? Image.file(
                        File(video.fanartPath!),
                        fit: BoxFit.cover,
                        errorBuilder: AppTheme.imageErrorBuilder,
                      )
                    : video.posterPath != null
                        ? Image.file(
                            File(video.posterPath!),
                            fit: BoxFit.cover,
                            errorBuilder: AppTheme.imageErrorBuilder,
                          )
                        : Container(
                            color: AppTheme.cardColor,
                            child: const Icon(
                              Icons.movie,
                              color: AppTheme.textSecondary,
                            ),
                          ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title ?? '未知标题',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (video.actors.isNotEmpty)
                    Text(
                      video.actors.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (video.isWatched)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility,
                      size: 14,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${video.watchCount}',
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                video.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: video.isFavorite
                    ? AppTheme.accentColor
                    : AppTheme.textSecondary,
              ),
              onPressed: () => onFavoriteToggle?.call(video),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedListItem() {
    final hasBackupPoster = video.posterPath != null;
    final hasBackupFanart = video.fanartPath != null;

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 360,
              height: 202,
              child: (hasBackupPoster || hasBackupFanart)
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasBackupFanart)
                          Image.file(
                            File(video.fanartPath!),
                            fit: BoxFit.cover,
                            errorBuilder: AppTheme.imageErrorBuilder,
                          )
                        else if (hasBackupPoster)
                          Image.file(
                            File(video.posterPath!),
                            fit: BoxFit.cover,
                            errorBuilder: AppTheme.imageErrorBuilder,
                          ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.white,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '该影片已被删除',
                                style: TextStyle(
                                  color: AppTheme.warningColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '只能展示部分信息',
                                style: TextStyle(
                                  color: AppTheme.warningColor.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title ?? '未知标题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (video.isDeleted && video.isFavorite)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done, size: 14, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text('备份', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (video.isWatched)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility, size: 14, color: AppTheme.successColor),
                  const SizedBox(width: 4),
                  Text('${video.watchCount}', style: const TextStyle(color: AppTheme.successColor, fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              video.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: video.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary,
            ),
            onPressed: () => onFavoriteToggle?.call(video),
          ),
        ],
      ),
    );
  }
}

List<Video> sortVideos(List<Video> videos, SortMode mode,
    {int randomKey = 0, bool separateFavorites = false, SmartSortWeights? smartWeights}) {
  final sorted = List<Video>.from(videos);

  void applySort(List<Video> list) {
    switch (mode) {
      case SortMode.titleAsc:
        list.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortMode.titleDesc:
        list.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
      case SortMode.random:
        list.shuffle(Random());
        break;
      case SortMode.recentlyWatchedAsc:
        list.sort((a, b) {
          if (a.lastWatchedTime == null && b.lastWatchedTime == null) return 0;
          if (a.lastWatchedTime == null) return -1;
          if (b.lastWatchedTime == null) return 1;
          return a.lastWatchedTime!.compareTo(b.lastWatchedTime!);
        });
        break;
      case SortMode.recentlyWatchedDesc:
        list.sort((a, b) {
          if (a.lastWatchedTime == null && b.lastWatchedTime == null) return 0;
          if (a.lastWatchedTime == null) return 1;
          if (b.lastWatchedTime == null) return -1;
          return b.lastWatchedTime!.compareTo(a.lastWatchedTime!);
        });
        break;
      case SortMode.smart:
      case SortMode.smartDesc:
        if (smartWeights != null) {
          final service = SmartSortService();
          final isAsc = mode == SortMode.smartDesc;
          list.sort((a, b) {
            final scoreA = service.calculateVideoScore(a, smartWeights);
            final scoreB = service.calculateVideoScore(b, smartWeights);
            final comparison = isAsc
                ? scoreA.compareTo(scoreB)
                : scoreB.compareTo(scoreA);
            if (comparison != 0) return comparison;
            return (a.title ?? '').compareTo(b.title ?? '');
          });
        }
        break;
    }
  }

  if (separateFavorites && mode != SortMode.smart && mode != SortMode.smartDesc) {
    final favs = sorted.where((v) => v.isFavorite).toList();
    final nonFavs = sorted.where((v) => !v.isFavorite).toList();

    if (randomKey > 0) {
      favs.shuffle(Random(randomKey));
      nonFavs.shuffle(Random(randomKey * 31 + 7));
      return [...favs, ...nonFavs];
    }

    applySort(favs);
    applySort(nonFavs);
    return [...favs, ...nonFavs];
  }

  if (randomKey > 0) {
    sorted.shuffle(Random(randomKey));
    return sorted;
  }

  applySort(sorted);
  return sorted;
}

class _PaginationBar extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final Function(int) onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  State<_PaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<_PaginationBar> {
  late TextEditingController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(text: '${widget.currentPage}');
  }

  @override
  void didUpdateWidget(_PaginationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) {
      _pageController.text = '${widget.currentPage}';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: const Icon(Icons.chevron_left),
              onPressed: widget.currentPage > 1
                  ? () => widget.onPageChanged(widget.currentPage - 1)
                  : null,
              color: widget.currentPage > 1 ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${widget.currentPage} / ${widget.totalPages}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: const Icon(Icons.chevron_right),
              onPressed: widget.currentPage < widget.totalPages
                  ? () => widget.onPageChanged(widget.currentPage + 1)
                  : null,
              color: widget.currentPage < widget.totalPages ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 50,
            height: 28,
            child: TextField(
              controller: _pageController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              onSubmitted: (value) {
                final page = int.tryParse(value);
                if (page != null && page >= 1 && page <= widget.totalPages) {
                  widget.onPageChanged(page);
                } else {
                  _pageController.text = '${widget.currentPage}';
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '页',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
