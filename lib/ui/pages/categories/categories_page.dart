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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
      });
    });
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
              ),
              _CategoryListView(
                provider: allSeriesProvider,
                searchQuery: _searchQuery,
                isFixedColumnCount: _isFixedColumnCount,
                fixedColumnCount: _fixedColumnCount,
                sortField: _sortField,
                sortOrder: _sortOrder,
              ),
              _CategoryListView(
                provider: allStudiosProvider,
                searchQuery: _searchQuery,
                isFixedColumnCount: _isFixedColumnCount,
                fixedColumnCount: _fixedColumnCount,
                sortField: _sortField,
                sortOrder: _sortOrder,
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
          const Text('分类', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w600)),
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
                decoration: InputDecoration(
                  hintText: _getSearchHint(),
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
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

class _CategoryListView extends ConsumerWidget {
  final FutureProvider<List<Category>> provider;
  final String searchQuery;
  final bool isFixedColumnCount;
  final int? fixedColumnCount;
  final CategorySortField sortField;
  final CategorySortOrder sortOrder;

  const _CategoryListView({
    required this.provider,
    required this.searchQuery,
    this.isFixedColumnCount = false,
    this.fixedColumnCount,
    required this.sortField,
    required this.sortOrder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(provider);

    return asyncValue.when(
      data: (categories) {
        var filtered = searchQuery.isEmpty
            ? categories
            : categories.where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();

        filtered = _applySort(filtered);
        return _CategoryGrid(
          categories: filtered,
          isFixedColumnCount: isFixedColumnCount,
          fixedColumnCount: fixedColumnCount,
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
      switch (sortField) {
        case CategorySortField.name:
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case CategorySortField.count:
          list.sort((a, b) => a.videoCount.compareTo(b.videoCount));
          break;
      }
      if (sortOrder == CategorySortOrder.desc) {
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

  const _CategoryGrid({
    required this.categories,
    this.isFixedColumnCount = false,
    this.fixedColumnCount,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('暂无分类', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 16)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = isFixedColumnCount && fixedColumnCount != null
            ? fixedColumnCount!
            : (constraints.maxWidth / 200).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) => _CategoryCard(category: categories[index]),
        );
      },
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
    _controller = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
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
                    ? AppTheme.cardColor.withValues(alpha: 0.6)
                    : AppTheme.surfaceColor.withValues(alpha: 0.3),
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
                              color: AppTheme.textSecondary.withValues(alpha: widget.category.hasVideos ? 0.7 : 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
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
                    color: widget.category.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary.withValues(alpha: 0.3),
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
    final repository = ref.read(categoryRepositoryProvider);
    await repository.toggleFavorite(widget.category.id!, !widget.category.isFavorite);
    setState(() {});
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
    ref.invalidate(allStudiosProvider);
    ref.invalidate(favoriteCategoriesProvider);
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
