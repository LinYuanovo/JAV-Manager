import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../actors/actor_detail_page.dart';
import '../categories/category_videos_page.dart';

class VideoDetailDialog extends ConsumerStatefulWidget {
  final Video video;

  const VideoDetailDialog({super.key, required this.video});

  @override
  ConsumerState<VideoDetailDialog> createState() => _VideoDetailDialogState();
}

class _VideoDetailDialogState extends ConsumerState<VideoDetailDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(40),
            child: Container(
              width: screenSize.width * 0.85,
              height: screenSize.height * 0.85,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Row(
                  children: [
                    _buildLeftPanel(screenSize),
                    _buildRightPanel(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(Size screenSize) {
    final leftWidth = screenSize.width * 0.85 * 0.7;
    return SizedBox(
      width: leftWidth,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.video.fanartPath != null)
            Image.file(
              File(widget.video.fanartPath!),
              fit: BoxFit.cover,
              cacheWidth: 1200,
              gaplessPlayback: true,
            )
          else if (widget.video.posterPath != null)
            Image.file(
              File(widget.video.posterPath!),
              fit: BoxFit.cover,
              cacheWidth: 600,
              gaplessPlayback: true,
            )
          else
            Container(color: AppTheme.cardColor),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.4),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.video.posterPath != null)
                  Container(
                    width: 140,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(widget.video.posterPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 280,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Expanded(
      child: Container(
        color: AppTheme.surfaceColor,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppTheme.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.video.title ?? '未知标题',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: null,
                overflow: TextOverflow.visible,
              ),
              if (widget.video.plot != null && widget.video.plot!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.video.plot!,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.video.actors.isNotEmpty) ...[
                        _buildSectionTitle('演员'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.video.actors.map((actor) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ActorDetailPage(actor: actor)),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  actor.name,
                                  style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _buildTagsSection(),
                      const SizedBox(height: 20),
                      _buildInfoSection(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTagsSection() {
    final tags = widget.video.categories.where((c) => c.type == Category.typeTag).toList();
    final series = widget.video.categories.where((c) => c.type == Category.typeSeries).toList();
    final studios = widget.video.categories.where((c) => c.type == Category.typeStudio).toList();

    if (tags.isEmpty && series.isEmpty && studios.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty) ...[
          _buildSectionTitle('标签'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: tags.map(_buildTagChip).toList()),
        ],
        if (series.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionTitle('系列'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: series.map(_buildTagChip).toList()),
        ],
        if (studios.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionTitle('片商'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: studios.map(_buildTagChip).toList()),
        ],
      ],
    );
  }

  Widget _buildTagChip(Category category) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CategoryVideosPage(category: category)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          category.name,
          style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(icon: Icons.visibility, label: '观看次数', value: '${widget.video.watchCount}'),
          if (widget.video.lastWatchedTime != null)
            _buildInfoRow(icon: Icons.access_time, label: '上次观看', value: _formatDateTime(widget.video.lastWatchedTime!)),
          _buildInfoRow(icon: Icons.folder, label: '路径', value: widget.video.folderPath, isPath: true),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value, bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              maxLines: isPath ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _playVideo,
            icon: const Icon(Icons.play_arrow, size: 22),
            label: const Text('播放', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: _toggleFavorite,
          icon: Icon(
            widget.video.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: widget.video.isFavorite ? AppTheme.accentColor : AppTheme.textSecondary,
          ),
          iconSize: 28,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.backgroundColor,
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(width: 8),
          IconButton(
            onPressed: _openFolder,
            icon: const Icon(Icons.folder_open),
            color: AppTheme.textSecondary,
            tooltip: '打开文件夹',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.backgroundColor,
              padding: const EdgeInsets.all(12),
            ),
          ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _playVideo() async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.incrementWatchCount(widget.video.id!);

    final prefs = ref.read(sharedPreferencesProvider);
    final playerPath = prefs.getString('player_path');

    try {
      if (playerPath != null && playerPath.isNotEmpty) {
        await Process.run('cmd', ['/c', 'start', '""', playerPath, widget.video.filePath], runInShell: true);
      } else {
        await Process.run('cmd', ['/c', 'start', '""', widget.video.filePath], runInShell: true);
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
  }

  Future<void> _toggleFavorite() async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.toggleFavorite(widget.video.id!, !widget.video.isFavorite);
    ref.invalidate(allVideosProvider);
    ref.invalidate(favoriteVideosProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openFolder() async {
    try {
      final folderPath = widget.video.folderPath;
      await Process.start('explorer', [folderPath], runInShell: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件夹失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}
