import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/actor_avatar.dart';
import '../../widgets/video_grid.dart';
import '../media/video_detail_dialog.dart';
import '../actors/actor_detail_page.dart';
import '../categories/category_videos_page.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    final initialIndex = prefs.getInt('favorites_last_tab') ?? 0;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setInt('favorites_last_tab', _tabController.index);
      }
    });
    final savedQuery = ref.read(favoritesSearchQueryProvider);
    if (savedQuery.isNotEmpty) {
      _searchQuery = savedQuery;
      _searchController.text = savedQuery;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FavoriteVideosTab(searchQuery: _searchQuery),
              _FavoriteActorsTab(searchQuery: _searchQuery),
              _FavoriteCategoriesTab(searchQuery: _searchQuery),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.accentGradient.createShader(bounds),
            child: const Text(
              '我的收藏',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: GlassSearchBar(
              controller: _searchController,
              hintText: '搜索收藏...',
              onChanged: (value) {
                setState(() => _searchQuery = value);
                ref.read(sharedPreferencesProvider).setString('favorites_search_query', value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: GlassConstants.radiusLarge,
      color: Colors.white.withValues(alpha:0.4),
      padding: EdgeInsets.zero,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppTheme.accentColor,
        indicatorWeight: 3,
        labelColor: AppTheme.accentColor,
        unselectedLabelColor: AppTheme.textSecondary,
        tabs: [
          _buildTabWithCount('影片', favoriteVideosProvider),
          _buildTabWithCount('演员', favoriteActorsProvider),
          Tab(text: '分类'),
        ],
      ),
    );
  }

  Widget _buildTabWithCount(String label, ProviderBase<AsyncValue<List<dynamic>>> provider) {
    final asyncValue = ref.watch(provider);
    final count = asyncValue.whenOrNull(data: (items) => items.length) ?? 0;

    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FavoriteVideosTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const _FavoriteVideosTab({this.searchQuery = ''});

  @override
  ConsumerState<_FavoriteVideosTab> createState() => _FavoriteVideosTabState();
}

class _FavoriteVideosTabState extends ConsumerState<_FavoriteVideosTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final videosAsync = ref.watch(favoriteVideosProvider);
    final viewMode = ref.watch(favoriteViewModeProvider);
    final sortMode = ref.watch(favoriteSortModeProvider);
    final paginationMode = ref.watch(favoritesPaginationModeProvider);
    final currentPage = ref.watch(favoritesCurrentPageProvider);

    return videosAsync.when(
      data: (videos) {
        var filtered = videos;
        if (widget.searchQuery.isNotEmpty) {
          filtered = videos.where((v) =>
            (v.title ?? '').toLowerCase().contains(widget.searchQuery.toLowerCase())
          ).toList();
        }

        filtered = sortVideos(filtered, sortMode, separateFavorites: true);

        if (filtered.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.movie_outlined,
            message: widget.searchQuery.isNotEmpty ? '未找到匹配的影片' : '暂无收藏的影片',
          );
        }

        return Column(
          children: [
            _buildToolbar(context, viewMode, sortMode, ref, filtered),
            Expanded(
              child: VideoGrid(
                videos: filtered,
                viewMode: viewMode,
                isFixedColumnCount: ref.watch(favoriteIsFixedColumnCountProvider),
                fixedColumnCount: ref.watch(favoriteFixedColumnCountProvider),
                onVideoTap: (video) => _showVideoDetail(context, video),
                onVideoDoubleTap: (video) => _playVideo(video),
                onVideoSecondaryTap: (video, offset) => _showContextMenu(context, ref, video, offset),
                onFavoriteToggle: (video) => _toggleFavorite(ref, video),
                paginationMode: paginationMode,
                currentPage: currentPage,
                onPageChanged: (page) {
                  ref.read(favoritesCurrentPageProvider.notifier).state = page;
                  ref.read(sharedPreferencesProvider).setInt('favorites_current_page', page);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ),
      error: (error, stack) => Center(
        child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor)),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, ViewMode viewMode, SortMode sortMode, WidgetRef ref, List<Video> filtered) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          PopupMenuButton<SortMode>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary, size: 20),
            onSelected: (value) {
              ref.read(favoriteSortModeProvider.notifier).state = value;
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setInt('favorite_sort_mode', value.index);
              ref.read(favoritesCurrentPageProvider.notifier).state = 1;
              prefs.setInt('favorites_current_page', 1);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.titleAsc, child: Text('标题 A-Z')),
              PopupMenuItem(value: SortMode.titleDesc, child: Text('标题 Z-A')),
              PopupMenuItem(value: SortMode.recentlyWatchedDesc, child: Text('最近观看')),
              PopupMenuItem(value: SortMode.recentlyWatchedAsc, child: Text('最早观看')),
              PopupMenuItem(value: SortMode.random, child: Text('随机排序')),
            ],
          ),
          const SizedBox(width: 12),
          PopupMenuButton<ViewMode>(
            tooltip: '视图模式',
            icon: Icon(getViewModeIcon(viewMode), color: AppTheme.textSecondary, size: 20),
            onSelected: (value) {
              ref.read(favoriteViewModeProvider.notifier).state = value;
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setInt('favorite_view_mode', value.index);
              ref.read(favoritesCurrentPageProvider.notifier).state = 1;
              prefs.setInt('favorites_current_page', 1);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: ViewMode.poster, child: Text('海报')),
              PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('海报+标题')),
              PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
              PopupMenuItem(value: ViewMode.list, child: Text('列表')),
            ],
          ),
          _buildPaginationModeButton(),
          const Spacer(),
          Text(
            '${filtered.length} 个影片',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationModeButton() {
    final paginationMode = ref.watch(favoritesPaginationModeProvider);
    final isPaginated = paginationMode == PaginationMode.paginated;
    return IconButton(
      icon: Icon(
        isPaginated ? Icons.view_agenda : Icons.grid_view,
        color: AppTheme.textSecondary,
      ),
      tooltip: isPaginated ? '切换为瀑布流' : '切换为分页',
      onPressed: () {
        final newMode = isPaginated ? PaginationMode.waterfall : PaginationMode.paginated;
        ref.read(favoritesPaginationModeProvider.notifier).state = newMode;
        ref.read(sharedPreferencesProvider).setInt('favorites_pagination_mode', newMode.index);
        ref.read(favoritesCurrentPageProvider.notifier).state = 1;
        ref.read(sharedPreferencesProvider).setInt('favorites_current_page', 1);
      },
    );
  }

  int _calculatePageSize(BuildContext context, ViewMode viewMode) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = 80.0;
    final paginationBarHeight = 60.0;
    final availableHeight = screenHeight - headerHeight - paginationBarHeight - 40;

    switch (viewMode) {
      case ViewMode.poster:
        final itemHeight = 260.0;
        final rows = (availableHeight / itemHeight).floor().clamp(1, 10);
        final columns = 5;
        return rows * columns;
      case ViewMode.posterWithTitle:
        final itemHeight = 290.0;
        final rows = (availableHeight / itemHeight).floor().clamp(1, 10);
        final columns = 4;
        return rows * columns;
      case ViewMode.posterWall:
        final itemHeight = 350.0;
        final rows = (availableHeight / itemHeight).floor().clamp(1, 10);
        final columns = 2;
        return rows * columns;
      case ViewMode.list:
        return 5;
    }
  }

  void _showVideoDetail(BuildContext context, Video video) {
    showDialog(
      context: context,
      builder: (context) => VideoDetailDialog(video: video),
    );
  }

  Future<void> _toggleFavorite(WidgetRef ref, Video video) async {
    try {
      final repository = ref.read(videoRepositoryProvider);
      final wasFavorite = video.isFavorite;
      await repository.toggleFavorite(video.id!, !wasFavorite);
      final prefs = ref.read(sharedPreferencesProvider);
      final libraryPath = prefs.getString('library_path') ?? '';
      if (libraryPath.isNotEmpty) {
        final scanner = ref.read(mediaScannerServiceProvider);
        if (!wasFavorite) {
          await scanner.backupFavoriteFiles(video, libraryPath);
        } else {
          await scanner.deleteBackupFiles(video, libraryPath);
          if (video.isDeleted) {
            await repository.deleteVideo(video.id!);
          }
        }
      }
      ref.invalidate(favoriteVideosProvider);
      ref.invalidate(allVideosProvider);
    } catch (e) {
      if (mounted) {
        showCopyToast(context, '操作失败: $e');
      }
    }
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, Video video, Offset position) {
    AppTheme.showGlassMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), dense: true)),
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            leading: Icon(video.isFavorite ? Icons.favorite : Icons.favorite_border),
            title: Text(video.isFavorite ? '取消收藏' : '收藏'),
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
          final wasFav = video.isFavorite;
          await repository.toggleFavorite(video.id!, !wasFav);
          final favPrefs = ref.read(sharedPreferencesProvider);
          final libPath = favPrefs.getString('library_path') ?? '';
          if (libPath.isNotEmpty) {
            final scanSvc = ref.read(mediaScannerServiceProvider);
            if (!wasFav) {
              await scanSvc.backupFavoriteFiles(video, libPath);
            } else {
              await scanSvc.deleteBackupFiles(video, libPath);
              if (video.isDeleted) {
                await repository.deleteVideo(video.id!);
              }
            }
          }
          ref.invalidate(favoriteVideosProvider);
          ref.invalidate(allVideosProvider);
          break;
        case 'folder':
          await Process.start('explorer', [video.folderPath], runInShell: true);
          break;
        case 'actors':
          if (video.actors.isNotEmpty && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ActorDetailPage(actor: video.actors.first)),
            );
          }
          break;
      }
    });
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
        showCopyToast(context, '播放失败: $e');
      }
    }

    ref.invalidate(favoriteVideosProvider);
    ref.invalidate(allVideosProvider);
  }
}

class _FavoriteActorsTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const _FavoriteActorsTab({this.searchQuery = ''});

  @override
  ConsumerState<_FavoriteActorsTab> createState() => _FavoriteActorsTabState();
}

class _FavoriteActorsTabState extends ConsumerState<_FavoriteActorsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final actorsAsync = ref.watch(favoriteActorsProvider);

    return actorsAsync.when(
      data: (actors) {
        var filtered = actors;
        if (widget.searchQuery.isNotEmpty) {
          filtered = actors.where((a) =>
            a.name.toLowerCase().contains(widget.searchQuery.toLowerCase())
          ).toList();
        }

        if (filtered.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.people_outline,
            message: widget.searchQuery.isNotEmpty ? '未找到匹配的演员' : '暂无收藏的演员',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = (constraints.maxWidth / 140).floor().clamp(2, 10);

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.75,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                return _ActorCard(
                  actor: filtered[index],
                  onTap: () => _showActorDetail(context, filtered[index]),
                );
              },
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ),
      error: (error, stack) => Center(
        child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor)),
      ),
    );
  }

  void _showActorDetail(BuildContext context, Actor actor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ActorDetailPage(actor: actor),
      ),
    );
  }
}

class _FavoriteCategoriesTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const _FavoriteCategoriesTab({this.searchQuery = ''});

  @override
  ConsumerState<_FavoriteCategoriesTab> createState() => _FavoriteCategoriesTabState();
}

class _FavoriteCategoriesTabState extends ConsumerState<_FavoriteCategoriesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categoriesAsync = ref.watch(favoriteCategoriesProvider);

    return categoriesAsync.when(
      data: (categories) {
        var filtered = categories;
        if (widget.searchQuery.isNotEmpty) {
          filtered = categories.where((c) =>
            c.name.toLowerCase().contains(widget.searchQuery.toLowerCase())
          ).toList();
        }

        if (filtered.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.category_outlined,
            message: widget.searchQuery.isNotEmpty ? '未找到匹配的分类' : '暂无收藏的分类',
          );
        }

        final tags = filtered.where((c) => c.type == Category.typeTag).toList();
        final series = filtered.where((c) => c.type == Category.typeSeries).toList();
        final studios = filtered.where((c) => c.type == Category.typeStudio).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tags.isNotEmpty) ...[
                _buildSectionHeader('标签', tags.length),
                const SizedBox(height: 12),
                _buildCategoryGrid(tags),
              ],
              if (series.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSectionHeader('系列', series.length),
                const SizedBox(height: 12),
                _buildCategoryGrid(series),
              ],
              if (studios.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSectionHeader('片商', studios.length),
                const SizedBox(height: 12),
                _buildCategoryGrid(studios),
              ],
            ],
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ),
      error: (error, stack) => Center(
        child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor)),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppTheme.accentColor,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid(List<Category> categories) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((category) {
        return _CategoryChip(category: category);
      }).toList(),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final Category category;

  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final typeColor = switch (category.type) {
      Category.typeTag => AppTheme.primaryColor,
      Category.typeSeries => AppTheme.secondaryColor,
      Category.typeStudio => AppTheme.accentColor,
      _ => AppTheme.textSecondary,
    };

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CategoryVideosPage(category: category),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha:0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: typeColor.withValues(alpha:0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.name,
              style: TextStyle(
                color: typeColor,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${category.videoCount}',
                style: TextStyle(
                  color: typeColor,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActorCard extends StatefulWidget {
  final Actor actor;
  final VoidCallback onTap;

  const _ActorCard({required this.actor, required this.onTap});

  @override
  State<_ActorCard> createState() => _ActorCardState();
}

class _ActorCardState extends State<_ActorCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: GlassConstants.animFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
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
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _scaleAnimation.value > 1.0
                                ? AppTheme.accentColor.withValues(alpha:0.4)
                                : Colors.black.withValues(alpha:0.2),
                            blurRadius: _scaleAnimation.value > 1.0 ? 20 : 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: ActorAvatar(
                          avatarUrl: widget.actor.avatarUrl,
                          name: widget.actor.name,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.actor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
