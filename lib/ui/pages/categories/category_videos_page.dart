import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../home_page.dart';
import '../actors/actor_detail_page.dart';
import '../media/video_detail_dialog.dart';

class CategoryVideosPage extends ConsumerStatefulWidget {
  final Category category;

  const CategoryVideosPage({super.key, required this.category});

  @override
  ConsumerState<CategoryVideosPage> createState() => _CategoryVideosPageState();
}

class _CategoryVideosPageState extends ConsumerState<CategoryVideosPage> {
  SortMode _sortMode = SortMode.titleAsc;
  ViewMode _viewMode = ViewMode.posterWithTitle;
  final _columnCountController = TextEditingController();
  bool _isFixedColumnCount = false;
  int? _fixedColumnCount;
  late Category _category;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    final fixedCount = ref.read(fixedColumnCountProvider);
    _fixedColumnCount = fixedCount;
    _isFixedColumnCount = false;
    _columnCountController.text = '';
  }

  @override
  void dispose() {
    _columnCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(videosByCategoryProvider(_category.id!));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Column(
            children: [
              _buildHeader(),
              Expanded(
            child: videosAsync.when(
              data: (videos) {
                if (videos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.movie_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text('该分类暂无影片', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 16)),
                      ],
                    ),
                  );
                }
                final sorted = _sortVideos(videos, _sortMode);
                return VideoGrid(
                  videos: sorted,
                  viewMode: _viewMode,
                  isFixedColumnCount: _isFixedColumnCount,
                  fixedColumnCount: _fixedColumnCount,
                  onVideoTap: (video) => _showVideoDetail(video),
                  onVideoDoubleTap: (video) => _playVideo(video),
                  onVideoSecondaryTap: (video, offset) => _showContextMenu(video, offset),
                  onFavoriteToggle: (video) => _toggleFavorite(video),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
              error: (error, stack) => Center(child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor))),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final typeLabel = switch (_category.type) {
      Category.typeTag => '标签',
      Category.typeSeries => '系列',
      Category.typeStudio => '片商',
      _ => '分类',
    };
    final typeColor = switch (_category.type) {
      Category.typeTag => AppTheme.primaryColor,
      Category.typeSeries => AppTheme.secondaryColor,
      Category.typeStudio => AppTheme.accentColor,
      _ => AppTheme.textSecondary,
    };

    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: AppTheme.textSecondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _category.name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          PopupMenuButton<SortMode>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.titleAsc, child: Text('标题 A-Z')),
              PopupMenuItem(value: SortMode.titleDesc, child: Text('标题 Z-A')),
              PopupMenuItem(value: SortMode.random, child: Text('随机')),
              PopupMenuItem(value: SortMode.recentlyWatchedDesc, child: Text('最近观看（新→旧）')),
              PopupMenuItem(value: SortMode.recentlyWatchedAsc, child: Text('最近观看（旧→新）')),
            ],
          ),
          const SizedBox(width: 8),
          PopupMenuButton<ViewMode>(
            tooltip: '视图模式',
            icon: Icon(_getViewModeIcon(_viewMode), color: AppTheme.textSecondary),
            onSelected: (v) => setState(() => _viewMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: ViewMode.list, child: Text('列表')),
              PopupMenuItem(value: ViewMode.poster, child: Text('海报图')),
              PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('带标题海报图')),
              PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
            ],
          ),
          const SizedBox(width: 8),
          _buildColumnCountControl(),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_category.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _category.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary),
            onPressed: _toggleCategoryFavorite,
          ),
        ],
      ),
    );
  }

  IconData _getViewModeIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.list: return Icons.view_list;
      case ViewMode.poster: return Icons.grid_view;
      case ViewMode.posterWithTitle: return Icons.grid_on;
      case ViewMode.posterWall: return Icons.wallpaper;
    }
  }

  Widget _buildColumnCountControl() {
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
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
              filled: true,
              fillColor: _isFixedColumnCount ? AppTheme.primaryColor.withValues(alpha: 0.1) : AppTheme.backgroundColor.withValues(alpha: 0.5),
            ),
            onSubmitted: (value) {
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                setState(() {
                  _fixedColumnCount = count;
                  _isFixedColumnCount = true;
                });
              } else {
                setState(() {
                  _isFixedColumnCount = false;
                  _fixedColumnCount = null;
                });
                _columnCountController.clear();
              }
            },
          ),
        ),
      ],
    );
  }

  List<Video> _sortVideos(List<Video> videos, SortMode mode) {
    final sorted = List<Video>.from(videos);
    switch (mode) {
      case SortMode.titleAsc:
        sorted.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortMode.titleDesc:
        sorted.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
      case SortMode.random:
        sorted.shuffle(Random());
        break;
      case SortMode.recentlyWatchedAsc:
        sorted.sort((a, b) {
          if (a.lastWatchedTime == null && b.lastWatchedTime == null) return 0;
          if (a.lastWatchedTime == null) return -1;
          if (b.lastWatchedTime == null) return 1;
          return a.lastWatchedTime!.compareTo(b.lastWatchedTime!);
        });
        break;
      case SortMode.recentlyWatchedDesc:
        sorted.sort((a, b) {
          if (a.lastWatchedTime == null && b.lastWatchedTime == null) return 0;
          if (a.lastWatchedTime == null) return 1;
          if (b.lastWatchedTime == null) return -1;
          return b.lastWatchedTime!.compareTo(a.lastWatchedTime!);
        });
        break;
    }
    return sorted;
  }

  void _showVideoDetail(Video video) {
    showDialog(context: context, builder: (_) => VideoDetailDialog(video: video));
  }

  Future<void> _toggleFavorite(Video video) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.toggleFavorite(video.id!, !video.isFavorite);
    ref.invalidate(videosByCategoryProvider(widget.category.id!));
    ref.invalidate(allVideosProvider);
    ref.invalidate(favoriteVideosProvider);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e'), backgroundColor: AppTheme.errorColor));
      }
    }
    ref.invalidate(videosByCategoryProvider(widget.category.id!));
    ref.invalidate(allVideosProvider);
    ref.invalidate(watchedVideosProvider);
  }

  void _showContextMenu(Video video, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), dense: true)),
        PopupMenuItem(value: 'favorite', child: ListTile(leading: Icon(video.isFavorite ? Icons.favorite : Icons.favorite_border), title: Text(video.isFavorite ? '取消收藏' : '收藏'), dense: true)),
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
          ref.invalidate(videosByCategoryProvider(widget.category.id!));
          ref.invalidate(allVideosProvider);
          break;
        case 'folder':
          await Process.start('explorer', [video.folderPath], runInShell: true);
          break;
        case 'actors':
          if (video.actors.isNotEmpty) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActorDetailPage(actor: video.actors.first)));
          }
          break;
      }
    });
  }

  Future<void> _toggleCategoryFavorite() async {
    final newFavoriteState = !_category.isFavorite;
    final repository = ref.read(categoryRepositoryProvider);
    await repository.toggleFavorite(_category.id!, newFavoriteState);

    setState(() {
      _category = _category.copyWith(isFavorite: newFavoriteState);
    });

    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
    ref.invalidate(allStudiosProvider);
    ref.invalidate(favoriteCategoriesProvider);
  }
}
