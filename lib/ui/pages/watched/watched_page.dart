import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/models/models.dart';
import '../../theme/app_theme.dart';
import '../actors/actor_detail_page.dart';
import '../home_page.dart';
import '../media/video_detail_dialog.dart';

class WatchedPage extends ConsumerStatefulWidget {
  const WatchedPage({super.key});

  @override
  ConsumerState<WatchedPage> createState() => _WatchedPageState();
}

class _WatchedPageState extends ConsumerState<WatchedPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  SortMode _sortMode = SortMode.recentlyWatchedDesc;
  ViewMode _viewMode = ViewMode.list;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(watchedVideosProvider);

    return Column(
      children: [
        _buildHeader(videosAsync),
        Expanded(
          child: videosAsync.when(
            data: (videos) {
              var filteredVideos = videos;

              if (_searchQuery.isNotEmpty) {
                filteredVideos = videos
                    .where((v) => (v.title ?? '').contains(_searchQuery))
                    .toList();
              }

              filteredVideos = sortVideos(filteredVideos, _sortMode);

              if (filteredVideos.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 64,
                        color: AppTheme.successColor.withValues(alpha:0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无已看记录',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha:0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return _viewMode == ViewMode.list
                  ? _buildVideosList(filteredVideos)
                  : _buildVideosGrid(filteredVideos);
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppTheme.successColor,
              ),
            ),
            error: (error, stack) => Center(
              child: Text(
                '加载失败: $error',
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AsyncValue<List<Video>> videosAsync) {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.visibility,
            color: AppTheme.successColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  '已看',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildCountBadge(videosAsync),
            ],
          ),
          const SizedBox(width: 24),
          PopupMenuButton<SortMode>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.titleAsc, child: Text('标题 A-Z')),
              PopupMenuItem(value: SortMode.titleDesc, child: Text('标题 Z-A')),
              PopupMenuItem(value: SortMode.recentlyWatchedDesc, child: Text('最近观看（新→旧）')),
              PopupMenuItem(value: SortMode.recentlyWatchedAsc, child: Text('最近观看（旧→新）')),
            ],
          ),
          const SizedBox(width: 8),
          PopupMenuButton<ViewMode>(
            tooltip: '视图模式',
            icon: Icon(getViewModeIcon(_viewMode), color: AppTheme.textSecondary),
            onSelected: (v) => setState(() => _viewMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: ViewMode.list, child: Text('列表')),
              PopupMenuItem(value: ViewMode.poster, child: Text('海报图')),
              PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('带标题海报图')),
              PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlassSearchBar(
              controller: _searchController,
              hintText: '搜索已观看影片...',
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(AsyncValue<List<Video>> videosAsync) {
    final count = videosAsync.whenOrNull(data: (videos) => videos.length) ?? 0;
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppTheme.successColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildVideosList(List videos) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        return _WatchedVideoCard(
          video: videos[index],
          onTap: () => _showVideoDetail(videos[index]),
          onDoubleTap: () => _playVideo(videos[index]),
          onSecondaryTap: (offset) => _showContextMenu(videos[index], offset),
        );
      },
    );
  }

  Widget _buildVideosGrid(List<Video> videos) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: VideoGrid(
        videos: videos,
        viewMode: _viewMode,
        onVideoTap: (video) => _showVideoDetail(video),
        onVideoDoubleTap: (video) => _playVideo(video),
        onVideoSecondaryTap: (video, offset) => _showContextMenu(video, offset),
        onFavoriteToggle: (video) => _toggleFavorite(video),
      ),
    );
  }

  Future<void> _toggleFavorite(Video video) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.toggleFavorite(video.id!, !video.isFavorite);
    ref.invalidate(watchedVideosProvider);
    ref.invalidate(allVideosProvider);
    ref.invalidate(favoriteVideosProvider);
  }

  void _showVideoDetail(video) {
    showDialog(
      context: context,
      builder: (context) => VideoDetailDialog(video: video),
    );
  }

  Future<void> _playVideo(dynamic video) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.incrementWatchCount(video.id!);
    final prefs = ref.read(sharedPreferencesProvider);
    final playerPath = prefs.getString('player_path');
    try {
      if (playerPath != null && playerPath.isNotEmpty) {
        await Process.run('cmd', ['/c', 'start', '""', playerPath, video.filePath], runInShell: true);
      } else {
        await Process.run('cmd', ['/c', 'start', '""', video.filePath], runInShell: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
    ref.invalidate(watchedVideosProvider);
    ref.invalidate(allVideosProvider);
    ref.invalidate(recentlyWatchedVideosProvider);
  }

  void _showContextMenu(dynamic video, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), dense: true)),
        const PopupMenuItem(value: 'cancel_watched', child: ListTile(leading: Icon(Icons.visibility_off), title: Text('取消已观看'), dense: true)),
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.folder_open), title: Text('打开文件夹'), dense: true)),
        if (video.actors.isNotEmpty)
          const PopupMenuItem(value: 'actors', child: ListTile(leading: Icon(Icons.person), title: Text('查看演员'), dense: true)),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'play':
          await _playVideo(video);
          break;
        case 'cancel_watched':
          final repository = ref.read(videoRepositoryProvider);
          await repository.resetWatchStatus(video.id!);
          ref.invalidate(watchedVideosProvider);
          ref.invalidate(allVideosProvider);
          break;
        case 'folder':
          await Process.start('explorer', [video.folderPath], runInShell: true);
          break;
        case 'actors':
          if (video.actors.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ActorDetailPage(actor: video.actors.first)),
            );
          }
          break;
      }
    });
  }
}

class _WatchedVideoCard extends ConsumerStatefulWidget {
  final dynamic video;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(Offset)? onSecondaryTap;

  const _WatchedVideoCard({
    required this.video,
    required this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
  });

  @override
  ConsumerState<_WatchedVideoCard> createState() => _WatchedVideoCardState();
}

class _WatchedVideoCardState extends ConsumerState<_WatchedVideoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: GlassConstants.animFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.01).animate(
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
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: (details) => widget.onSecondaryTap?.call(details.globalPosition),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: GlassContainer(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            color: AppTheme.cardColor.withValues(alpha:_isHovered ? 0.7 : 0.5),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
                  child: SizedBox(
                    width: 240,
                    height: 135,
                    child: widget.video.fanartPath != null
                        ? Image.file(
                            File(widget.video.fanartPath!),
                            fit: BoxFit.cover,
                          )
                        : widget.video.posterPath != null
                            ? Image.file(
                                File(widget.video.posterPath!),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppTheme.surfaceColor,
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
                        widget.video.title ?? '未知标题',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.video.actors.isNotEmpty)
                        Text(
                          widget.video.actors.map((a) => a.name).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _buildWatchInfo(),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.successColor.withValues(alpha:0.25),
                        AppTheme.successColor.withValues(alpha:0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_circle_outline,
                        color: AppTheme.successColor,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '再次播放',
                        style: const TextStyle(
                          color: AppTheme.successColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWatchInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility,
              size: 14,
              color: AppTheme.successColor,
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.video.watchCount} 次',
              style: const TextStyle(
                color: AppTheme.successColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (widget.video.lastWatchedTime != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatDate(widget.video.lastWatchedTime),
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha:0.7),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return '今天';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}
