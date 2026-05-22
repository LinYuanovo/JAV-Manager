import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;
import '../utils/app_settings.dart';
import '../repositories/video_repository.dart';
import 'media_scanner_service.dart';

class AutoTaskService {
  final VideoRepository _videoRepository;
  final MediaScannerService _mediaScannerService;
  final AppSettings _prefs;

  Timer? _scanTimer;
  Timer? _moveTimer;
  bool _isRunning = false;
  bool _isScanning = false;
  bool _isMoving = false;
  final StreamController<int> _onAutoMoveCompleteController = StreamController<int>.broadcast();

  Stream<int> get onAutoMoveComplete => _onAutoMoveCompleteController.stream;

  static const String _keyLibraryPath = 'library_path';
  static const String _keyWatchedPath = 'watched_path';
  static const String _keyPlayerPath = 'player_path';
  static const String _keyScanInterval = 'scan_interval';

  AutoTaskService({
    required AppSettings prefs,
    VideoRepository? videoRepository,
    MediaScannerService? mediaScannerService,
  })  : _prefs = prefs,
        _videoRepository = videoRepository ?? VideoRepository(),
        _mediaScannerService = mediaScannerService ?? MediaScannerService();

  String? get libraryPath => _prefs.getString(_keyLibraryPath);
  String? get watchedPath => _prefs.getString(_keyWatchedPath);
  String? get playerPath => _prefs.getString(_keyPlayerPath);
  int get scanIntervalMinutes => _prefs.getInt(_keyScanInterval) ?? 5;

  bool get isRunning => _isRunning;

  Future<void> setLibraryPath(String path) async {
    await _prefs.setString(_keyLibraryPath, path);
  }

  Future<void> setWatchedPath(String path) async {
    await _prefs.setString(_keyWatchedPath, path);
  }

  Future<void> setPlayerPath(String path) async {
    await _prefs.setString(_keyPlayerPath, path);
  }

  Future<void> setScanInterval(int minutes) async {
    await _prefs.setInt(_keyScanInterval, minutes);
    if (_isRunning) {
      stop();
      start();
    }
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _scanTimer = Timer.periodic(
      Duration(minutes: scanIntervalMinutes),
      (_) async {
        if (_isScanning) return;
        _isScanning = true;
        try {
          await _performScan();
        } finally {
          _isScanning = false;
        }
      },
    );

    _moveTimer = Timer.periodic(
      Duration(minutes: scanIntervalMinutes),
      (_) async {
        if (_isMoving) return;
        _isMoving = true;
        try {
          await _performAutoMove();
        } finally {
          _isMoving = false;
        }
      },
    );
  }

  void stop() {
    _scanTimer?.cancel();
    _moveTimer?.cancel();
    _scanTimer = null;
    _moveTimer = null;
    _isRunning = false;
  }

  Future<void> _performScan() async {
    final path = libraryPath;
    if (path == null || path.isEmpty) return;

    try {
      await _mediaScannerService.scanMediaLibrary(path);
    } catch (e) {
      debugPrint('[AutoTask] Scan error: $e');
    }
  }

  Future<void> _performAutoMove() async {
    final libPath = libraryPath;
    final watchedFolder = watchedPath;

    if (libPath == null || libPath == '' || watchedFolder == null || watchedFolder.isEmpty) {
      if (kDebugMode) debugPrint('[AutoMove] Skipping: libraryPath or watchedPath not configured');
      return;
    }

    try {
      final watchedVideos = await _videoRepository.getVideosWithWatchCountGreaterThanZero();

      if (kDebugMode) {
        debugPrint('[AutoMove] Found ${watchedVideos.length} videos with watch count > 0');
      }

      int movedCount = 0;
      final movedVideoIds = <int>[];
      for (final video in watchedVideos) {
        try {
          if (kDebugMode) {
            debugPrint('[AutoMove] Checking video: ${video.title}');
            debugPrint('[AutoMove]   folderPath: ${video.folderPath}');
            debugPrint('[AutoMove]   contains #整理完成: ${video.folderPath.contains('#整理完成')}');
          }

          if (video.folderPath.contains('#整理完成')) {
            if (kDebugMode) debugPrint('[AutoMove] Moving video to watched folder: ${video.title}');
            await _mediaScannerService.moveVideoToWatched(video, watchedFolder);
            movedCount++;
            if (video.id != null) movedVideoIds.add(video.id!);
            if (kDebugMode) debugPrint('[AutoMove] Successfully moved: ${video.title}');
          } else {
            if (kDebugMode) debugPrint('[AutoMove] Skipping video (not in #整理完成): ${video.title}');
          }
        } catch (videoError) {
          if (kDebugMode) debugPrint('[AutoMove] Error moving video ${video.title}: $videoError');
        }
      }

      if (kDebugMode) {
        debugPrint('[AutoMove] Complete. Moved $movedCount/${watchedVideos.length} videos');
      }

      // 移动完成后标记为已观看状态（不删除记录，已观看页面仍可显示）
      if (movedVideoIds.isNotEmpty) {
        for (final video in watchedVideos) {
          if (video.id != null && movedVideoIds.contains(video.id!)) {
            try {
              final actorDirName = path.basename(path.dirname(video.folderPath));
              final episodeDirName = path.basename(video.folderPath);
              final newFolderPath = path.join(watchedFolder, actorDirName, episodeDirName);
              await _videoRepository.updateVideo(video.copyWith(
                isWatched: true,
                folderPath: newFolderPath,
                filePath: path.join(newFolderPath, path.basename(video.filePath)),
                posterPath: video.posterPath != null
                    ? path.join(newFolderPath, path.basename(video.posterPath!))
                    : null,
                fanartPath: video.fanartPath != null
                    ? path.join(newFolderPath, path.basename(video.fanartPath!))
                    : null,
              ));
              if (kDebugMode) debugPrint('[AutoMove] Marked video ID ${video.id} as watched');
            } catch (updateError) {
              if (kDebugMode) debugPrint('[AutoMove] Error marking video watched: $updateError');
            }
          }
        }
      }

      // 移动完成后刷新媒体库以更新UI
      if (movedCount > 0) {
        final libPath = libraryPath;
        if (libPath != null && libPath.isNotEmpty) {
          // 检查是否已有扫描正在进行，避免重复扫描
          if (_mediaScannerService.isScanning) {
            if (kDebugMode) debugPrint('[AutoMove] Scan already in progress, skipping post-move scan');
          } else {
            try {
              await _mediaScannerService.scanMediaLibrary(libPath);
              if (kDebugMode) debugPrint('[AutoMove] Media library refreshed after moving $movedCount videos');
            } catch (scanError) {
              if (kDebugMode) debugPrint('[AutoMove] Error refreshing media library: $scanError');
            }
          }

          // 通知 UI 层刷新
          _onAutoMoveCompleteController.add(movedCount);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoMove] Error in _performAutoMove: $e');
    }
  }

  Future<void> runScanNow() async {
    await _performScan();
  }

  Future<void> runMoveNow() async {
    await _performAutoMove();
  }

  Future<void> refreshLibrary() async {
    await _performScan();
  }

  void dispose() {
    stop();
    _onAutoMoveCompleteController.close();
  }
}
