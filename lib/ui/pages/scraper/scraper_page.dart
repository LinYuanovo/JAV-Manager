import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/models/scraper_models.dart';
import '../../../core/services/scraper_service.dart';
import '../../theme/app_theme.dart';

class ScraperPage extends ConsumerStatefulWidget {
  const ScraperPage({super.key});

  @override
  ConsumerState<ScraperPage> createState() => _ScraperPageState();
}

class _ScraperPageState extends ConsumerState<ScraperPage> {
  int _threadCount = 4;
  late TextEditingController _threadCountController;
  bool _isStartingProcess = false;
  bool _isScanning = false;  // 防止重复点击扫描按钮
  
  @override
  void initState() {
    super.initState();
    _threadCountController = TextEditingController(text: _threadCount.toString());
    
    // 初始化刮削服务并监听进度事件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScraperService();
    });
  }
  
  Future<void> _initScraperService() async {
    final service = ref.read(scraperServiceProvider);
    
    // 监听进度更新
    service.progressStream.listen((progress) {
      if (mounted) {
        ref.read(scrapableMoviesProvider.notifier).state = List.from(service.movies);
        ref.read(scrapingTaskStateProvider.notifier).state = service.taskState;
        if (mounted) setState(() {});
      }
    });
    
    // 监听任务状态变化（包括进程状态变化）
    service.stateStream.listen((state) {
      if (mounted) {
        ref.read(scrapingTaskStateProvider.notifier).state = state;
        
        // 关键：同步更新进程运行状态 Provider
        final isRunning = service.isProcessRunning;
        ref.read(scraperProcessRunningProvider.notifier).state = isRunning;
        
        // 同步影片列表（扫描完成时 service.movies 已更新）
        ref.read(scrapableMoviesProvider.notifier).state = List.from(service.movies);
        
        print('[ScraperPage] 状态更新: taskState=$state, processRunning=$isRunning, movies=${service.movies.length}');
        
        if (mounted) setState(() {});
      }
    });
  }
  
  @override
  void dispose() {
    _threadCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movies = ref.watch(scrapableMoviesProvider);
    final taskState = ref.watch(scrapingTaskStateProvider);
    final stats = ref.watch(scrapeStatsProvider);
    final service = ref.read(scraperServiceProvider);  // read 不触发 rebuild
    final isProcessRunning = ref.watch(scraperProcessRunningProvider);  // watch 触发 rebuild
    
    return Row(
      children: [
        // 左侧控制面板
        _buildControlPanel(taskState, stats, movies, isProcessRunning, service),
        
        const SizedBox(width: GlassConstants.spacingMedium),
        
        // 右侧影片列表
        Expanded(child: _buildMovieList(movies, stats)),
      ],
    );
  }
  
  Widget _buildControlPanel(
    ScrapingTaskState taskState,
    ScrapeStats stats,
    List<ScrapableMovie> movies,
    bool isProcessRunning,
    ScraperService service,
  ) {
    return GlassContainer(
      width: 300,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.cloud_download_outlined, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  '刮削中心',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // 进程状态显示
          _buildProcessStatus(isProcessRunning),
          
          const SizedBox(height: 20),
          
          // 进程控制按钮（启动/停止）
          _buildProcessControlButtons(isProcessRunning, service),
          
          if (isProcessRunning) ...[
            const SizedBox(height: 20),
            
            Divider(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            
            // 线程数设置
            _buildThreadCountInput(),
            
            const SizedBox(height: 16),
            
            // 扫描按钮
            _buildActionButton(
              icon: Icons.folder_open,
              label: '扫描影片',
              color: AppTheme.primaryColor,
              isLoading: taskState == ScrapingTaskState.scanning || _isScanning,
              isEnabled: !service.isRunning && !_isScanning,
              onPressed: _scanMovies,
            ),
            
            const SizedBox(height: 12),
            
            // 开始按钮
            _buildActionButton(
              icon: Icons.play_arrow,
              label: '开始刮削',
              color: AppTheme.successColor,
              isEnabled: movies.isNotEmpty && !service.isRunning,
              onPressed: () => _startScraping(movies),
            ),
            
            const SizedBox(height: 12),
            
            // 停止按钮
            _buildActionButton(
              icon: Icons.stop,
              label: '停止刮削',
              color: AppTheme.warningColor,
              isEnabled: service.isRunning,
              onPressed: _stopScraping,
            ),
          ],
          
          const Spacer(),
          
          // 统计信息
          _buildStatsPanel(stats),
        ],
      ),
    );
  }
  
  Widget _buildProcessStatus(bool isRunning) {
    return SizedBox(
      width: 200,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
        color: isRunning 
            ? AppTheme.successColor.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(
          color: isRunning 
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isRunning ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 18,
            color: isRunning ? AppTheme.successColor : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            isRunning ? '服务运行中' : '服务未启动',
            style: TextStyle(
              color: isRunning ? AppTheme.successColor : Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      ),
    );
  }
  
  Widget _buildProcessControlButtons(bool isRunning, ScraperService service) {
    return SizedBox(
      width: 200,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 启动/停止进程按钮
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          child: InkWell(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            onTap: _isStartingProcess ? null : () => _toggleProcess(service),
            child: AnimatedContainer(
              duration: GlassConstants.animFast,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isRunning 
                    ? AppTheme.errorColor.withValues(alpha: 0.15)
                    : AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                border: Border.all(
                  color: isRunning 
                      ? AppTheme.errorColor.withValues(alpha: 0.3)
                      : AppTheme.primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isStartingProcess)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    )
                  else
                    Icon(
                      isRunning ? Icons.power_settings_new : Icons.play_circle_outline,
                      color: isRunning ? AppTheme.errorColor : AppTheme.primaryColor,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _isStartingProcess 
                        ? '启动中...' 
                        : (isRunning ? '停止服务' : '启动服务'),
                    style: TextStyle(
                      color: isRunning ? AppTheme.errorColor : AppTheme.primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // 提示文本
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            isRunning 
                ? '点击停止可关闭 Python 后台进程'
                : '点击启动 Python 刮削服务',
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
      ),
    );
  }
  
  Future<void> _toggleProcess(ScraperService service) async {
    if (_isStartingProcess) return;
    
    setState(() => _isStartingProcess = true);
    
    try {
      if (service.isProcessRunning) {
        // 停止进程
        await service.stopProcess(force: true);
        
        // 立即更新 UI 状态
        if (mounted) {
          ref.read(scraperProcessRunningProvider.notifier).state = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Python 服务已停止'), backgroundColor: AppTheme.errorColor),
          );
        }
      } else {
        // 启动进程
        final success = await service.startProcess();
        
        if (!mounted) return;
        
        // 立即更新 UI 状态
        ref.read(scraperProcessRunningProvider.notifier).state = success;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '服务启动成功' : '服务启动失败'),
            backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
      
      if (mounted) setState(() {});
    } catch (e) {
      print('[ScraperPage] 操作失败: $e');
      
      if (!mounted) return;
      
      // 确保状态同步
      ref.read(scraperProcessRunningProvider.notifier).state = service.isProcessRunning;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e'), backgroundColor: AppTheme.errorColor),
      );
      setState(() {});
    } finally {
      _isStartingProcess = false;
      if (mounted) setState(() {});
    }
  }
  
  Widget _buildThreadCountInput() {
    return SizedBox(
      width: 200,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('线程数', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove, size: 18, color: AppTheme.primaryColor),
                onPressed: () {
                  if (_threadCount > 1) {
                    setState(() => _threadCount--);
                    _threadCountController.text = _threadCount.toString();
                  }
                },
              ),
              Expanded(
                child: TextField(
                  controller: _threadCountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed >= 1 && parsed <= 16) {
                      _threadCount = parsed;
                    }
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, size: 18, color: AppTheme.primaryColor),
                onPressed: () {
                  if (_threadCount < 16) {
                    _threadCount++;
                    _threadCountController.text = _threadCount.toString();
                  }
                },
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool isLoading = false,
    bool isEnabled = true,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 200,
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        onTap: isEnabled ? onPressed : null,
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isEnabled ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: isEnabled ? color.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              else
                Icon(icon, color: isEnabled ? color : Colors.grey, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? color : Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
  
  Widget _buildStatsPanel(ScrapeStats stats) {
    return SizedBox(
      width: 200,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('统计信息', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _StatRow(label: '总计', value: '${stats.total}', color: AppTheme.textPrimary),
          const SizedBox(height: 8),
          _StatRow(label: '待处理', value: '${stats.pending}', color: Colors.orange),
          const SizedBox(height: 8),
          _StatRow(label: '成功', value: '${stats.success}', color: AppTheme.successColor),
          const SizedBox(height: 8),
          _StatRow(label: '失败', value: '${stats.failed}', color: AppTheme.errorColor),
        ],
      ),
      ),
    );
  }
  
  Widget _buildMovieList(List<ScrapableMovie> movies, ScrapeStats stats) {
    if (!ref.read(scraperServiceProvider).isProcessRunning) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.settings_remote_outlined,
          message: '刮削服务未启动',
          subMessage: '请先点击左侧"启动服务"按钮启动 Python 刮削服务',
        ),
      );
    }
    
    if (movies.isEmpty) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.cloud_off_outlined,
          message: '暂无待刮削影片',
          subMessage: '点击左侧"扫描影片"按钮开始扫描目录',
        ),
      );
    }
    
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt_outlined, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '待刮削影片 (${movies.length})',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '成功率: ${stats.successRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: AppTheme.successColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text('番号', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12))),
                Expanded(flex: 3, child: Text('进度', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12))),
                SizedBox(width: 130, child: Text('状态', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
                SizedBox(width: 50, child: Text('操作', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          Expanded(
            child: ListView.separated(
              itemCount: movies.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.borderColor.withValues(alpha: 0.3)),
              itemBuilder: (context, index) {
                return _MovieListItem(movie: movies[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _scanMovies() async {
    // 防止重复点击
    if (_isScanning) return;
    _isScanning = true;
    
    if (mounted) setState(() {});
    
    final config = ref.read(scraperConfigProvider);
    final service = ref.read(scraperServiceProvider);
    
    try {
      // 检查进程是否运行
      if (!service.isProcessRunning) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('请先启动刮削服务'), backgroundColor: AppTheme.warningColor),
          );
        }
        return;
      }
      
      // 一次性完成：初始化配置 + 扫描（initConfig 内部会检查幂等性）
      print('[ScraperPage] 开始扫描流程...');
      final scanSuccess = await service.scanMovies(config: config);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              scanSuccess 
                  ? '✅ 扫描完成！找到 ${service.movies.length} 个影片' 
                  : '❌ 扫描失败'
            ),
            backgroundColor: scanSuccess ? AppTheme.successColor : AppTheme.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('[ScraperPage] 扫描出错: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描出错: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      _isScanning = false;
      if (mounted) setState(() {});
    }
  }
  
  Future<void> _startScraping(List<ScrapableMovie> movies) async {
    final service = ref.read(scraperServiceProvider);
    
    try {
      await service.startScraping(threadCount: _threadCount);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('开始刮削 ${movies.length} 个影片 (线程数: $_threadCount)'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
  
  Future<void> _stopScraping() async {
    final service = ref.read(scraperServiceProvider);
    
    try {
      await service.stopScraping();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已发送停止信号，等待当前任务完成...'), backgroundColor: AppTheme.warningColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停止失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  
  const _StatRow({required this.label, required this.value, this.color = Colors.black});
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _MovieListItem extends StatelessWidget {
  final ScrapableMovie movie;
  
  const _MovieListItem({required this.movie});
  
  Color get _statusColor {
    switch (movie.status) {
      case ScrapeStatus.pending:
        return Colors.grey;
      case ScrapeStatus.scraping:
        return AppTheme.primaryColor;
      case ScrapeStatus.success:
        return AppTheme.successColor;
      case ScrapeStatus.failed:
        return AppTheme.errorColor;
      case ScrapeStatus.completed:
        return AppTheme.successColor;
    }
  }
  
  String get _statusText {
    switch (movie.status) {
      case ScrapeStatus.pending:
        return '待刮削';
      case ScrapeStatus.scraping:
        return movie.crawlerName != null ? '${movie.crawlerName} 爬取中' : '刮削中';
      case ScrapeStatus.success:
        return '✓ 成功';
      case ScrapeStatus.failed:
        return '✗ 失败';
      case ScrapeStatus.completed:
        return '已完成';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  movie.avid,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LinearProgressIndicator(
                    value: movie.progress,
                    backgroundColor: AppTheme.textSecondary.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(_statusColor),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              
              SizedBox(
                width: 130,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              
              SizedBox(
                width: 50,
                child: Center(
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
                    offset: const Offset(0, 30),
                    onSelected: (value) {
                      if (value == 'info') {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(movie.avid),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoRow('番号', movie.avid),
                                _InfoRow('文件', movie.filePath),
                                _InfoRow('类型', movie.movieType),
                                _InfoRow('状态', _statusText),
                                if (movie.crawlerName != null)
                                  _InfoRow('爬虫', movie.crawlerName!),
                                if (movie.errorMessage != null)
                                  _InfoRow('错误', movie.errorMessage!),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'info', child: Text('查看详情')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text('$label:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
