import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/utils/app_settings.dart';
import '../theme/app_theme.dart';

/// 窗口管理控制器，封装所有窗口生命周期相关逻辑
class WindowController extends ChangeNotifier with WindowListener {
  final AppSettings _prefs;
  bool _isMaximized = false;
  Size? _lastNormalSize;
  Offset? _lastNormalPosition;

  WindowController(this._prefs);

  bool get isMaximized => _isMaximized;

  /// 初始化窗口：恢复上次保存的位置、大小和最大化状态
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    final width = _prefs.getDouble('window_width') ?? LayoutConstants.defaultWindowWidth;
    final height = _prefs.getDouble('window_height') ?? LayoutConstants.defaultWindowHeight;
    final x = _prefs.getDouble('window_x');
    final y = _prefs.getDouble('window_y');
    _isMaximized = _prefs.getBool('window_maximized') ?? false;

    if (_isMaximized) {
      await windowManager.setSize(Size(width, height));
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      await windowManager.maximize();
    } else {
      await windowManager.setSize(Size(width, height));
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
    }
  }

  /// 关闭窗口并保存当前状态
  Future<void> close() async {
    final isMax = await windowManager.isMaximized();
    Size size;
    Offset position;

    if (isMax && _lastNormalSize != null) {
      size = _lastNormalSize!;
      position = _lastNormalPosition ?? await windowManager.getPosition();
    } else {
      size = await windowManager.getSize();
      position = await windowManager.getPosition();
    }

    await _prefs.setBool('window_maximized', isMax);
    await _prefs.setDouble('window_width', size.width);
    await _prefs.setDouble('window_height', size.height);
    await _prefs.setDouble('window_x', position.dx);
    await _prefs.setDouble('window_y', position.dy);

    await windowManager.destroy();
  }

  /// 切换最大化/还原
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 最小化窗口
  Future<void> minimize() async {
    await windowManager.minimize();
  }

  /// 开始拖拽窗口
  Future<void> startDragging() async {
    await windowManager.startDragging();
  }

  // WindowListener 回调
  @override
  void onWindowClose() async {
    await close();
  }

  @override
  void onWindowResize() async {
    final isMax = await windowManager.isMaximized();
    if (!isMax) {
      _lastNormalSize = await windowManager.getSize();
      _lastNormalPosition = await windowManager.getPosition();
    }
  }

  @override
  void onWindowMaximize() {
    _isMaximized = true;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }
}
