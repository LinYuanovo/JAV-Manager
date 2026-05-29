import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/webdav_service.dart';
import '../../theme/app_theme.dart';
import 'ignored_codes_dialog.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _libraryPathController;
  late TextEditingController _watchedPathController;
  late TextEditingController _playerPathController;
  late TextEditingController _scanIntervalController;
  late TextEditingController _proxyUrlController;
  late TextEditingController _webdavUrlController;
  late TextEditingController _webdavUsernameController;
  late TextEditingController _webdavPasswordController;
  // 刮削相关
  late TextEditingController _scraperDirController;
  late TextEditingController _javdbCookieController;
  String _proxyMode = 'none';
  bool _isTestingProxy = false;
  bool _webdavPasswordVisible = false;
  bool _isBackingUp = false;
  bool _isLoadingBackups = false;
  List<WebDavFile>? _backupFiles;
  String? _proxyTestResult;
  String _selectedFont = '';
  double _fontSize = 14.0;
  bool _enableGridAnimation = true;
  bool _enableAutoMove = true;
  bool _pureModeEnabled = false;
  // 刮削设置状态
  List<String> _ignoreFolders = [];
  bool _translateTitle = true;
  bool _translatePlot = true;
  // 关于区块状态
  String? _latestVersion;
  bool _isCheckingUpdate = false;
  bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final prefs = ref.read(sharedPreferencesProvider);
    final libraryPath = prefs.getString('library_path') ?? '';
    final watchedPath = prefs.getString('watched_path') ?? '';
    final playerPath = prefs.getString('player_path') ?? '';
    final scanInterval = prefs.getInt('scan_interval') ?? 5;
    final proxyMode = prefs.getString('proxy_mode') ?? 'none';
    final proxyUrl = prefs.getString('proxy_url') ?? '';
    final font = prefs.getString('font_family') ?? '';
    final fontSize = prefs.getDouble('font_size') ?? 14.0;

    // 加载刮削配置
    final scraperDir = prefs.getString('scraper_scan_dir') ?? '';
    final javdbCookie = prefs.getString('scraper_javdb_cookie') ?? '';
    final ignoreFoldersStr = prefs.getString('scraper_ignore_folders') ?? '';
    _ignoreFolders = ignoreFoldersStr.isNotEmpty
        ? ignoreFoldersStr.split('|').where((s) => s.isNotEmpty).toList()
        : [];
    _translateTitle = prefs.getBool('scraper_translate_title') ?? true;
    _translatePlot = prefs.getBool('scraper_translate_plot') ?? true;

    _libraryPathController = TextEditingController(text: libraryPath);
    _watchedPathController = TextEditingController(text: watchedPath);
    _playerPathController = TextEditingController(text: playerPath);
    _scanIntervalController = TextEditingController(text: scanInterval.toString());
    _proxyMode = proxyMode;
    _proxyUrlController = TextEditingController(text: proxyUrl);
    _webdavUrlController = TextEditingController(text: prefs.getString('webdav_url') ?? '');
    _webdavUsernameController = TextEditingController(text: prefs.getString('webdav_username') ?? '');
    _webdavPasswordController = TextEditingController(text: prefs.getString('webdav_password') ?? '');
    // 初始化刮削控制器
    _scraperDirController = TextEditingController(text: scraperDir);
    _javdbCookieController = TextEditingController(text: javdbCookie);
    _selectedFont = font;
    _fontSize = fontSize;
    _enableGridAnimation = prefs.getBool('enable_grid_animation') ?? true;
    _enableAutoMove = prefs.getBool('enable_auto_move') ?? true;
    _pureModeEnabled = prefs.getBool('pure_mode_enabled') ?? false;
  }

  @override
  void dispose() {
    _libraryPathController.dispose();
    _watchedPathController.dispose();
    _playerPathController.dispose();
    _scanIntervalController.dispose();
    _proxyUrlController.dispose();
    _webdavUrlController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    _scraperDirController.dispose();
    _javdbCookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildActionsSection(),
          const SizedBox(height: 32),
          _buildAboutSection(),
          const SizedBox(height: 32),
          _buildProxySection(),
          const SizedBox(height: 24),
          _buildScraperSettingsSection(),
          const SizedBox(height: 24),
          _buildSection(
            title: '媒体库设置',
            icon: Icons.folder_outlined,
            children: [
              _buildPathSetting(
                label: '媒体库目录',
                hint: '选择包含 #整理完成 的文件夹',
                controller: _libraryPathController,
                onBrowse: () => _selectDirectory(_libraryPathController),
              ),
              const SizedBox(height: 20),
              _buildPathSetting(
                label: '已观看影片目录',
                hint: '默认: 媒体库根目录/Watched',
                controller: _watchedPathController,
                onBrowse: () => _selectDirectory(_watchedPathController),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: '播放设置',
            icon: Icons.play_circle_outline,
            children: [
              _buildPathSetting(
                label: '播放器路径（可选）',
                hint: '留空使用系统默认播放器',
                controller: _playerPathController,
                onBrowse: () => _selectFile(
                  _playerPathController,
                  extensions: ['exe'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: '自动整理设置',
            icon: Icons.auto_fix_high_outlined,
            children: [
              _buildIntervalSetting(),
              const SizedBox(height: 16),
              _buildAutoMoveSetting(),
            ],
          ),
          const SizedBox(height: 24),
          _buildFontSection(),
          const SizedBox(height: 24),
          _buildDisplaySection(),
          const SizedBox(height: 24),
          _buildWebdavSection(),
          const SizedBox(height: 24),
          _buildLocalBackupSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          Icons.settings,
          color: AppTheme.primaryColor,
          size: 28,
        ),
        const SizedBox(width: 12),
        ShaderMask(
          shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
          child: const Text(
            '设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPathSetting({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onBrowse,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(
                    color: AppTheme.textSecondary.withValues(alpha:0.2),
                  ),
                ),
                child: Text(
                  controller.text.isEmpty ? hint : controller.text,
                  style: TextStyle(
                    color: controller.text.isEmpty
                        ? AppTheme.textSecondary.withValues(alpha:0.5)
                        : AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onBrowse,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor.withValues(alpha:0.15),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                ),
              ),
              child: const Text('浏览'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIntervalSetting() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自动扫描间隔',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '每隔设定时间自动扫描媒体库并整理',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 100,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: AppTheme.textSecondary.withValues(alpha:0.2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scanIntervalController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const Text(
                '分钟',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutoMoveSetting() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动移动已观看影片', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('每次扫描后将已观看的影片自动移到"已观看影片目录"', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _enableAutoMove,
              onChanged: (value) => setState(() => _enableAutoMove = value),
              activeThumbColor: AppTheme.primaryColor,
            ),
          ],
        ),
        if (_enableAutoMove) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              border: Border.all(color: AppTheme.warningColor.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.warningColor, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '已观看的影片（观看次数 ≥ 1）将在每次扫描后自动移动到"已观看影片目录"',
                    style: TextStyle(color: AppTheme.warningColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFontSection() {
    return _buildSection(
      title: '字体设置',
      icon: Icons.font_download_outlined,
      children: [
        Row(
          children: [
            const Text(
              '字体',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(color: AppTheme.textSecondary.withValues(alpha:0.2)),
                ),
                child: DropdownButton<String>(
                  value: _selectedFont.isEmpty ? null : _selectedFont,
                  hint: const Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppTheme.surfaceColor,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: 'MapleMonoNL-NF-CN', child: Text('MapleMonoNL-NF-CN', style: TextStyle(fontSize: 14, fontFamily: 'MapleMonoNL-NF-CN'))),
                  ],
                  onChanged: (v) => setState(() => _selectedFont = v ?? ''),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              '字号',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_fontSize.toStringAsFixed(1)} px',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () {
                      if (_fontSize > 10.0) {
                        setState(() => _fontSize -= 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '减小字号',
                  ),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 10.0,
                      max: 24.0,
                      divisions: 28,
                      label: '${_fontSize.toStringAsFixed(1)} px',
                      onChanged: (value) {
                        setState(() => _fontSize = value);
                      },
                      activeColor: AppTheme.primaryColor,
                      inactiveColor: AppTheme.textSecondary.withValues(alpha:0.2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () {
                      if (_fontSize < 24.0) {
                        setState(() => _fontSize += 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '增大字号',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor.withValues(alpha:0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '预览 AaBbCc 中文 123',
                style: TextStyle(
                  fontSize: _fontSize,
                  fontFamily: _selectedFont.isNotEmpty ? _selectedFont : null,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '选择后需点击"保存设置"并重启应用生效',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.6), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDisplaySection() {
    return _buildSection(
      title: '显示设置',
      icon: Icons.visibility_outlined,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('网格加载动画', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('关闭后视频卡片将立即显示，滚动更流畅', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _enableGridAnimation,
              onChanged: (value) {
                setState(() => _enableGridAnimation = value);
              },
              activeThumbColor: AppTheme.primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('纯净模式', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('仅显示番号并隐藏海报内容', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _pureModeEnabled,
              onChanged: (value) {
                setState(() => _pureModeEnabled = value);
              },
              activeThumbColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    const currentVersion = '1.4.4';
    const githubRepoUrl = 'https://github.com/LinYuanovo/JAV-Manager';
    const releasesUrl = '$githubRepoUrl/releases';

    return _buildSection(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('当前版本', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('v$currentVersion', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(width: 32),
                  if (_latestVersion != null) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_hasUpdate ? '发现新版本' : '云端版本', style: TextStyle(color: _hasUpdate ? Colors.orange : AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('v$_latestVersion', style: TextStyle(color: _hasUpdate ? Colors.orange : AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ] else ...[
                    const Text('未检查', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 24),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  child: ElevatedButton.icon(
                    onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                    icon: _isCheckingUpdate
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 16),
                    label: Text(_isCheckingUpdate ? '检查中...' : '检查更新'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor.withValues(alpha:0.15),
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: TextStyle(fontSize: _fontSize * 0.93, fontFamily: _selectedFont.isEmpty ? null : _selectedFont),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 120,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(releasesUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('查看详情'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor.withValues(alpha:0.15),
                      foregroundColor: AppTheme.successColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: TextStyle(fontSize: _fontSize * 0.93, fontFamily: _selectedFont.isEmpty ? null : _selectedFont),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_hasUpdate && _latestVersion != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.new_releases, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '发现新版本 v$_latestVersion，点击"查看详情"获取更新',
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _latestVersion = null;
      _hasUpdate = false;
    });

    try {
      final uri = Uri.parse('https://api.github.com/repos/LinYuanovo/JAV-Manager/releases/latest');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestTag = data['tag_name'] as String? ?? '';
        final latestVersionClean = latestTag.startsWith('v') ? latestTag.substring(1) : latestTag;

        if (mounted) {
          setState(() {
            _latestVersion = latestVersionClean;
            _isCheckingUpdate = false;

            final currentParts = '1.4.3'.split('.').map((e) => int.tryParse(e) ?? 0).toList();
            final latestParts = latestVersionClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

            for (var i = 0; i < 3; i++) {
              final current = i < currentParts.length ? currentParts[i] : 0;
              final latest = i < latestParts.length ? latestParts[i] : 0;
              if (latest > current) {
                _hasUpdate = true;
                break;
              } else if (latest < current) {
                break;
              }
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isCheckingUpdate = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('检查更新失败，请稍后重试'), backgroundColor: AppTheme.errorColor),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Widget _buildScraperSettingsSection() {
    return _buildSection(
      title: '刮削设置',
      icon: Icons.cloud_download_outlined,
      children: [
        // 1. 扫描目录选择
        _buildPathSetting(
          label: '影片目录',
          hint: '选择要刮削的影片所在文件夹',
          controller: _scraperDirController,
          onBrowse: () => _selectDirectory(_scraperDirController),
        ),
        
        const SizedBox(height: 16),
        
        // 2. 忽略文件夹（多选+删除）
        _buildIgnoreFoldersSetting(),
        
        const SizedBox(height: 16),
        
        // 3. JavDB Cookie 输入
        _buildJavdbCookieSetting(),
        
        const SizedBox(height: 16),
        
        // 4. 翻译开关
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('翻译标题', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('将日文标题翻译为中文', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _translateTitle,
                    onChanged: (value) => setState(() => _translateTitle = value),
                    activeThumbColor: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('翻译剧情简介', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('将剧情简介翻译为中文', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _translatePlot,
                    onChanged: (value) => setState(() => _translatePlot = value),
                    activeThumbColor: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIgnoreFoldersSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '忽略文件夹',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._ignoreFolders.map((folder) {
              return Chip(
                label: Text(folder, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _ignoreFolders.remove(folder);
                  });
                },
                backgroundColor: Colors.white.withValues(alpha: 0.6),
                side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
              );
            }),
            ActionChip(
              label: const Text('+ 添加', style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
              onPressed: _addIgnoreFolder,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addIgnoreFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择要忽略的文件夹',
    );

    if (result != null) {
      final folderName = result.split(Platform.pathSeparator).last;
      if (!_ignoreFolders.contains(folderName)) {
        setState(() {
          _ignoreFolders.add(folderName);
        });
      }
    }
  }

  Widget _buildJavdbCookieSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JavDB Cookie（可选）',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '手动填入以启用 JavDB 刮削，留空则不使用 JavDB',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _javdbCookieController,
          obscureText: false,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: '_jdb_session=xxx; locale=zh',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildProxySection() {
    return _buildSection(
      title: '网络代理设置',
      icon: Icons.language,
      children: [
        Row(
          children: [
            GlassChip(
              label: '不使用代理',
              isSelected: _proxyMode == 'none',
              onTap: () => setState(() => _proxyMode = 'none'),
            ),
            const SizedBox(width: 8),
            GlassChip(
              label: '使用系统代理',
              isSelected: _proxyMode == 'system',
              onTap: () => setState(() => _proxyMode = 'system'),
            ),
            const SizedBox(width: 8),
            GlassChip(
              label: '自定义代理',
              isSelected: _proxyMode == 'custom',
              onTap: () => setState(() => _proxyMode = 'custom'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isTestingProxy ? null : _testProxy,
              icon: _isTestingProxy
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.network_check, size: 18),
              label: Text('测试连接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_proxyTestResult != null)
              Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text(
                  _proxyTestResult!,
                  style: TextStyle(
                    color: _proxyTestResult!.contains('成功') ? AppTheme.successColor : AppTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
        if (_proxyMode == 'custom') ...[
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('代理地址', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _proxyUrlController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '例如: 127.0.0.1:7890',
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha:0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionsSection() {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on, color: AppTheme.accentColor, size: 22),
              SizedBox(width: 12),
              Text(
                '快捷操作',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.save,
                  label: '保存设置',
                  color: AppTheme.primaryColor,
                  onPressed: _saveSettings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh,
                  label: '立即扫描',
                  color: AppTheme.successColor,
                  isLoading: ref.watch(isScanningProvider),
                  onPressed: _scanNow,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.block,
                  label: '黑名单管理',
                  color: Colors.orange,
                  onPressed: () {
                    showDialog(context: context, builder: (context) => const IgnoredCodesDialog());
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectDirectory(TextEditingController controller) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择文件夹',
      initialDirectory: controller.text.isNotEmpty ? controller.text : null,
    );
    if (result != null) {
      setState(() {
        controller.text = result;
      });
    }
  }

  Future<void> _selectFile(
    TextEditingController controller, {
    List<String>? extensions,
  }) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择文件',
      type: extensions != null ? FileType.custom : FileType.any,
      allowedExtensions: extensions,
      initialDirectory: controller.text.isNotEmpty
          ? Directory(controller.text).parent.path
          : null,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        controller.text = result.files.single.path!;
      });
    }
  }

  Future<void> _testProxy() async {
    // Save current proxy settings first
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);

    setState(() {
      _isTestingProxy = true;
      _proxyTestResult = null;
    });

    final ok = await testProxyConnection('https://ja.wikipedia.org/wiki/三上悠亜');

    if (mounted) {
      setState(() {
        _isTestingProxy = false;
        _proxyTestResult = ok ? '连接成功' : '连接失败，请检查代理设置';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);

    await prefs.setString('library_path', _libraryPathController.text);
    await prefs.setString('watched_path', _watchedPathController.text);
    await prefs.setString('player_path', _playerPathController.text);

    final interval = int.tryParse(_scanIntervalController.text) ?? 5;
    await prefs.setInt('scan_interval', interval);

    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);
    await prefs.setString('font_family', _selectedFont);
    await prefs.setDouble('font_size', _fontSize);
    await prefs.setBool('enable_grid_animation', _enableGridAnimation);
    await prefs.setBool('enable_auto_move', _enableAutoMove);
    await prefs.setBool('pure_mode_enabled', _pureModeEnabled);
    await prefs.setString('webdav_url', _webdavUrlController.text);
    await prefs.setString('webdav_username', _webdavUsernameController.text);
    await prefs.setString('webdav_password', _webdavPasswordController.text);

    // 保存刮削配置
    await prefs.setString('scraper_scan_dir', _scraperDirController.text);
    await prefs.setString('scraper_javdb_cookie', _javdbCookieController.text);
    await prefs.setString('scraper_ignore_folders', _ignoreFolders.join('|'));
    await prefs.setBool('scraper_translate_title', _translateTitle);
    await prefs.setBool('scraper_translate_plot', _translatePlot);

    final autoTaskService = ref.read(autoTaskServiceProvider);
    await autoTaskService.setScanInterval(interval);

    if (!mounted) return;
    ref.invalidate(enableGridAnimationProvider);
    ref.invalidate(pureModeProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  Future<void> _scanNow() async {
    // 防止重复扫描
    if (ref.read(isScanningProvider)) return;

    if (_libraryPathController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先配置媒体库目录'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    ref.read(isScanningProvider.notifier).state = true;
    ref.read(scanCancelProvider.notifier).state = false;
    ref.read(scanProcessedProvider.notifier).state = 0;
    ref.read(scanTotalProvider.notifier).state = 0;

    await _saveSettings();

    try {
      final scanner = ref.read(mediaScannerServiceProvider);
      await scanner.scanMediaLibrary(_libraryPathController.text);

      ref.invalidate(allVideosProvider);
      ref.invalidate(watchedVideosProvider);
      ref.invalidate(favoriteVideosProvider);
      ref.invalidate(allActorsProvider);
      ref.invalidate(allTagsProvider);
      ref.invalidate(allSeriesProvider);
      ref.invalidate(allStudiosProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('扫描完成'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } finally {
      ref.read(isScanningProvider.notifier).state = false;
    }
  }

  Widget _buildLocalBackupSection() {
    return _buildSection(
      title: '本地备份',
      icon: Icons.folder_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportLocalBackup,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导出备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _importLocalBackup,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWebdavSection() {
    return _buildSection(
      title: 'WebDAV 云备份',
      icon: Icons.cloud_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoadingBackups ? null : _showBackupList,
                icon: _isLoadingBackups
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_queue, size: 18),
                label: const Text('查看备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _backupToWebdav,
                icon: _isBackingUp
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.backup, size: 18),
                label: const Text('备份数据'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildWebdavTextField(
          controller: _webdavUrlController,
          label: '服务地址',
          hint: 'https://your-webdav-server.com/remote.php/dav/files/username/',
          icon: Icons.link,
        ),
        const SizedBox(height: 12),
        _buildWebdavTextField(
          controller: _webdavUsernameController,
          label: '用户名',
          hint: 'WebDAV 账号',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        _buildWebdavPasswordField(),
      ],
    );
  }

  Widget _buildWebdavTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildWebdavPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('密码', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _webdavPasswordController,
          obscureText: !_webdavPasswordVisible,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'WebDAV 密码',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            suffixIcon: IconButton(
              icon: Icon(
                _webdavPasswordVisible ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
              onPressed: () => setState(() => _webdavPasswordVisible = !_webdavPasswordVisible),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  void _showBackupList() async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写完整的 WebDAV 配置'), backgroundColor: AppTheme.warningColor),
        );
      }
      return;
    }

    setState(() => _isLoadingBackups = true);

    final service = ref.read(webdavServiceProvider);
    final files = await service.listBackups(
      serverUrl: url,
      username: username,
      password: password,
    );

    if (mounted) {
      setState(() {
        _isLoadingBackups = false;
        _backupFiles = files;
      });
      _showBackupDialog();
    }
  }

  void _showBackupDialog() {
    final files = _backupFiles ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusLarge)),
        title: Row(
          children: [
            const Icon(Icons.cloud_queue, color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 8),
            const Text('云端备份列表', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () {
                Navigator.of(ctx).pop();
                _showBackupList();
              },
              tooltip: '刷新',
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 780,
          child: files.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('暂无备份文件', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              : SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 16,
                    headingTextStyle: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    dataTextStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    columns: const [
                      DataColumn(label: Text('文件名')),
                      DataColumn(label: Text('大小')),
                      DataColumn(label: Text('备份日期')),
                      DataColumn(label: Text('操作')),
                    ],
                    rows: files.map((f) {
                      return DataRow(cells: [
                        DataCell(Text(f.name, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(f.sizeFormatted)),
                        DataCell(Text(f.modifiedDate != null
                            ? '${f.modifiedDate!.year}-${f.modifiedDate!.month.toString().padLeft(2, '0')}-${f.modifiedDate!.day.toString().padLeft(2, '0')} ${f.modifiedDate!.hour.toString().padLeft(2, '0')}:${f.modifiedDate!.minute.toString().padLeft(2, '0')}'
                            : '-')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniIconButton(
                                icon: Icons.download,
                                tooltip: '下载',
                                color: AppTheme.primaryColor,
                                onTap: () => _downloadBackupFile(f.name),
                              ),
                              const SizedBox(width: 4),
                              _MiniIconButton(
                                icon: Icons.file_download_outlined,
                                tooltip: '导入',
                                color: AppTheme.successColor,
                                onTap: () => _importBackupFile(f.name),
                              ),
                              const SizedBox(width: 4),
                              _MiniIconButton(
                                icon: Icons.delete_outline,
                                tooltip: '删除',
                                color: AppTheme.errorColor,
                                onTap: () => _deleteBackupWithConfirm(f.name),
                              ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _backupToWebdav() async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写完整的 WebDAV 配置'), backgroundColor: AppTheme.warningColor),
        );
      }
      return;
    }

    setState(() => _isBackingUp = true);

    try {
      // 检查是否正在扫描，避免备份不完整的数据库
      if (ref.read(isScanningProvider)) {
        if (mounted) {
          setState(() => _isBackingUp = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在扫描媒体库，请等待扫描完成后再备份'), backgroundColor: AppTheme.warningColor),
          );
        }
        return;
      }

      final dbPath = await DatabaseHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        if (mounted) {
          setState(() => _isBackingUp = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('数据库文件不存在'), backgroundColor: AppTheme.errorColor),
          );
        }
        return;
      }

      // 收集设置
      final prefs = ref.read(sharedPreferencesProvider);
      final settingsJson = jsonEncode(prefs.toMap());

      // 创建 zip 包
      final archive = Archive();
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
      final settingsBytes = utf8.encode(settingsJson);
      archive.addFile(ArchiveFile('settings.json', settingsBytes.length, settingsBytes));
      final zipBytes = ZipEncoder().encode(archive);

      // 写入临时 zip 文件
      final tempDir = Directory.systemTemp;
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final tempZipPath = '${tempDir.path}${Platform.pathSeparator}jav_manager_$timestamp.zip';
      await File(tempZipPath).writeAsBytes(zipBytes);

      final service = ref.read(webdavServiceProvider);
      final ok = await service.uploadBackup(
        serverUrl: url,
        username: username,
        password: password,
        localDbPath: tempZipPath,
      );

      // 清理临时文件
      final tempFile = File(tempZipPath);
      if (await tempFile.exists()) await tempFile.delete();

      if (mounted) {
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '备份成功' : '备份失败，请检查配置和服务器状态'),
            backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('WebDAV backup error: $e');
      if (mounted) {
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _downloadBackupFile(String fileName) async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
    if (result == null) return;

    final localPath = '$result${Platform.pathSeparator}$fileName';
    final service = ref.read(webdavServiceProvider);
    final ok = await service.downloadBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
      localPath: localPath,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '下载成功: $localPath' : '下载失败'),
          backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _importBackupFile(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认导入备份', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '导入备份将替换当前数据库和设置。导入后需要重启应用才能生效。\n\n确定要导入 "$fileName" 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定导入', style: TextStyle(color: AppTheme.warningColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final dbPath = await DatabaseHelper.getDatabasePath();
    final service = ref.read(webdavServiceProvider);
    final tempPath = await service.importBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
      localDbPath: dbPath,
    );

    bool ok = false;
    if (tempPath != null) {
      try {
        final tempFile = File(tempPath);
        if (!tempFile.existsSync()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('导入失败：临时文件不存在'), backgroundColor: AppTheme.errorColor),
            );
          }
          return;
        }

        // 关闭数据库连接
        await DatabaseHelper.close();

        if (fileName.endsWith('.zip')) {
          // 新格式：zip 包含数据库 + 设置
          final zipBytes = await tempFile.readAsBytes();
          final archive = ZipDecoder().decodeBytes(zipBytes);

          for (final file in archive) {
            if (file.name == 'database.db') {
              final dbFile = File(dbPath);
              if (dbFile.existsSync()) await dbFile.delete();
              await dbFile.writeAsBytes(file.content as List<int>);
            } else if (file.name == 'settings.json') {
              // 还原设置
              final settingsJson = String.fromCharCodes(file.content as List<int>);
              final settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
              final prefs = ref.read(sharedPreferencesProvider);
              for (final entry in settingsMap.entries) {
                final value = entry.value;
                if (value is String) {
                  await prefs.setString(entry.key, value);
                } else if (value is int) {
                  await prefs.setInt(entry.key, value);
                } else if (value is double) {
                  await prefs.setDouble(entry.key, value);
                } else if (value is bool) {
                  await prefs.setBool(entry.key, value);
                }
              }
            }
          }
        } else {
          // 旧格式：纯 db 文件
          final dbFile = File(dbPath);
          if (dbFile.existsSync()) await dbFile.delete();
          await tempFile.copy(dbPath);
        }

        // 清理临时文件
        if (tempFile.existsSync()) await tempFile.delete();

        ok = true;
      } catch (e) {
        debugPrint('Failed to import backup: $e');
        // 尝试清理临时文件
        try {
          final tempFile = File(tempPath);
          if (tempFile.existsSync()) await tempFile.delete();
        } catch (_) {}
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '导入成功！请重启应用使数据生效。' : '导入失败'),
          backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _exportLocalBackup() async {
    // 检查是否正在扫描，避免备份不完整的数据库
    if (ref.read(isScanningProvider)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在扫描媒体库，请等待扫描完成后再备份'), backgroundColor: AppTheme.warningColor),
        );
      }
      return;
    }

    final dbPath = await DatabaseHelper.getDatabasePath();
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据库文件不存在'), backgroundColor: AppTheme.errorColor),
        );
      }
      return;
    }

    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final result = await FilePicker.saveFile(
      dialogTitle: '导出备份',
      fileName: 'jav_manager_$timestamp.zip',
    );

    if (result == null) return;

    try {
      // 收集设置
      final prefs = ref.read(sharedPreferencesProvider);
      final settingsJson = jsonEncode(prefs.toMap());

      // 创建 zip 包
      final archive = Archive();
      // 添加数据库文件
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
      // 添加设置文件
      final settingsBytes = utf8.encode(settingsJson);
      archive.addFile(ArchiveFile('settings.json', settingsBytes.length, settingsBytes));

      final zipBytes = ZipEncoder().encode(archive);
      await File(result).writeAsBytes(zipBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功: $result'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      debugPrint('Export backup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _importLocalBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认导入备份', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('导入备份将替换当前数据库和设置。导入后需要重启应用才能生效。', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定导入', style: TextStyle(color: AppTheme.warningColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      allowMultiple: false,
      allowedExtensions: ['zip', 'db'],
    );

    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    try {
      final dbPath = await DatabaseHelper.getDatabasePath();

      if (sourcePath.endsWith('.zip')) {
        // 新格式：zip 包含数据库 + 设置
        final zipBytes = await File(sourcePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);

        // 关闭数据库连接
        await DatabaseHelper.close();

        // 还原数据库
        for (final file in archive) {
          if (file.name == 'database.db') {
            final dbFile = File(dbPath);
            if (dbFile.existsSync()) await dbFile.delete();
            await dbFile.writeAsBytes(file.content as List<int>);
          } else if (file.name == 'settings.json') {
            // 还原设置
            final settingsJson = String.fromCharCodes(file.content as List<int>);
            final settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
            final prefs = ref.read(sharedPreferencesProvider);
            for (final entry in settingsMap.entries) {
              final value = entry.value;
              if (value is String) {
                await prefs.setString(entry.key, value);
              } else if (value is int) {
                await prefs.setInt(entry.key, value);
              } else if (value is double) {
                await prefs.setDouble(entry.key, value);
              } else if (value is bool) {
                await prefs.setBool(entry.key, value);
              }
            }
          }
        }
      } else {
        // 旧格式：纯 db 文件
        await DatabaseHelper.close();
        final dbFile = File(dbPath);
        if (dbFile.existsSync()) await dbFile.delete();
        await File(sourcePath).copy(dbPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入成功！请重启应用使数据生效。'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      debugPrint('Import local backup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _deleteBackupWithConfirm(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认删除', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定要删除云端备份 "$fileName" 吗？此操作不可撤销。', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final service = ref.read(webdavServiceProvider);
    final ok = await service.deleteBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
    );

    if (mounted && ok) {
      // Close current backup dialog before refreshing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showBackupList();
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        onTap: isLoading ? null : onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: color.withValues(alpha:0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

