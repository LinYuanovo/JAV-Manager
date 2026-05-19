import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/models/models.dart';
import '../../theme/app_theme.dart';
import '../home_page.dart';
import '../actors/actor_detail_page.dart';
import 'video_detail_dialog.dart';

class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({super.key});

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  final _searchController = TextEditingController();
  final _columnCountController = TextEditingController();
  String _searchQuery = '';
  bool _isScanning = false;
  int _randomKey = 0;

  @override
  void initState() {
    super.initState();
    final fixedCount = ref.read(fixedColumnCountProvider);
    _columnCountController.text = fixedCount.toString();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _columnCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videosAsync = _searchQuery.isEmpty
        ? ref.watch(allVideosProvider)
        : ref.watch(searchVideosProvider(_searchQuery));
    final viewMode = ref.watch(viewModeProvider);
    final sortMode = ref.watch(sortModeProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final watchedPath = prefs.getString('watched_path') ?? '';

    return Column(
      children: [
        _buildHeader(sortMode, viewMode),
        Expanded(
          child: videosAsync.when(
            data: (videos) {
              final filteredVideos = watchedPath.isNotEmpty
                  ? videos.where((v) => !v.folderPath.contains(watchedPath)).toList()
                  : videos;
              final sortedVideos = _sortVideos(filteredVideos, sortMode, _randomKey);
              return VideoGrid(
                videos: sortedVideos,
                viewMode: viewMode,
                isFixedColumnCount: ref.watch(isFixedColumnCountProvider),
                fixedColumnCount: ref.watch(fixedColumnCountProvider),
                onVideoTap: (video) => _showVideoDetail(video),
                onVideoDoubleTap: (video) => _playVideo(video),
                onVideoSecondaryTap: (video, offset) => _showContextMenu(video, offset),
                onFavoriteToggle: (video) => _toggleFavorite(video),
              );
            },
            loading: () => Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentGradient.colors.first),
              ),
            ),
            error: (error, stack) => Center(
              child: GlassContainer(
                margin: const EdgeInsets.all(GlassConstants.spacingLarge),
                padding: const EdgeInsets.all(GlassConstants.spacingLarge),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 48),
                    const SizedBox(height: GlassConstants.spacingMedium),
                    Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor)),
                    const SizedBox(height: GlassConstants.spacingMedium),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(allVideosProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(SortMode sortMode, ViewMode viewMode) {
    return GlassContainer(
      margin: const EdgeInsets.all(GlassConstants.spacingMedium),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
            child: const Text('媒体库', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: GlassConstants.spacingLarge),
          Expanded(
            child: GlassSearchBar(
              controller: _searchController,
              hintText: '搜索视频...',
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: GlassConstants.spacingMedium),
          _buildSortButton(sortMode),
          const SizedBox(width: GlassConstants.spacingSmall),
          IconButton(
            icon: const Icon(Icons.shuffle, color: AppTheme.textSecondary),
            tooltip: '随机排序',
            onPressed: () {
              setState(() {
                _randomKey = DateTime.now().millisecondsSinceEpoch;
              });
            },
          ),
          const SizedBox(width: GlassConstants.spacingSmall),
          _buildViewModeButton(viewMode),
          const SizedBox(width: GlassConstants.spacingSmall),
          _buildColumnCountControl(),
          const SizedBox(width: GlassConstants.spacingSmall),
          _buildRefreshButton(),
        ],
      ),
    );
  }

  Widget _buildSortButton(SortMode current) {
    return PopupMenuButton<SortMode>(
      tooltip: '排序方式',
      icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
      onSelected: (value) {
        ref.read(sortModeProvider.notifier).state = value;
        ref.read(sharedPreferencesProvider).setInt('sort_mode', value.index);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: SortMode.titleAsc, child: Text('标题 A-Z')),
        PopupMenuItem(value: SortMode.titleDesc, child: Text('标题 Z-A')),
        PopupMenuItem(value: SortMode.recentlyWatchedDesc, child: Text('最近观看（新→旧）')),
        PopupMenuItem(value: SortMode.recentlyWatchedAsc, child: Text('最近观看（旧→新）')),
      ],
    );
  }

  Widget _buildViewModeButton(ViewMode current) {
    return PopupMenuButton<ViewMode>(
      tooltip: '视图模式',
      icon: Icon(_getViewModeIcon(current), color: AppTheme.textSecondary),
      onSelected: (value) {
        ref.read(viewModeProvider.notifier).state = value;
        ref.read(sharedPreferencesProvider).setInt('view_mode', value.index);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: ViewMode.list, child: Text('列表')),
        PopupMenuItem(value: ViewMode.poster, child: Text('海报图')),
        PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('带标题海报图')),
        PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
      ],
    );
  }

  IconData _getViewModeIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.list:
        return Icons.view_list;
      case ViewMode.poster:
        return Icons.grid_view;
      case ViewMode.posterWithTitle:
        return Icons.grid_on;
      case ViewMode.posterWall:
        return Icons.wallpaper;
    }
  }

  Widget _buildColumnCountControl() {
    final isFixed = ref.watch(isFixedColumnCountProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 50,
          height: 32,
          child: TextField(
            controller: _columnCountController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: '自动',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.5), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
              filled: true,
              fillColor: isFixed ? AppTheme.primaryColor.withValues(alpha:0.1) : Colors.white.withValues(alpha:0.5),
            ),
            onSubmitted: (value) {
              final prefs = ref.read(sharedPreferencesProvider);
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                ref.read(fixedColumnCountProvider.notifier).state = count;
                ref.read(isFixedColumnCountProvider.notifier).state = true;
                prefs.setInt('media_fixed_column_count', count);
                prefs.setBool('media_is_fixed_column', true);
              } else {
                ref.read(isFixedColumnCountProvider.notifier).state = false;
                prefs.remove('media_fixed_column_count');
                prefs.setBool('media_is_fixed_column', false);
                _columnCountController.clear();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return IconButton(
      icon: _isScanning
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
          : const Icon(Icons.refresh, color: AppTheme.textSecondary),
      tooltip: '刷新媒体库',
      onPressed: _isScanning ? null : _refreshMediaLibrary,
    );
  }

  Future<void> _refreshMediaLibrary() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final libraryPath = prefs.getString('library_path') ?? '';
    if (libraryPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置媒体库目录'), backgroundColor: AppTheme.warningColor),
        );
      }
      return;
    }

    setState(() => _isScanning = true);
    try {
      final autoTaskService = ref.read(autoTaskServiceProvider);
      await autoTaskService.runMoveNow();

      final scanner = ref.read(mediaScannerServiceProvider);
      await scanner.scanMediaLibrary(libraryPath);
      ref.invalidate(allVideosProvider);
      ref.invalidate(allActorsProvider);
      ref.invalidate(allTagsProvider);
      ref.invalidate(allSeriesProvider);
      ref.invalidate(allStudiosProvider);
      ref.invalidate(watchedVideosProvider);
      ref.invalidate(favoriteVideosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('媒体库已刷新'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  List<Video> _sortVideos(List<Video> videos, SortMode mode, [int randomKey = 0]) {
    final sorted = List<Video>.from(videos);
    if (randomKey > 0) {
      sorted.shuffle(Random(randomKey));
      return sorted;
    }

    final favorites = sorted.where((v) => v.isFavorite).toList();
    final nonFavorites = sorted.where((v) => !v.isFavorite).toList();

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

    applySort(favorites);
    applySort(nonFavorites);

    return [...favorites, ...nonFavorites];
  }

  void _showVideoDetail(Video video) {
    showDialog(context: context, builder: (context) => VideoDetailDialog(video: video));
  }

  Future<void> _playVideo(Video video) async {
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

    ref.invalidate(allVideosProvider);
    ref.invalidate(watchedVideosProvider);
    ref.invalidate(recentlyWatchedVideosProvider);

    if (kDebugMode) {
      debugPrint('[Media] Video marked as watched: ${video.title}');
      debugPrint('[Media] Video still in media library with watched icon');
    }
  }

  void _showContextMenu(Video video, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), dense: true)),
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            leading: Icon(video.isFavorite ? Icons.favorite : Icons.favorite_border),
            title: Text(video.isFavorite ? '取消收藏' : '收藏'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'watched',
          child: ListTile(
            leading: Icon(video.isWatched ? Icons.visibility_off : Icons.visibility),
            title: Text(video.isWatched ? '取消已观看' : '标记已观看'),
            dense: true,
          ),
        ),
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.folder_open), title: Text('打开文件夹'), dense: true)),
        if (video.actors.isNotEmpty)
          const PopupMenuItem(value: 'actors', child: ListTile(leading: Icon(Icons.person), title: Text('查看演员'), dense: true)),
      ],
    ).then((value) async {
      if (value == null) return;
      final repository = ref.read(videoRepositoryProvider);
      switch (value) {
        case 'play':
          await _playVideo(video);
          break;
        case 'favorite':
          await repository.toggleFavorite(video.id!, !video.isFavorite);
          ref.invalidate(allVideosProvider);
          ref.invalidate(favoriteVideosProvider);
          break;
        case 'watched':
          if (video.isWatched) {
            await repository.resetWatchStatus(video.id!);
          } else {
            await repository.incrementWatchCount(video.id!);
          }
          ref.invalidate(allVideosProvider);
          ref.invalidate(watchedVideosProvider);
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

  void _toggleFavorite(Video video) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.updateVideo(video.copyWith(isFavorite: !video.isFavorite));
    ref.invalidate(allVideosProvider);
    ref.invalidate(favoriteVideosProvider);
  }
}
