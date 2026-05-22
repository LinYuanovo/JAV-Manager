import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';

class IgnoredCodesDialog extends ConsumerStatefulWidget {
  const IgnoredCodesDialog({super.key});

  @override
  ConsumerState<IgnoredCodesDialog> createState() => _IgnoredCodesDialogState();
}

class _IgnoredCodesDialogState extends ConsumerState<IgnoredCodesDialog> {
  List<Map<String, dynamic>> _ignoredCodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIgnoredCodes();
  }

  Future<void> _loadIgnoredCodes() async {
    setState(() => _isLoading = true);
    try {
      final repository = ref.read(videoRepositoryProvider);
      final codes = await repository.getAllIgnoredCodes();
      if (mounted) {
        setState(() {
          _ignoredCodes = codes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFromBlacklist(int id, String code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text('移出黑名单'),
        content: Text('确定要将「$code」从黑名单移出吗？\n\n移出后，下次扫描媒体库时会重新导入该番号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移出', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final repository = ref.read(videoRepositoryProvider);
      await repository.removeFromIgnoredCodes(id);
      await _loadIgnoredCodes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 $code 移出黑名单'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.backgroundColor,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 600,
        height: 500,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.1))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '黑名单管理',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '共 ${_ignoredCodes.length} 项',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: '刷新',
                    onPressed: _loadIgnoredCodes,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _ignoredCodes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 48, color: AppTheme.textSecondary.withValues(alpha:0.3)),
                              const SizedBox(height: 16),
                              Text('暂无黑名单记录', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text('右键视频可选择"移除媒体库"加入黑名单', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _ignoredCodes.length,
                          itemBuilder: (context, index) {
                            final item = _ignoredCodes[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.5),
                                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                                border: Border.all(color: AppTheme.textSecondary.withValues(alpha:0.1)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha:0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item['code'] as String? ?? '',
                                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title'] as String? ?? '未知标题',
                                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item['folder_path'] as String? ?? '',
                                          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.6), fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.restore_from_trash, size: 20, color: Colors.orange),
                                    tooltip: '移出黑名单',
                                    onPressed: () => _removeFromBlacklist(item['id'] as int, item['code'] as String? ?? ''),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.1))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
