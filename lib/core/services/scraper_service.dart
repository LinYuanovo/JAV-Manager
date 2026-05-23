import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/scraper_models.dart';
import 'app_logger.dart';

/// 刮削服务 - 管理与 Python 子进程的通信
class ScraperService {
  final _log = AppLogger.instance;
  Process? _process;
  final _progressController = StreamController<ScrapeProgress>.broadcast();
  final _stateController = StreamController<ScrapingTaskState>.broadcast();
  
  List<ScrapableMovie> _movies = [];
  ScrapingTaskState _taskState = ScrapingTaskState.idle;
  
  bool get isProcessRunning => _process != null;
  Stream<ScrapeProgress> get progressStream => _progressController.stream;
  Stream<ScrapingTaskState> get stateStream => _stateController.stream;
  ScrapingTaskState get taskState => _taskState;
  List<ScrapableMovie> get movies => List.unmodifiable(_movies);
  ScrapeStats get stats => ScrapeStats.fromList(_movies);
  bool get isRunning => 
      _taskState == ScrapingTaskState.running || 
      _taskState == ScrapingTaskState.scanning;

  final Map<String, Completer<Map<String, dynamic>?>> _commandCompleters = {};
  int _commandIdCounter = 0;
  bool _configInitialized = false;

  /// 启动 Python 进程（简化版 - 直接启动，不做复杂检查）
  Future<bool> startProcess() async {
    // 如果进程已存在且可能还活着，先尝试 ping
    if (_process != null) {
      try {
        final pingResult = await sendPing();
        if (pingResult) {
          _log.info('ScraperService', '进程已运行且正常响应');
          return true;
        }
      } catch (e) {
        _log.warning('ScraperService', '现有进程无响应，将重启: $e');
      }
      
      // 旧进程无响应，强制清理
      await stopProcess(force: true);
    }
    
    try {
      // 获取当前 exe 所在目录（Release 模式下为安装目录）
      final exeDir = path.dirname(Platform.resolvedExecutable);
      _log.info('ScraperService', 'exe目录: $exeDir');
      _log.info('ScraperService', '工作目录: ${Directory.current.path}');
      
      // 选择执行方式（按优先级）
      final exePaths = [
        path.join(exeDir, 'javsp_scraper.exe'),   // PyInstaller 打包版本（与主程序同目录）
        path.join(exeDir, 'scraper.exe'),          // 兼容旧名称
        'javsp_scraper.exe',                        // 工作目录下的打包版本
        'scraper.exe',                              // 工作目录下的兼容旧名称
      ];
      
      String? executable;
      List<String> args = [];
      bool foundExe = false;
      
      for (final exePath in exePaths) {
        _log.info('ScraperService', '检查刮削器: $exePath');
        if (File(exePath).existsSync()) {
          executable = exePath;
          foundExe = true;
          _log.info('ScraperService', '找到刮削器: $exePath');
          break;
        }
      }
      
      if (!foundExe) {
        // 回退到 Python 脚本模式
        final scriptCandidates = [
          path.join(exeDir, 'python_scraper', '__main__.py'),
          'python_scraper/__main__.py',
        ];
        String? scriptPath;
        for (final candidate in scriptCandidates) {
          if (File(candidate).existsSync()) {
            scriptPath = candidate;
            break;
          }
        }
        
        if (scriptPath == null) {
          final errMsg = '刮削器文件不存在！（已检查: javsp_scraper.exe, python_scraper/__main__.py）';
          _log.error('ScraperService', errMsg);
          throw Exception(errMsg);
        }
        executable = 'python';
        args = [scriptPath];
        _log.info('ScraperService', '启动 Python 脚本: $scriptPath');
      } else {
        _log.info('ScraperService', '启动独立 exe: $executable');
      }
      
      // 确保 executable 不为空（编译器需要）
      if (executable == null) {
        throw Exception('无法确定刮削器执行路径');
      }
      
      // 启动新进程
      _process = await Process.start(
        executable!,
        args,
        workingDirectory: exeDir,
        mode: ProcessStartMode.normal,
        environment: {
          ...Platform.environment,
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONUTF8': '1',
        },
      );
      
      // 通知 UI: 进程已创建（但可能还没就绪）
      _notifyProcessStateChanged(true);
      
      // 清空旧影片列表（新进程需要重新扫描）
      _movies.clear();
      _configInitialized = false;
      
      // 监听 stdout
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleStdout,
            onError: (e) => _log.error('ScraperService', 'stdout 错误', e),
            onDone: () {
              _log.info('ScraperService', 'stdout 关闭');
              _onProcessExit();
            },
          );
      
      // 监听 stderr - 写入日志文件
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              _log.info('Python', line);
            },
            onError: (e) => _log.error('ScraperService', 'stderr 错误', e),
          );
      
      // 进程退出处理
      _process!.exitCode.then((code) {
        _log.info('ScraperService', 'Python 进程退出，退出码: $code');
        _onProcessExit();
      });
      
      // 等待进程就绪
      await Future.delayed(Duration(milliseconds: 1000));
      
      // 发送 ping 测试
      final pingSuccess = await sendPing();
      if (!pingSuccess) {
        _log.error('ScraperService', 'Python 进程无法响应 ping');
        throw Exception('Python 进程无法响应 ping');
      }
      
      _log.info('ScraperService', '进程启动成功 (PID: ${_process!.pid})');
      return true;
      
    } catch (e, stackTrace) {
      _log.error('ScraperService', '启动失败', e, stackTrace);
      _process = null;
      _notifyProcessStateChanged(false);  // 通知失败
      return false;
    }
  }

  /// 通知进程状态变化（通过 stateStream）
  void _notifyProcessStateChanged(bool isRunning) {
    // 通过发送特殊的 taskState 来通知 UI 刷新
    // UI 层会监听这个 stream 并调用 setState
    if (!_stateController.isClosed) {
      _stateController.add(ScrapingTaskState.idle);  // 触发 rebuild
    }
  }

  /// 进程退出清理
  void _onProcessExit() {
    _process = null;
    _configInitialized = false;
    _movies.clear();  // 清空影片列表
    
    // 清理所有等待中的命令
    for (var completer in _commandCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _commandCompleters.clear();
    
    _updateTaskState(ScrapingTaskState.idle);
    _log.info('ScraperService', '进程已退出并清理');
  }

  /// 停止进程
  Future<void> stopProcess({bool force = false}) async {
    if (_process == null) return;
    
    _log.info('ScraperService', '正在停止进程...');
    
    try {
      if (!force && !_isStdinClosed()) {
        _sendRawCommand({'type': 'exit'});
        await Future.delayed(Duration(milliseconds: 1000));
      }
    } catch (e) {}
    
    // 强制终止
    try { _process?.kill(ProcessSignal.sigterm); await Future.delayed(Duration(milliseconds: 500)); } catch (e) {}
    try { _process?.kill(ProcessSignal.sigkill); } catch (e) {}
    
    _process = null;
    _configInitialized = false;
    _updateTaskState(ScrapingTaskState.idle);
    _log.info('ScraperService', '进程已停止');
  }

  void _handleStdout(String line) {
    if (line.trim().isEmpty) return;
    
    try {
      final data = jsonDecode(line);
      final type = data['type'] as String?;
      final cmdId = data['id'] as String?;
      
      switch (type) {
        case 'progress':
          final progress = ScrapeProgress.fromJson(data['data']);
          _log.info('ScraperService', '进度: id=${progress.movieId} status=${progress.status} avid=${progress.avid}');
          _handleProgress(progress);
          break;
          
        case 'result':
          _handleResult(data['data'], cmdId);
          break;
          
        case 'error':
          _log.warning('ScraperService', 'Python错误: ${data['data']?['message']}');
          if (cmdId != null && _commandCompleters.containsKey(cmdId)) {
            final c = _commandCompleters[cmdId];
            if (!c!.isCompleted) c.complete({'success': false, 'message': data['data']?['message']});
          }
          break;
          
        default:
          _log.warning('ScraperService', '未知消息类型: $type');
      }
    } catch (e, stackTrace) {
      _log.warning('ScraperService', 'JSON解析失败: $e\n  原始数据: ${line.length > 200 ? line.substring(0, 200) : line}');
    }
  }

  void _handleProgress(ScrapeProgress progress) {
    if (progress.status == ScrapeStatus.completed) {
      _updateTaskState(ScrapingTaskState.idle);
      if (!_progressController.isClosed) _progressController.add(progress);
      return;
    }

    final index = _movies.indexWhere((m) => m.id == progress.movieId);
    if (index >= 0) {
      _movies[index] = _movies[index].copyWith(
        status: progress.status,
        progress: progress.progress,
        crawlerName: progress.crawlerName,
        info: progress.info,
        errorMessage: progress.error,
      );
    } else {
      _log.warning('ScraperService', '进度事件未匹配到影片: movieId=${progress.movieId}, status=${progress.status}');
    }
    if (!_progressController.isClosed) _progressController.add(progress);
  }

  void _handleResult(Map<String, dynamic> resultData, String? cmdId) {
    final success = resultData['success'] as bool? ?? false;
    _log.info('ScraperService', '结果: success=$success, msg=${resultData['message']}');
    
    if (resultData['data']?['count'] != null) {
      _movies = (resultData['data']['movies'] as List<dynamic>?)
              ?.map((e) => ScrapableMovie.fromJson(e))
              .toList() ?? [];
      _log.info('ScraperService', '影片列表已更新: ${_movies.length} 个');
    }
    
    if (cmdId != null && _commandCompleters.containsKey(cmdId)) {
      final c = _commandCompleters[cmdId];
      if (!c!.isCompleted) c.complete(resultData);
    }
  }

  void _updateTaskState(ScrapingTaskState newState) {
    if (_taskState != newState) {
      _taskState = newState;
      if (!_stateController.isClosed) _stateController.add(newState);
    }
  }

  /// 发送命令并等待结果（带超时）
  Future<Map<String, dynamic>?> _sendCommandAndWait(Map<String, dynamic> command) async {
    if (_process == null || _isStdinClosed()) throw Exception('进程未运行');
    
    final commandId = (++_commandIdCounter).toString();
    command['id'] = commandId;
    
    final completer = Completer<Map<String, dynamic>?>();
    _commandCompleters[commandId] = completer;
    
    _sendRawCommand(command);
    
    try {
      return await completer.future.timeout(
        Duration(seconds: 60),
        onTimeout: () {
          _log.warning('ScraperService', '超时: ${command['type']} ($commandId)');
          return null;
        },
      );
    } finally {
      _commandCompleters.remove(commandId);
    }
  }

  /// 发送命令（不等待）
  Future<void> _sendCommand(Map<String, dynamic> command) async {
    if (_process == null || _isStdinClosed()) throw Exception('进程未运行');
    command['id'] = (++_commandIdCounter).toString();
    _sendRawCommand(command);
  }

  void _sendRawCommand(Map<String, dynamic> command) {
    final jsonStr = jsonEncode(command);
    _process!.stdin.write('$jsonStr\n');
    _process!.stdin.flush();
    _log.info('ScraperService', '发送: ${command['type']} (id=${command['id']})');
  }

  bool _isStdinClosed() {
    try {
      return _process?.stdin.done == true;
    } catch (e) {
      return true;
    }
  }

  /// 初始化配置（幂等）
  Future<bool> initConfig(ScraperConfig config, {bool force = false}) async {
    if (_configInitialized && !force) {
      _log.info('ScraperService', '配置已初始化，跳过');
      return true;
    }
    
    // 确保进程运行（如果已运行则不重启）
    if (_process == null) {
      if (!await startProcess()) return false;
    }
    
    if (_process == null) return false;
    
    _log.info('ScraperService', '初始化配置...');
    final pyConfig = config.toPythonConfig();
    _log.info('ScraperService', '网络配置: use_proxy=${pyConfig['network']['use_proxy']}, proxy=${pyConfig['network']['proxy']}');
    final result = await _sendCommandAndWait({
      'type': 'init',
      'config': pyConfig,
    });
    
    if (result == null || result!['success'] != true) {
      _configInitialized = false;
      _log.error('ScraperService', '配置初始化失败: ${result?['message'] ?? '无响应'}');
      return false;
    }
    
    _configInitialized = true;
    _log.info('ScraperService', '配置初始化成功');
    return true;
  }

  /// 扫描影片
  Future<bool> scanMovies({ScraperConfig? config}) async {
    if (config != null) {
      if (!await initConfig(config)) return false;
    } else if (!_configInitialized) {
      throw Exception('请先初始化配置');
    }
    
    if (_process == null) throw Exception('进程未启动');
    
    _updateTaskState(ScrapingTaskState.scanning);
    
    _log.info('ScraperService', '开始扫描...');
    final result = await _sendCommandAndWait({'type': 'scan'});
    
    if (result == null || result!['success'] != true) {
      _updateTaskState(ScrapingTaskState.idle);
      _log.error('ScraperService', '扫描失败: ${result?['message'] ?? '无响应'}');
      return false;
    }
    
    _log.info('ScraperService', '扫描完成: ${_movies.length} 个影片');
    _updateTaskState(ScrapingTaskState.idle);
    return true;
  }

  /// 开始刮削
  Future<void> startScraping({int threadCount = 4}) async {
    if (isRunning) throw Exception('已有任务在运行');
    if (_process == null) throw Exception('进程未启动');
    
    _updateTaskState(ScrapingTaskState.running);
    
    await _sendCommand({
      'type': 'start_scrape',
      'thread_count': threadCount,
    });
    
    _log.info('ScraperService', '开始刮削 (线程数: $threadCount)');
  }

  /// 停止刮削
  Future<void> stopScraping() async {
    if (!isRunning || _process == null) return;
    
    _updateTaskState(ScrapingTaskState.stopping);
    await _sendCommand({'type': 'stop_scrape'});
    _log.info('ScraperService', '已发送停止信号');
  }

  /// 心跳检测
  Future<bool> sendPing() async {
    if (_process == null) return false;
    try {
      final result = await _sendCommandAndWait({'type': 'ping'});
      return result != null && result!['success'] == true;
    } catch (e) {
      return false;
    }
  }

  void clearMovies() => _movies = [];

  Future<void> dispose() async {
    await stopProcess(force: true);
    await _progressController.close();
    await _stateController.close();
  }
}
