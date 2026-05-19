import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/models/models.dart';
import '../../theme/app_theme.dart';
import 'actor_detail_page.dart';

class ActorsPage extends ConsumerStatefulWidget {
  const ActorsPage({super.key});

  @override
  ConsumerState<ActorsPage> createState() => _ActorsPageState();
}

class _ActorsPageState extends ConsumerState<ActorsPage> {
  final _searchController = TextEditingController();
  final _columnCountController = TextEditingController();
  String _searchQuery = '';
  bool _sortByCount = false;
  bool _sortDescending = true;
  bool _isFetchingAvatars = false;
  bool _isFetchingInfo = false;
  int _avatarFetchProgress = 0;
  int _avatarFetchTotal = 0;
  String _avatarFetchCurrentActor = '';
  int _infoFetchProgress = 0;
  int _infoFetchTotal = 0;

  @override
  void initState() {
    super.initState();
    final fixedCount = ref.read(actorFixedColumnCountProvider);
    _columnCountController.text = fixedCount.toString();

    final prefs = ref.read(sharedPreferencesProvider);
    _sortByCount = prefs.getBool('actor_sort_by_count') ?? false;
    _sortDescending = prefs.getBool('actor_sort_descending') ?? true;
  }

  void _saveSortPreferences() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool('actor_sort_by_count', _sortByCount);
    prefs.setBool('actor_sort_descending', _sortDescending);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _columnCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actorsAsync = ref.watch(allActorsProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: actorsAsync.when(
            data: (actors) {
              var filteredActors = actors;
              
              if (_searchQuery.isNotEmpty) {
                filteredActors = actors
                    .where((a) => a.name.contains(_searchQuery))
                    .toList();
              }

              if (_sortByCount) {
                filteredActors.sort((a, b) => _sortDescending
                    ? b.videoCount.compareTo(a.videoCount)
                    : a.videoCount.compareTo(b.videoCount));
              } else {
                filteredActors.sort((a, b) {
                  if (a.isFavorite && !b.isFavorite) return -1;
                  if (!a.isFavorite && b.isFavorite) return 1;
                  return _sortDescending
                      ? b.name.compareTo(a.name)
                      : a.name.compareTo(b.name);
                });
              }

              if (filteredActors.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无演员',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return _buildActorsGrid(filteredActors, fontSize);
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
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

  Widget _buildHeader() {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Text(
            '演员库',
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
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索演员...',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildSortOptions(),
          const SizedBox(width: 12),
          _buildColumnCountControl(),
          const SizedBox(width: 12),
          (_isFetchingAvatars)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_avatarFetchProgress/$_avatarFetchTotal $_avatarFetchCurrentActor',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : TextButton.icon(
                  onPressed: _fetchAvatars,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('获取头像'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                  ),
                ),
          const SizedBox(width: 8),
          (_isFetchingInfo)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '信息 $_infoFetchProgress/$_infoFetchTotal',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : TextButton.icon(
                  onPressed: _fetchAllActorInfo,
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('获取信息'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSortOptions() {
    return Row(
      children: [
        _buildSortChip(
          label: '名称',
          isSelected: !_sortByCount,
          onTap: () {
            setState(() {
              _sortByCount = false;
            });
            _saveSortPreferences();
          },
        ),
        const SizedBox(width: 8),
        _buildSortChip(
          label: '影片数量',
          isSelected: _sortByCount,
          onTap: () {
            setState(() {
              _sortByCount = true;
            });
            _saveSortPreferences();
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            _sortDescending
                ? Icons.arrow_downward
                : Icons.arrow_upward,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          onPressed: () {
            setState(() {
              _sortDescending = !_sortDescending;
            });
            _saveSortPreferences();
          },
        ),
      ],
    );
  }

  Widget _buildSortChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : AppTheme.surfaceColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildColumnCountControl() {
    final isFixed = ref.watch(isActorFixedColumnCountProvider);
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
              fillColor: isFixed ? AppTheme.primaryColor.withValues(alpha: 0.1) : AppTheme.backgroundColor.withValues(alpha: 0.5),
            ),
            onSubmitted: (value) {
              final prefs = ref.read(sharedPreferencesProvider);
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                ref.read(actorFixedColumnCountProvider.notifier).state = count;
                ref.read(isActorFixedColumnCountProvider.notifier).state = true;
                prefs.setInt('actor_fixed_column_count', count);
                prefs.setBool('actor_is_fixed_column', true);
              } else {
                ref.read(isActorFixedColumnCountProvider.notifier).state = false;
                prefs.remove('actor_fixed_column_count');
                prefs.setBool('actor_is_fixed_column', false);
                _columnCountController.clear();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActorsGrid(List<Actor> actors, double fontSize) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(
          constraints.maxWidth,
        );

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.75,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: actors.length,
          itemBuilder: (context, index) {
            return _ActorCard(
              actor: actors[index],
              onTap: () => _showActorDetail(actors[index]),
              onFavoriteToggle: () => _toggleFavorite(actors[index]),
              fontSize: fontSize * 0.93,
            );
          },
        );
      },
    );
  }

  int _calculateCrossAxisCount(double width) {
    final isFixed = ref.watch(isActorFixedColumnCountProvider);
    if (isFixed) {
      final fixedCount = ref.watch(actorFixedColumnCountProvider);
      return fixedCount.clamp(2, 10);
    }
    return (width / 140).floor().clamp(2, 10);
  }

  Future<void> _fetchAvatars() async {
    if (_isFetchingAvatars) return;

    final actorsAsync = ref.read(allActorsProvider);
    final actors = actorsAsync.valueOrNull;
    if (actors == null || actors.isEmpty) return;

    setState(() {
      _isFetchingAvatars = true;
      _avatarFetchProgress = 0;
      _avatarFetchTotal = actors.length;
      _avatarFetchCurrentActor = '';
    });

    try {
      final avatarService = ref.read(avatarServiceProvider);
      final count = await avatarService.fetchAvatarsForActors(
        actors,
        onProgress: (current, total, actorName) {
          if (mounted) {
            setState(() {
              _avatarFetchProgress = current;
              _avatarFetchTotal = total;
              _avatarFetchCurrentActor = actorName;
            });
          }
        },
      );

      ref.invalidate(allActorsProvider);
      ref.invalidate(favoriteActorsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('头像获取完成，成功获取 $count 个'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('头像获取失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isFetchingAvatars = false;
      });
    }
  }

  Future<void> _fetchAllActorInfo() async {
    if (_isFetchingInfo) return;

    final actorsAsync = ref.read(allActorsProvider);
    final actors = actorsAsync.valueOrNull;
    if (actors == null || actors.isEmpty) return;

    final actorsWithoutInfo = actors
        .where((a) => a.infoJson == null || a.infoJson!.isEmpty)
        .toList();

    if (actorsWithoutInfo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('所有演员都已拥有信息'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
      return;
    }

    setState(() {
      _isFetchingInfo = true;
      _infoFetchProgress = 0;
      _infoFetchTotal = actorsWithoutInfo.length;
    });

    try {
      final wikipediaService = ref.read(wikipediaServiceProvider);
      final actorRepo = ref.read(actorRepositoryProvider);
      int successCount = 0;
      const batchSize = 5;

      for (var i = 0; i < actorsWithoutInfo.length; i += batchSize) {
        final end = (i + batchSize > actorsWithoutInfo.length) ? actorsWithoutInfo.length : i + batchSize;
        final batch = actorsWithoutInfo.sublist(i, end);

        final results = await Future.wait(batch.map((actor) async {
          try {
            final info = await wikipediaService.fetchActorInfo(actor.name);
            if (info != null && info.isNotEmpty) {
              await actorRepo.updateActorInfo(actor.id!, info);
              return true;
            }
            return false;
          } catch (e) {
            return false;
          }
        }));

        successCount += results.where((r) => r).length;

        if (mounted) {
          setState(() {
            _infoFetchProgress = end;
          });
        }

        if (end < actorsWithoutInfo.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      ref.invalidate(allActorsProvider);
      ref.invalidate(favoriteActorsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('信息获取完成，成功获取 $successCount/${actorsWithoutInfo.length} 个演员信息'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('信息获取失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isFetchingInfo = false;
      });
    }
  }

  void _showActorDetail(Actor actor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ActorDetailPage(actor: actor),
      ),
    );
  }

  Future<void> _toggleFavorite(Actor actor) async {
    final repository = ref.read(actorRepositoryProvider);
    await repository.toggleFavorite(actor.id!, !actor.isFavorite);
    ref.invalidate(allActorsProvider);
    ref.invalidate(favoriteActorsProvider);
  }
}

class _ActorCard extends StatefulWidget {
  final Actor actor;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final double fontSize;

  const _ActorCard({
    required this.actor,
    required this.onTap,
    required this.onFavoriteToggle,
    this.fontSize = 13.0,
  });

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
            final isHovered = _scaleAnimation.value > 1.0;
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _scaleAnimation.value > 1.0
                                ? AppTheme.primaryColor.withValues(alpha: 0.3)
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
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: widget.onFavoriteToggle,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.actor.isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 16,
                            color: widget.actor.isFavorite
                                ? AppTheme.accentColor
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (widget.actor.videoCount > 0)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.actor.videoCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.actor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _scaleAnimation.value > 1.0
                      ? AppTheme.primaryColor
                      : AppTheme.textPrimary,
                  fontSize: widget.fontSize,
                  fontWeight:
                      widget.actor.isFavorite ? FontWeight.w600 : FontWeight.normal,
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
            color: AppTheme.primaryColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
