import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/providers/providers.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';
import 'media/media_page.dart';
import 'actors/actors_page.dart';
import 'categories/categories_page.dart';
import 'favorites/favorites_page.dart';
import 'watched/watched_page.dart';
import 'settings/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WindowListener {
  bool _isSidebarExpanded = true;
  double _sidebarWidth = 220;
  double _minSidebarWidth = 70;
  double _maxSidebarWidth = 280;
  Size? _lastNormalSize;
  Offset? _lastNormalPosition;
  StreamSubscription? _autoMoveSubscription;

  int get _mediaCount {
    final asyncVideos = ref.watch(allVideosProvider);
    return asyncVideos.whenOrNull(data: (videos) => videos.length) ?? ref.read(mediaCountStateProvider);
  }

  int get _actorCount {
    final asyncActors = ref.watch(allActorsProvider);
    return asyncActors.whenOrNull(data: (actors) => actors.length) ?? 0;
  }

  int get _watchedCount {
    final asyncVideos = ref.watch(watchedVideosProvider);
    return asyncVideos.whenOrNull(data: (videos) => videos.length) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.ensureInitialized();

      final prefs = ref.read(sharedPreferencesProvider);
      final width = prefs.getDouble('window_width') ?? 1400;
      final height = prefs.getDouble('window_height') ?? 900;
      final x = prefs.getDouble('window_x');
      final y = prefs.getDouble('window_y');
      final isMaximized = prefs.getBool('window_maximized') ?? false;

      if (isMaximized) {
        await windowManager.setSize(Size(width, height));
        if (x != null && y != null) {
          await windowManager.setPosition(Offset(x, y));
        }
        await windowManager.maximize();
      } else {
        await windowManager.setSize(Size(width, height));
        if (x != null && y != null) {
          await windowManager.setPosition(Offset(x, y));
        }
      }

      final autoTask = ref.read(autoTaskServiceProvider);
      if (!autoTask.isRunning) {
        autoTask.start();
      }

      // 监听自动整理完成事件，刷新媒体库
      _autoMoveSubscription = autoTask.onAutoMoveComplete.listen((movedCount) {
        if (mounted && movedCount > 0) {
          setState(() {
            ref.invalidate(allVideosProvider);
            ref.invalidate(watchedVideosProvider);
            ref.invalidate(favoriteVideosProvider);

            // 更新媒体计数（减去移动的数量）
            final currentCount = ref.read(mediaCountStateProvider);
            ref.read(mediaCountStateProvider.notifier).state = (currentCount - movedCount).clamp(0, 99999);
          });
        }
      });

      // 初始化媒体计数
      _syncMediaCount();
    });
  }

  @override
  void onWindowClose() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final isMaximized = await windowManager.isMaximized();
    Size size;
    Offset position;

    if (isMaximized && _lastNormalSize != null) {
      size = _lastNormalSize!;
      position = _lastNormalPosition ?? await windowManager.getPosition();
    } else {
      size = await windowManager.getSize();
      position = await windowManager.getPosition();
    }

    await prefs.setBool('window_maximized', isMaximized);
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
    await prefs.setDouble('window_x', position.dx);
    await prefs.setDouble('window_y', position.dy);

    await windowManager.destroy();
  }

  @override
  void onWindowResize() async {
    final isMax = await windowManager.isMaximized();
    if (!isMax) {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _lastNormalSize = size;
      _lastNormalPosition = pos;
    }
  }

  void _syncMediaCount() {
    final asyncVideos = ref.read(allVideosProvider);
    asyncVideos.whenOrNull(data: (videos) {
      if (mounted) {
        ref.read(mediaCountStateProvider.notifier).state = videos.length;
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _autoMoveSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedNavIndexProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          _buildTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(selectedIndex),
                Expanded(
                  child: _buildContent(selectedIndex),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassConstants.blurMedium,
            sigmaY: GlassConstants.blurMedium,
          ),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.7),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha:0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(
                  Icons.video_library_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                ShaderMask(
                  shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                  child: const Text(
                    'JAV Manager',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                _buildWindowButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWindowButtons() {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.remove,
          onPressed: () => windowManager.minimize(),
        ),
        _WindowButton(
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          isClose: true,
        ),
      ],
    );
  }

  Widget _buildSidebar(int selectedIndex) {
    final fontSize = ref.watch(fontSizeProvider);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth - details.delta.dx)
                .clamp(_minSidebarWidth, _maxSidebarWidth);
            _isSidebarExpanded = _sidebarWidth > 100;
          });
        },
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: GlassConstants.blurMedium,
              sigmaY: GlassConstants.blurMedium,
            ),
            child: Container(
              width: _sidebarWidth,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.4),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha:0.2),
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildNavItem(
                    index: 0,
                    icon: Icons.movie_outlined,
                    selectedIcon: Icons.movie,
                    label: '媒体',
                    selectedIndex: selectedIndex,
                    count: _mediaCount,
                    fontSize: fontSize,
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.people_outline,
                    selectedIcon: Icons.people,
                    label: '演员',
                    selectedIndex: selectedIndex,
                    count: _actorCount,
                    fontSize: fontSize,
                  ),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.category_outlined,
                    selectedIcon: Icons.category,
                    label: '分类',
                    selectedIndex: selectedIndex,
                    fontSize: fontSize,
                  ),
                  _buildNavItem(
                    index: 3,
                    icon: Icons.favorite_outline,
                    selectedIcon: Icons.favorite,
                    label: '收藏',
                    selectedIndex: selectedIndex,
                    fontSize: fontSize,
                  ),
                  _buildNavItem(
                    index: 4,
                    icon: Icons.visibility_outlined,
                    selectedIcon: Icons.visibility,
                    label: '已看',
                    selectedIndex: selectedIndex,
                    count: _watchedCount,
                    fontSize: fontSize,
                  ),
                  const Spacer(),
                  _buildNavItem(
                    index: 5,
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: '设置',
                    selectedIndex: selectedIndex,
                    fontSize: fontSize,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int selectedIndex,
    int? count,
    double fontSize = 14.0,
  }) {
    final isSelected = index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          onTap: () {
            ref.read(selectedNavIndexProvider.notifier).state = index;
          },
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarExpanded ? 16 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha:0.15),
                        AppTheme.secondaryColor.withValues(alpha:0.15),
                      ],
                    )
                  : null,
              color: isSelected ? null : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha:0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: _isSidebarExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                  size: 22,
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      fontSize: fontSize,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
                if (count != null && count > 0 && _isSidebarExpanded)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                AppTheme.primaryColor.withValues(alpha:0.8),
                                AppTheme.secondaryColor.withValues(alpha:0.8),
                              ],
                            )
                          : null,
                      color: isSelected ? null : AppTheme.textSecondary.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 18),
                    child: Text(
                      count > 0 ? '$count' : '',
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                        fontSize: (fontSize * 0.78).clamp(9, 14),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return const MediaPage();
      case 1:
        return const ActorsPage();
      case 2:
        return const CategoriesPage();
      case 3:
        return const FavoritesPage();
      case 4:
        return const WatchedPage();
      case 5:
        return const SettingsPage();
      default:
        return const MediaPage();
    }
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          width: 46,
          height: 40,
          color: _isHovered
              ? (widget.isClose
                  ? AppTheme.accentColor.withValues(alpha:0.8)
                  : Colors.white.withValues(alpha:0.15))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose
                ? Colors.white
                : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class VideoGrid extends ConsumerWidget {
  final List<Video> videos;
  final ViewMode viewMode;
  final bool isFixedColumnCount;
  final int? fixedColumnCount;
  final Function(Video)? onVideoTap;
  final Function(Video)? onVideoDoubleTap;
  final Function(Video, Offset)? onVideoSecondaryTap;
  final Function(Video)? onFavoriteToggle;

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
  });

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
              color: AppTheme.textSecondary.withValues(alpha:0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无视频',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha:0.5),
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

        switch (viewMode) {
          case ViewMode.list:
            return _buildListView(fontSize);
          default:
            return _buildGridView(crossAxisCount, fontSize, enableAnimation);
        }
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
        return (width / 180).floor().clamp(2, 7);   // max 7 columns
      case ViewMode.posterWithTitle:
        return (width / 200).floor().clamp(2, 6);     // max 6 columns
      case ViewMode.posterWall:
        return (width / 300).floor().clamp(1, 3);     // max 3 columns
      default:
        return 4;
    }
  }

  Widget _buildGridView(int crossAxisCount, double fontSize, bool enableAnimation) {
    final ratio = viewMode == ViewMode.posterWall ? 1.5 : 0.7;
    return GridView.builder(
      padding: const EdgeInsets.all(GlassConstants.spacingMedium),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: ratio,
        crossAxisSpacing: GlassConstants.spacingMedium,
        mainAxisSpacing: GlassConstants.spacingMedium,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final card = _VideoCard(
          video: videos[index],
          viewMode: viewMode,
          onTap: onVideoTap,
          onDoubleTap: onVideoDoubleTap,
          onSecondaryTap: onVideoSecondaryTap,
          onFavoriteToggle: onFavoriteToggle,
          fontSize: fontSize,
        );
        if (!enableAnimation) return card;
        return StaggeredItem(
          index: index,
          child: card,
        );
      },
    );
  }

  Widget _buildListView(double fontSize) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        return _VideoListItem(
          video: videos[index],
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

class _VideoCard extends StatefulWidget {
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
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard>
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
        onSecondaryTapUp: (details) => widget.onSecondaryTap?.call(widget.video, details.globalPosition),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: _buildCardContent(),
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
                      color: AppTheme.successColor.withValues(alpha:0.15),
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
                  )
                else if (widget.video.posterPath != null)
                  Image.file(
                    File(widget.video.posterPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    gaplessPlayback: true,
                  )
                else
                  Container(
                    color: AppTheme.cardColor,
                    child: const Center(child: Icon(Icons.movie, size: 32, color: AppTheme.textSecondary)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha:0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility, size: 12, color: AppTheme.successColor),
                          SizedBox(width: 3),
                          Text('已看', style: TextStyle(color: AppTheme.successColor, fontSize: 10)),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: _isHovered
                ? AppTheme.primaryColor.withValues(alpha:0.2)
                : Colors.black.withValues(alpha:0.2),
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

  Widget _buildFavoriteButton() {
    return GestureDetector(
      onTap: () => widget.onFavoriteToggle?.call(widget.video),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.8),
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.video.isFavorite
              ? Icons.favorite
              : Icons.favorite_border,
          size: 18,
          color: widget.video.isFavorite
              ? AppTheme.accentColor
              : Colors.white.withValues(alpha:0.9),
        ),
      ),
    );
  }
}

class _VideoListItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap?.call(video),
      onDoubleTap: () => onDoubleTap?.call(video),
      onSecondaryTapUp: (details) => onSecondaryTap?.call(video, details.globalPosition),
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
                      )
                    : video.posterPath != null
                        ? Image.file(
                            File(video.posterPath!),
                            fit: BoxFit.cover,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha:0.1),
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
}

List<Video> sortVideos(List<Video> videos, SortMode mode, {int randomKey = 0, bool separateFavorites = false}) {
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
    }
  }

  if (separateFavorites) {
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
