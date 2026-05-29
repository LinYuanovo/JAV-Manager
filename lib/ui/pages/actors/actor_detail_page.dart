import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../core/utils/app_paths.dart';
import '../../theme/app_theme.dart';
import '../../widgets/actor_avatar.dart';
import '../../widgets/video_grid.dart';
import '../media/video_detail_dialog.dart';

class ActorDetailPage extends ConsumerStatefulWidget {
  final Actor actor;

  const ActorDetailPage({super.key, required this.actor});

  @override
  ConsumerState<ActorDetailPage> createState() => _ActorDetailPageState();
}

class _ActorDetailPageState extends ConsumerState<ActorDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Actor _actor;
  bool _isLoadingInfo = false;
  late SortMode _sortMode;
  late ViewMode _viewMode;
  int _avatarKey = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _actor = widget.actor;

    final prefs = ref.read(sharedPreferencesProvider);
    final sortIndex = prefs.getInt('actor_sort_mode') ?? 0;
    final viewIndex = prefs.getInt('actor_view_mode') ?? 2;
    _sortMode = SortMode.values[sortIndex];
    _viewMode = ViewMode.values[viewIndex];

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _fetchActorInfo();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchActorInfo({bool force = false}) async {
    // Don't re-fetch if data already exists (unless forced by user clicking refresh)
    if (!force && _actor.infoJson != null && _actor.infoJson!.isNotEmpty) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingInfo = true;
    });

    try {
      final wikipediaService = ref.read(wikipediaServiceProvider);
      final info = await wikipediaService.fetchActorInfo(_actor.name);

      if (info != null && info.isNotEmpty) {
        final actorRepo = ref.read(actorRepositoryProvider);
        await actorRepo.updateActorInfo(_actor.id!, info);
        if (!mounted) return;
        // Reload merged data from DB
        final updatedActor = await actorRepo.getActorById(_actor.id!);
        setState(() {
          _actor = updatedActor ?? _actor.copyWith(infoJson: info);
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch actor info: $e');
    }

    if (!mounted) return;
    setState(() {
      _isLoadingInfo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(videosByActorProvider(_actor.id!));

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoPanel(),
                    Expanded(
                      child: _buildVideosPanel(videosAsync),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurLarge,
          sigmaY: GlassConstants.blurLarge,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
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
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: AppTheme.textSecondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  '演员详情',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _actor.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _actor.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary.withValues(alpha:0.8),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return RepaintBoundary(
    child: ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurMedium,
          sigmaY: GlassConstants.blurMedium,
        ),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.4),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha:0.2),
              ),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(90),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha:0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipOval(
                        child: ActorAvatar(
                          key: ValueKey(_avatarKey),
                          avatarUrl: _actor.avatarUrl,
                          name: _actor.name,
                          placeholderFontSize: 64,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _showAvatarSelectionDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.photo_camera,
                              size: 18,
                              color: Colors.white.withValues(alpha:0.85),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(ClipboardData(text: _actor.name));
                    showCopyToast(context, '已复制演员名');
                  },
                  child: Text(
                    _actor.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_actor.videoCount} 部作品',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _buildInfoCard(),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildInfoCard() {
    final info = _actor.infoJson;
    final hasInfo = info != null && info.isNotEmpty;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '演员信息',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isLoadingInfo)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primaryColor,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => _fetchActorInfo(force: true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(hasInfo ? '刷新信息' : '获取信息'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasInfo) ...[
            _buildInfoRow(Icons.cake, '出生日期', _actor.birthDate ?? '未知'),
            _buildInfoRow(Icons.height, '身高', _actor.height != null ? '${_actor.height} cm' : '未知'),
            _buildInfoRow(Icons.monitor_weight, '体重', _actor.weight != null ? '${_actor.weight} kg' : '未知'),
            if (_actor.bust != null || _actor.waist != null || _actor.hip != null)
              _buildInfoRow(
                Icons.straighten,
                '三围',
                '${[
                  if (_actor.bust != null) _actor.bust,
                  if (_actor.waist != null) _actor.waist,
                  if (_actor.hip != null) _actor.hip,
                ].join(' - ')} cm',
              ),
            if (_actor.cupSize != null)
              _buildInfoRow(Icons.accessibility, '罩杯', _actor.cupSize!),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: AppTheme.textSecondary.withValues(alpha:0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '点击获取按钮从 Wikipedia 加载演员信息',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha:0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosPanel(AsyncValue<List<Video>> videosAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: const Text('出演作品', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              videosAsync.whenOrNull(
                data: (videos) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(12)),
                  child: Text('${videos.length}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ) ?? const SizedBox(),
              const Spacer(),
              PopupMenuButton<SortMode>(
                tooltip: '排序方式',
                icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
                onSelected: (v) async {
                  setState(() => _sortMode = v);
                  final prefs = ref.read(sharedPreferencesProvider);
                  await prefs.setInt('actor_sort_mode', v.index);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: SortMode.titleAsc, child: Text('标题 A-Z')),
                  PopupMenuItem(value: SortMode.titleDesc, child: Text('标题 Z-A')),
                  PopupMenuItem(value: SortMode.random, child: Text('随机')),
                  PopupMenuItem(value: SortMode.recentlyWatchedDesc, child: Text('最近观看')),
                ],
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ViewMode>(
                tooltip: '视图模式',
                icon: Icon(getViewModeIcon(_viewMode), color: AppTheme.textSecondary),
                onSelected: (v) async {
                  setState(() => _viewMode = v);
                  final prefs = ref.read(sharedPreferencesProvider);
                  await prefs.setInt('actor_view_mode', v.index);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: ViewMode.list, child: Text('列表')),
                  PopupMenuItem(value: ViewMode.poster, child: Text('海报图')),
                  PopupMenuItem(value: ViewMode.posterWithTitle, child: Text('带标题海报图')),
                  PopupMenuItem(value: ViewMode.posterWall, child: Text('海报墙')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: videosAsync.when(
            data: (videos) {
              if (videos.isEmpty) {
                return const EmptyStateWidget(
                  icon: Icons.movie_outlined,
                  message: '暂无出演作品',
                );
              }
              final sorted = sortVideos(videos, _sortMode, separateFavorites: true);
              return VideoGrid(
                videos: sorted,
                viewMode: _viewMode,
                onVideoTap: (video) => _showVideoDetail(video),
                onVideoDoubleTap: (video) => _playVideo(video),
                onVideoSecondaryTap: (video, offset) => _showContextMenu(video, offset),
                onFavoriteToggle: (video) => _toggleVideoFavorite(video),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
            error: (error, stack) => Center(child: Text('加载失败: $error', style: const TextStyle(color: AppTheme.errorColor))),
          ),
        ),
      ],
    );
  }

  void _showVideoDetail(Video video) {
    showDialog(
      context: context,
      builder: (context) => VideoDetailDialog(video: video),
    );
  }

  Future<void> _toggleFavorite() async {
    try {
      final repository = ref.read(actorRepositoryProvider);
      await repository.toggleFavorite(_actor.id!, !_actor.isFavorite);
      ref.invalidate(allActorsProvider);
      ref.invalidate(favoriteActorsProvider);
      setState(() {
        _actor = _actor.copyWith(isFavorite: !_actor.isFavorite);
      });
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
    ref.invalidate(videosByActorProvider(_actor.id!));
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
          final libPath = ref.read(sharedPreferencesProvider).getString('library_path') ?? '';
          if (libPath.isNotEmpty) {
            final scanner = ref.read(mediaScannerServiceProvider);
            if (!wasFav) {
              await scanner.backupFavoriteFiles(video, libPath);
            } else {
              await scanner.deleteBackupFiles(video, libPath);
            }
          }
          ref.invalidate(videosByActorProvider(_actor.id!));
          ref.invalidate(allVideosProvider);
          break;
        case 'folder':
          await Process.start('explorer', [video.folderPath], runInShell: true);
          break;
      }
    });
  }

  Future<void> _toggleVideoFavorite(Video video) async {
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
        }
      }
      ref.invalidate(videosByActorProvider(_actor.id!));
      ref.invalidate(allVideosProvider);
      ref.invalidate(favoriteVideosProvider);
    } catch (e) {
      if (mounted) {
        showCopyToast(context, '操作失败: $e');
      }
    }
  }

  Future<void> _showAvatarSelectionDialog() async {
    final avatarService = ref.read(avatarServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: avatarService.fetchFiletree(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return AlertDialog(
                title: const Text('获取头像列表失败'),
                content: const Text('无法连接到头像服务器，请稍后重试'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }

            final filetree = snapshot.data!;
            final urls = avatarService.findAllAvatarUrls(filetree, _actor.name);

            if (urls.isEmpty) {
              return AlertDialog(
                title: const Text('未找到头像'),
                content: Text('未找到 ${_actor.name} 的可用头像'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }

            return _AvatarSelectionDialog(
              actorName: _actor.name,
              avatarUrls: urls,
              currentAvatarUrl: _actor.avatarUrl,
              onSelect: (selectedUrl) => _changeAvatar(selectedUrl, dialogContext),
            );
          },
        );
      },
    );
  }

  Future<void> _changeAvatar(String newUrl, BuildContext dialogContext) async {
    try {
      final avatarsDir = await AppPaths.avatarsDir;

      if (_actor.avatarUrl != null && _actor.avatarUrl!.isNotEmpty) {
        final oldFile = File(_actor.avatarUrl!);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      final client = await createProxyClientFromPrefs();
      final response = await client.get(Uri.parse(newUrl)).timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode == 200 && response.bodyBytes.length > 100) {
        final safeName = _actor.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final filePath = path.join(avatarsDir, '$safeName.jpg');
        await File(filePath).writeAsBytes(response.bodyBytes);

        // Clear image cache so Image.file re-decodes the new file
        ActorAvatar.evictCache(filePath);

        final actorRepo = ref.read(actorRepositoryProvider);
        await actorRepo.updateActorAvatar(_actor.id!, filePath);

        ref.invalidate(allActorsProvider);
        ref.invalidate(favoriteActorsProvider);

        setState(() {
          _actor = _actor.copyWith(avatarUrl: filePath);
          _avatarKey = DateTime.now().microsecondsSinceEpoch;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('头像更换成功'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载头像失败 (${response.statusCode})'), backgroundColor: AppTheme.errorColor),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更换头像失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }

    if (Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }
  }
}

class _AvatarSelectionDialog extends StatefulWidget {
  final String actorName;
  final List<String> avatarUrls;
  final String? currentAvatarUrl;
  final Function(String) onSelect;

  const _AvatarSelectionDialog({
    required this.actorName,
    required this.avatarUrls,
    required this.currentAvatarUrl,
    required this.onSelect,
  });

  @override
  State<_AvatarSelectionDialog> createState() => _AvatarSelectionDialogState();
}

class _AvatarSelectionDialogState extends State<_AvatarSelectionDialog> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    if (widget.currentAvatarUrl != null && widget.avatarUrls.isNotEmpty) {
      for (int i = 0; i < widget.avatarUrls.length; i++) {
        if (widget.avatarUrls[i].contains(widget.actorName)) {
          _selectedIndex = i;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        borderRadius: GlassConstants.radiusXLarge,
        padding: const EdgeInsets.all(24),
        width: 600,
        height: 500,
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  '选择头像',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${widget.actorName} (${widget.avatarUrls.length} 个候选)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: widget.avatarUrls.length,
                itemBuilder: (context, index) {
                  final url = widget.avatarUrls[index];
                  final isSelected = _selectedIndex == index;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    onDoubleTap: () {
                      if (_selectedIndex == index) {
                        widget.onSelect(url);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(alpha:0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    color: AppTheme.primaryColor,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: AppTheme.cardColor,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: AppTheme.textSecondary,
                                      size: 32,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _selectedIndex != null
                      ? () => widget.onSelect(widget.avatarUrls[_selectedIndex!])
                      : null,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('确认更换'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
