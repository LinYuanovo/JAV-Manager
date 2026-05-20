import 'dart:io';
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
  late SortMode _sortMode;
  late ViewMode _viewMode;
  final _columnCountController = TextEditingController();
  late bool _isFixedColumnCount;
  int? _fixedColumnCount;
  late Category _category;

  @override
  void initState() {
    super.initState();
    _category = widget.category;

    final prefs = ref.read(sharedPreferencesProvider);
    final sortIndex = prefs.getInt('category_sort_mode') ?? 0;
    final viewIndex = prefs.getInt('category_view_mode') ?? 2;
    _sortMode = SortMode.values[sortIndex];
    _viewMode = ViewMode.values[viewIndex];

    _isFixedColumnCount = prefs.getBool('category_is_fixed_column') ?? false;
    _fixedColumnCount = prefs.getInt('category_fixed_column_count');
    if (_fixedColumnCount != null && _fixedColumnCount! > 0) {
      _columnCountController.text = _fixedColumnCount.toString();
    }
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
                  return const EmptyStateWidget(
                    icon: Icons.movie_outlined,
                    message: '该分类暂无影片',
                  );
                }
                final sorted = sortVideos(videos, _sortMode, separateFavorites: true);
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
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryLightColor)),
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
              gradient: LinearGradient(
                colors: [typeColor.withValues(alpha:0.3), typeColor.withValues(alpha:0.1)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onDoubleTap: () {
                Clipboard.setData(ClipboardData(text: _category.name));
                showCopyToast(context, '已复制$typeLabel');
              },
              child: ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: Text(
                  _category.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          PopupMenuButton<SortMode>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (v) async {
              setState(() => _sortMode = v);
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.setInt('category_sort_mode', v.index);
            },
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
            icon: Icon(getViewModeIcon(_viewMode), color: AppTheme.textSecondary),
            onSelected: (v) async {
              setState(() => _viewMode = v);
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.setInt('category_view_mode', v.index);
            },
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
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.5), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusSmall), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusSmall), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
              filled: true,
              fillColor: _isFixedColumnCount ? AppTheme.primaryColor.withValues(alpha:0.1) : AppTheme.backgroundColor.withValues(alpha:0.5),
            ),
            onSubmitted: (value) async {
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                setState(() {
                  _fixedColumnCount = count;
                  _isFixedColumnCount = true;
                });
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool('category_is_fixed_column', true);
                await prefs.setInt('category_fixed_column_count', count);
              } else {
                setState(() {
                  _isFixedColumnCount = false;
                  _fixedColumnCount = null;
                });
                _columnCountController.clear();
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool('category_is_fixed_column', false);
              }
            },
          ),
        ),
      ],
    );
  }

  void _showVideoDetail(Video video) {
    showDialog(context: context, builder: (_) => VideoDetailDialog(video: video));
  }

  Future<void> _toggleFavorite(Video video) async {
    try {
      final repository = ref.read(videoRepositoryProvider);
      await repository.toggleFavorite(video.id!, !video.isFavorite);
      ref.invalidate(videosByCategoryProvider(widget.category.id!));
      ref.invalidate(allVideosProvider);
      ref.invalidate(favoriteVideosProvider);
    } catch (e) {
      if (mounted) {
        showCopyToast(context, '操作失败: $e');
      }
    }
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
    AppTheme.showGlassMenu(
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
    try {
      final repository = ref.read(categoryRepositoryProvider);
      await repository.toggleFavorite(_category.id!, newFavoriteState);

      setState(() {
        _category = _category.copyWith(isFavorite: newFavoriteState);
      });

      ref.invalidate(allTagsProvider);
      ref.invalidate(allSeriesProvider);
      ref.invalidate(allStudiosProvider);
      ref.invalidate(favoriteCategoriesProvider);
    } catch (e) {
      if (mounted) {
        showCopyToast(context, '操作失败: $e');
      }
    }
  }
}
