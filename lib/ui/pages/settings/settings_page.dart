import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/proxy_client.dart';
import '../../theme/app_theme.dart';

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
  String _proxyMode = 'none';
  bool _isScanning = false;
  bool _isTestingProxy = false;
  String? _proxyTestResult;
  String _selectedFont = '';
  double _fontSize = 14.0;

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

    _libraryPathController = TextEditingController(text: libraryPath);
    _watchedPathController = TextEditingController(text: watchedPath);
    _playerPathController = TextEditingController(text: playerPath);
    _scanIntervalController = TextEditingController(text: scanInterval.toString());
    _proxyMode = proxyMode;
    _proxyUrlController = TextEditingController(text: proxyUrl);
    _selectedFont = font;
    _fontSize = fontSize;
  }

  @override
  void dispose() {
    _libraryPathController.dispose();
    _watchedPathController.dispose();
    _playerPathController.dispose();
    _scanIntervalController.dispose();
    _proxyUrlController.dispose();
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
          _buildProxySection(),
          const SizedBox(height: 32),
          _buildActionsSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      children: [
        Icon(
          Icons.settings,
          color: AppTheme.textSecondary,
          size: 28,
        ),
        SizedBox(width: 12),
        Text(
          '设置',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
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
                  color: AppTheme.backgroundColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.textSecondary.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  controller.text.isEmpty ? hint : controller.text,
                  style: TextStyle(
                    color: controller.text.isEmpty
                        ? AppTheme.textSecondary.withValues(alpha: 0.5)
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
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
            color: AppTheme.backgroundColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.textSecondary.withValues(alpha: 0.2),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.warningColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: AppTheme.warningColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '已观看的影片（观看次数 ≥ 1）将在每次扫描后自动移动到"已观看影片目录"',
              style: TextStyle(
                color: AppTheme.warningColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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
                  color: AppTheme.backgroundColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
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
                      const Spacer(),
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
                      Slider(
                        value: _fontSize,
                        min: 10.0,
                        max: 24.0,
                        divisions: 28,
                        label: '${_fontSize.toStringAsFixed(1)} px',
                        onChanged: (value) {
                          setState(() => _fontSize = value);
                        },
                        activeColor: AppTheme.primaryColor,
                        inactiveColor: AppTheme.textSecondary.withValues(alpha: 0.2),
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
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '预览文字 AaBbCc 中文测试 123',
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontFamily: _selectedFont.isNotEmpty ? _selectedFont : null,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '选择后需点击"保存设置"并重启应用生效',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
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
            _buildProxyModeChip('none', '不使用代理'),
            const SizedBox(width: 8),
            _buildProxyModeChip('system', '使用系统代理'),
            const SizedBox(width: 8),
            _buildProxyModeChip('custom', '自定义代理'),
          ],
        ),
        if (_proxyMode == 'custom') ...[
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('代理地址', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _proxyUrlController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '例如: 127.0.0.1:7890',
                        hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppTheme.backgroundColor.withValues(alpha: 0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isTestingProxy ? null : _testProxy,
              icon: _isTestingProxy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.network_check, size: 18),
              label: const Text('测试连接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 12),
            if (_proxyTestResult != null)
              Text(
                _proxyTestResult!,
                style: TextStyle(
                  color: _proxyTestResult!.contains('成功') ? AppTheme.successColor : AppTheme.errorColor,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildProxyModeChip(String mode, String label) {
    final isSelected = _proxyMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _proxyMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  isLoading: _isScanning,
                  onPressed: _scanNow,
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

    final autoTaskService = ref.read(autoTaskServiceProvider);
    await autoTaskService.setScanInterval(interval);

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
    if (_libraryPathController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先配置媒体库目录'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() {
      _isScanning = true;
    });

    await _saveSettings();

    final scanner = ref.read(mediaScannerServiceProvider);
    await scanner.scanMediaLibrary(_libraryPathController.text);

    ref.invalidate(allVideosProvider);
    ref.invalidate(allActorsProvider);
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
    ref.invalidate(allStudiosProvider);

    setState(() {
      _isScanning = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('扫描完成'),
          backgroundColor: AppTheme.successColor,
        ),
      );
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isLoading ? null : onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
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

