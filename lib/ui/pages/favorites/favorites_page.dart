import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import '../../../core/providers/providers.dart';
import '../../../core/models/models.dart';
import '../../theme/app_theme.dart';
import '../home_page.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
          const Icon(Icons.favorite, color: AppTheme.accentColor, size: 24),
          const SizedBox(width: 12),
          const Text(
            '我的收藏',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: '搜索收藏...',
                  hintStyle: TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
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
                color: AppTheme.accentColor.withValues(alpha: 0.2),
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

class _FavoriteVideosTab extends ConsumerWidget {
  final String searchQuery;
  const _FavoriteVideosTab({this.searchQuery = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(favoriteVideosProvider);
    final viewMode = ref.watch(favoriteViewModeProvider);
    final sortMode = ref.watch(favoriteSortModeProvider);

    return videosAsync.when(
      data: (videos) {
        var filtered = videos;
        if (searchQuery.isNotEmpty) {
          filtered = videos.where((v) =>
            (v.title ?? '').toLowerCase().contains(searchQuery.toLowerCase())
          ).toList();
        }

        filtered = _sortVideos(filtered, sortMode);

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.movie_outlined,
            message: searchQuery.isNotEmpty ? '未找到匹配的影片' : '暂无收藏的影片',
          );
        }

        return Column(
          children: [
            _buildToolbar(context, viewMode, sortMode, ref, filtered),
            Expanded(
              child: VideoGrid(
                videos: filtered,
                viewMode: viewMode,
                isFixedColumnCount: ref.watch(isFixedColumnCountProvider),
                fixedColumnCount: ref.watch(fixedColumnCountProvider),
                onVideoTap: (video) => _showVideoDetail(context, video),
                onFavoriteToggle: (video) => _toggleFavorite(ref, video),
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
            icon: Icon(_getViewModeIcon(viewMode), color: AppTheme.textSecondary, size: 20),
            onSelected: (value) {
              ref.read(favoriteViewModeProvider.notifier).state = value;
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setInt('favorite_view_mode', value.index);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: ViewMode.poster, child: Text('海报')),
              PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('海报+标题')),
              PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
              PopupMenuItem(value: ViewMode.list, child: Text('列表')),
            ],
          ),
          const Spacer(),
          Text(
            '${filtered.length} 个影片',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppTheme.accentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoDetail(BuildContext context, Video video) {
    showDialog(
      context: context,
      builder: (context) => VideoDetailDialog(video: video),
    );
  }

  Future<void> _toggleFavorite(WidgetRef ref, Video video) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.toggleFavorite(video.id!, !video.isFavorite);
    ref.invalidate(favoriteVideosProvider);
    ref.invalidate(allVideosProvider);
  }
}

class _FavoriteActorsTab extends ConsumerWidget {
  final String searchQuery;
  const _FavoriteActorsTab({this.searchQuery = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorsAsync = ref.watch(favoriteActorsProvider);

    return actorsAsync.when(
      data: (actors) {
        var filtered = actors;
        if (searchQuery.isNotEmpty) {
          filtered = actors.where((a) =>
            a.name.toLowerCase().contains(searchQuery.toLowerCase())
          ).toList();
        }

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.people_outline,
            message: searchQuery.isNotEmpty ? '未找到匹配的演员' : '暂无收藏的演员',
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppTheme.accentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
        ],
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

class _FavoriteCategoriesTab extends ConsumerWidget {
  final String searchQuery;
  const _FavoriteCategoriesTab({this.searchQuery = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(favoriteCategoriesProvider);

    return categoriesAsync.when(
      data: (categories) {
        var filtered = categories;
        if (searchQuery.isNotEmpty) {
          filtered = categories.where((c) =>
            c.name.toLowerCase().contains(searchQuery.toLowerCase())
          ).toList();
        }

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.category_outlined,
            message: searchQuery.isNotEmpty ? '未找到匹配的分类' : '暂无收藏的分类',
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppTheme.accentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
        ],
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
            color: AppTheme.accentColor.withValues(alpha: 0.15),
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
          color: typeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: typeColor.withValues(alpha: 0.3),
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
                color: typeColor.withValues(alpha: 0.2),
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
      duration: const Duration(milliseconds: 200),
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
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _scaleAnimation.value > 1.0
                            ? AppTheme.accentColor.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.2),
                        blurRadius: _scaleAnimation.value > 1.0 ? 20 : 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _buildAvatar(),
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

  Widget _buildAvatar() {
    if (widget.actor.avatarUrl != null && widget.actor.avatarUrl!.isNotEmpty) {
      final file = File(widget.actor.avatarUrl!);
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholder();
              },
            );
          }
          return _buildPlaceholder();
        },
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.cardColor,
      child: Center(
        child: Text(
          widget.actor.name.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: AppTheme.accentColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
