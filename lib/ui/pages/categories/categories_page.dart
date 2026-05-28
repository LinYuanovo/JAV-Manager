import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import 'category_videos_page.dart';

enum CategorySortField { name, count }
enum CategorySortOrder { asc, desc }

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _columnCountController = TextEditingController();
  String _searchQuery = '';
  bool _isFixedColumnCount = false;
  int? _fixedColumnCount;
  CategorySortField _sortField = CategorySortField.name;
  CategorySortOrder _sortOrder = CategorySortOrder.asc;
  PaginationMode _paginationMode = PaginationMode.waterfall;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    final initialTabIndex = prefs.getInt('categories_last_tab') ?? 0;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setInt('categories_last_tab', _tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = ref.read(sharedPreferencesProvider);
      setState(() {
        _isFixedColumnCount = prefs.getBool('category_is_fixed_column') ?? false;
        _fixedColumnCount = prefs.getInt('category_fixed_column_count');
        if (_fixedColumnCount != null) {
          _columnCountController.text = _fixedColumnCount.toString();
        }
        final sortFieldIndex = prefs.getInt('category_sort_field') ?? 0;
        final sortOrderIndex = prefs.getInt('category_sort_order') ?? 0;
        _sortField = CategorySortField.values[sortFieldIndex.clamp(0, CategorySortField.values.length - 1)];
        _sortOrder = CategorySortOrder.values[sortOrderIndex.clamp(0, CategorySortOrder.values.length - 1)];
        _paginationMode = PaginationMode.values[(prefs.getInt('category_pagination_mode') ?? 0).clamp(0, PaginationMode.values.length - 1)];
        _currentPage = prefs.getInt('category_current_page') ?? 1;
      });
      _cleanupOrphanedCategories();
    });
  }

  Future<void> _cleanupOrphanedCategories() async {
    try {
      final repository = ref.read(categoryRepositoryProvider);
      final deleted = await repository.deleteOrphanedCategories();
      if (deleted > 0) {
        ref.invalidate(allTagsProvider);
        ref.invalidate(allSeriesProvider);
        ref.invalidate(allStudiosProvider);
      }
    } catch (e) {
      debugPrint('清理孤立分类失败: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _columnCountController.dispose();
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
              _CategoryListView(
                provider: allTagsProvider,
                searchQuery: _searchQuery,
                isFixedColumnCount: _isFixedColumnCount,
                fixedColumnCount: _fixedColumnCount,
                sortField: _sortField,
                sortOrder: _sortOrder,
                paginationMode: _paginationMode,
                currentPage: _currentPage,
                onPageChanged: (page) => setState(() {
                  _currentPage = page;
                  ref.read(sharedPreferencesProvider).setInt('category_current_page', page);
                }),
              ),
              _CategoryListView(
                provider: allSeriesProvider,
                searchQuery: _searchQuery,
                isFixedColumnCount: _isFixedColumnCount,
                fixedColumnCount: _fixedColumnCount,
                sortField: _sortField,
                sortOrder: _sortOrder,
                paginationMode: _paginationMode,
                currentPage: _currentPage,
                onPageChanged: (page) => setState(() {
                  _currentPage = page;
                  ref.read(sharedPreferencesProvider).setInt('category_current_page', page);
                }),
              ),
              _CategoryListView(
                provider: allStudiosProvider,
                searchQuery: _searchQuery,
                isFixedColumnCount: _isFixedColumnCount,
                fixedColumnCount: _fixedColumnCount,
                sortField: _sortField,
                sortOrder: _sortOrder,
                paginationMode: _paginationMode,
                currentPage: _currentPage,
                onPageChanged: (page) => setState(() {
                  _currentPage = page;
                  ref.read(sharedPreferencesProvider).setInt('category_current_page', page);
                }),
              ),
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
            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
            child: const Text('分类', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: GlassSearchBar(
              controller: _searchController,
              hintText: _getSearchHint(),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (value) {
              final parts = value.split('_');
              setState(() {
                _sortField = CategorySortField.values[int.parse(parts[0])];
                _sortOrder = CategorySortOrder.values[int.parse(parts[1])];
              });
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setInt('category_sort_field', _sortField.index);
              prefs.setInt('category_sort_order', _sortOrder.index);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: '0_0',
                child: Row(
                  children: [
                    const Icon(Icons.sort_by_alpha, size: 18),
                    const SizedBox(width: 8),
                    const Text('名称升序'),
                    if (_sortField == CategorySortField.name && _sortOrder == CategorySortOrder.asc)
                      const Icon(Icons.check, size: 16, color: AppTheme.primaryColor),
                  ],
                ),
              ),
              PopupMenuItem(
                value: '0_1',
                child: Row(
                  children: [
                    const Icon(Icons.sort_by_alpha, size: 18),
                    const SizedBox(width: 8),
                    const Text('名称降序'),
                    if (_sortField == CategorySortField.name && _sortOrder == CategorySortOrder.desc)
                      const Icon(Icons.check, size: 16, color: AppTheme.primaryColor),
                  ],
                ),
              ),
              PopupMenuItem(
                value: '1_0',
                child: Row(
                  children: [
                    const Icon(Icons.numbers, size: 18),
                    const SizedBox(width: 8),
                    const Text('数量升序'),
                    if (_sortField == CategorySortField.count && _sortOrder == CategorySortOrder.asc)
                      const Icon(Icons.check, size: 16, color: AppTheme.primaryColor),
                  ],
                ),
              ),
              PopupMenuItem(
                value: '1_1',
                child: Row(
                  children: [
                    const Icon(Icons.numbers, size: 18),
                    const SizedBox(width: 8),
                    const Text('数量降序'),
                    if (_sortField == CategorySortField.count && _sortOrder == CategorySortOrder.desc)
                      const Icon(Icons.check, size: 16, color: AppTheme.primaryColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          _buildPaginationModeButton(),
          const SizedBox(width: 12),
          _buildColumnCountControl(),
        ],
      ),
    );
  }

  String _getSearchHint() {
    switch (_tabController.index) {
      case 0: return '搜索标签...';
      case 1: return '搜索系列...';
      case 2: return '搜索片商...';
      default: return '搜索...';
    }
  }

  Widget _buildPaginationModeButton() {
    final isPaginated = _paginationMode == PaginationMode.paginated;
    return IconButton(
      icon: Icon(
        isPaginated ? Icons.view_agenda : Icons.grid_view,
        color: AppTheme.textSecondary,
      ),
      tooltip: isPaginated ? '切换为瀑布流' : '切换为分页',
      onPressed: () {
        setState(() {
          _paginationMode = isPaginated ? PaginationMode.waterfall : PaginationMode.paginated;
          _currentPage = 1;
        });
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setInt('category_pagination_mode', _paginationMode.index);
        prefs.setInt('category_current_page', 1);
      },
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
            onSubmitted: (value) {
              final prefs = ref.read(sharedPreferencesProvider);
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                setState(() {
                  _fixedColumnCount = count;
                  _isFixedColumnCount = true;
                });
                prefs.setInt('category_fixed_column_count', count);
                prefs.setBool('category_is_fixed_column', true);
              } else {
                setState(() {
                  _isFixedColumnCount = false;
                  _fixedColumnCount = null;
                });
                prefs.remove('category_fixed_column_count');
                prefs.setBool('category_is_fixed_column', false);
                _columnCountController.clear();
              }
            },
          ),
        ),
      ],
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
        indicatorColor: AppTheme.primaryColor,
        indicatorWeight: 3,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: AppTheme.textSecondary,
        tabs: const [
          Tab(text: '标签'),
          Tab(text: '系列'),
          Tab(text: '片商'),
        ],
      ),
    );
  }
}

class _CategoryListView extends ConsumerStatefulWidget {
  final FutureProvider<List<Category>> provider;
  final String searchQuery;
  final bool isFixedColumnCount;
  final int? fixedColumnCount;
  final CategorySortField sortField;
  final CategorySortOrder sortOrder;
  final PaginationMode paginationMode;
  final int currentPage;
  final Function(int)? onPageChanged;

  const _CategoryListView({
    required this.provider,
    required this.searchQuery,
    this.isFixedColumnCount = false,
    this.fixedColumnCount,
    required this.sortField,
    required this.sortOrder,
    this.paginationMode = PaginationMode.waterfall,
    this.currentPage = 1,
    this.onPageChanged,
  });

  @override
  ConsumerState<_CategoryListView> createState() => _CategoryListViewState();
}

class _CategoryListViewState extends ConsumerState<_CategoryListView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final asyncValue = ref.watch(widget.provider);

    return asyncValue.when(
      data: (categories) {
        var filtered = widget.searchQuery.isEmpty
            ? categories
            : categories.where((c) => c.name.toLowerCase().contains(widget.searchQuery.toLowerCase())).toList();

        filtered = filtered.where((c) => c.hasVideos || c.isFavorite).toList();

        filtered = _applySort(filtered);
        return _CategoryGrid(
          categories: filtered,
          isFixedColumnCount: widget.isFixedColumnCount,
          fixedColumnCount: widget.fixedColumnCount,
          paginationMode: widget.paginationMode,
          currentPage: widget.currentPage,
          onPageChanged: widget.onPageChanged,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      error: (error, stack) => Center(child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor))),
    );
  }

  List<Category> _applySort(List<Category> categories) {
    final sorted = List<Category>.from(categories);

    // 收藏优先
    sorted.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));

    // 分组后再按用户选择排序
    final favorites = sorted.where((c) => c.isFavorite).toList();
    final nonFavorites = sorted.where((c) => !c.isFavorite).toList();

    void applyUserSort(List<Category> list) {
      switch (widget.sortField) {
        case CategorySortField.name:
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case CategorySortField.count:
          list.sort((a, b) => a.videoCount.compareTo(b.videoCount));
          break;
      }
      if (widget.sortOrder == CategorySortOrder.desc) {
        final reversed = list.reversed.toList();
        list.clear();
        list.addAll(reversed);
      }
    }

    applyUserSort(favorites);
    applyUserSort(nonFavorites);

    return [...favorites, ...nonFavorites];
  }
}

class _CategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final bool isFixedColumnCount;
  final int? fixedColumnCount;
  final PaginationMode paginationMode;
  final int currentPage;
  final Function(int)? onPageChanged;

  const _CategoryGrid({
    required this.categories,
    this.isFixedColumnCount = false,
    this.fixedColumnCount,
    this.paginationMode = PaginationMode.waterfall,
    this.currentPage = 1,
    this.onPageChanged,
  });

  List<Category> get _paginatedCategories {
    if (paginationMode == PaginationMode.waterfall) {
      return categories;
    }
    const pageSize = 5;
    final start = (currentPage - 1) * pageSize;
    final end = start + pageSize;
    return categories.sublist(start.clamp(0, categories.length), end.clamp(0, categories.length));
  }

  int get _totalPages {
    if (paginationMode == PaginationMode.waterfall) return 1;
    const pageSize = 5;
    return (categories.length / pageSize).ceil().clamp(1, 9999);
  }

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.category_outlined,
        message: '暂无分类',
      );
    }

    final displayCategories = _paginatedCategories;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = isFixedColumnCount && fixedColumnCount != null
                  ? fixedColumnCount!
                  : (constraints.maxWidth / 200).floor().clamp(2, 8);
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: GlassConstants.spacingMedium,
                  mainAxisSpacing: GlassConstants.spacingMedium,
                ),
                itemCount: displayCategories.length,
                itemBuilder: (context, index) => _CategoryCard(category: displayCategories[index]),
              );
            },
          ),
        ),
        if (paginationMode == PaginationMode.paginated && _totalPages > 1)
          _CategoryPaginationBar(
            currentPage: currentPage,
            totalPages: _totalPages,
            onPageChanged: onPageChanged ?? (_) {},
          ),
      ],
    );
  }
}

class _CategoryCard extends ConsumerStatefulWidget {
  final Category category;
  const _CategoryCard({required this.category});

  @override
  ConsumerState<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends ConsumerState<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: GlassConstants.animFast, vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
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
      onEnter: (_) { _controller.forward(); },
      onExit: (_) { _controller.reverse(); },
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CategoryVideosPage(category: widget.category)),
        ),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(scale: _scaleAnimation.value, child: child),
          child: Stack(
            children: [
              GlassContainer(
                color: widget.category.hasVideos
                    ? AppTheme.cardColor.withValues(alpha:0.6)
                    : AppTheme.surfaceColor.withValues(alpha:0.3),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _getDisplayName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.category.hasVideos ? AppTheme.textPrimary : AppTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: widget.category.isFavorite ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.category.videoCount} 部影片',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(alpha:widget.category.hasVideos ? 0.7 : 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary.withValues(alpha:0.5)),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _toggleFavorite,
                  child: Icon(
                    widget.category.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: widget.category.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary.withValues(alpha:0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    try {
      final repository = ref.read(categoryRepositoryProvider);
      await repository.toggleFavorite(widget.category.id!, !widget.category.isFavorite);
      setState(() {});
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

  String _getDisplayName() {
    if (widget.category.name.trim().isNotEmpty) {
      return widget.category.name.trim();
    }
    switch (widget.category.type) {
      case Category.typeSeries:
        return '[未命名系列]';
      case Category.typeTag:
        return '[未命名标签]';
      case Category.typeStudio:
        return '[未命名片商]';
      default:
        return '[未命名]';
    }
  }
}

class _CategoryPaginationBar extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final Function(int) onPageChanged;

  const _CategoryPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  State<_CategoryPaginationBar> createState() => _CategoryPaginationBarState();
}

class _CategoryPaginationBarState extends State<_CategoryPaginationBar> {
  late TextEditingController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(text: '${widget.currentPage}');
  }

  @override
  void didUpdateWidget(_CategoryPaginationBar oldWidget) {
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
    return GlassContainer(
      margin: const EdgeInsets.all(GlassConstants.spacingMedium),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: widget.currentPage > 1
                ? () => widget.onPageChanged(widget.currentPage - 1)
                : null,
            color: widget.currentPage > 1 ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 16),
          Text(
            '${widget.currentPage} / ${widget.totalPages}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: widget.currentPage < widget.totalPages
                ? () => widget.onPageChanged(widget.currentPage + 1)
                : null,
            color: widget.currentPage < widget.totalPages ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 60,
            height: 36,
            child: TextField(
              controller: _pageController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
