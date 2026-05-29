import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;
import '../database/database_helper.dart';
import '../models/models.dart';
import '../repositories/video_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/category_repository.dart';
import 'app_logger.dart';

class MediaScannerService {
  final _log = AppLogger.instance;
  final VideoRepository _videoRepository;
  final ActorRepository _actorRepository;
  final CategoryRepository _categoryRepository;

  /// 扫描过程中实时通知UI刷新的回调
  void Function()? onVideoProcessed;

  /// 扫描进度回调：(已处理数, 总数)
  void Function(int processed, int total)? onProgress;

  /// 取消检查回调：返回 True 则中断扫描
  bool Function()? shouldCancel;

  /// 防止重复扫描的锁
  bool _isScanning = false;

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// NFO解析并行批次大小
  static const int _nfoBatchSize = 50;

  /// 数据库事务批次大小（每处理多少个视频提交一次事务）
  static const int _dbBatchSize = 50;

  MediaScannerService({
    VideoRepository? videoRepository,
    ActorRepository? actorRepository,
    CategoryRepository? categoryRepository,
    this.onVideoProcessed,
    this.onProgress,
    this.shouldCancel,
  })  : _videoRepository = videoRepository ?? VideoRepository(),
        _actorRepository = actorRepository ?? ActorRepository(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  Future<void> scanMediaLibrary(String libraryPath) async {
    // 防止重复扫描
    if (_isScanning) {
      _log.info('Scan', 'Already scanning, skipping duplicate request');
      return;
    }
    _isScanning = true;

    _log.info('Scan', 'Starting Media Scan, libraryPath=$libraryPath');

    try {
      final organizedPath = path.join(libraryPath, '#整理完成');
      final organizedDir = Directory(organizedPath);

      String scanPath;
      if (await organizedDir.exists()) {
        scanPath = organizedPath;
      } else {
        scanPath = libraryPath;
        if (kDebugMode) {
          debugPrint('📁 #整理完成 not found, scanning root: $scanPath');
        }
      }

      final scanDir = Directory(scanPath);
      if (!await scanDir.exists()) {
        _log.warning('Scan', 'Scan directory does not exist: $scanPath');
        return;
      }

      if (kDebugMode) {
        debugPrint('📂 Scanning folder: $scanPath');
      }

      final List<String> mp4Files = [];

      await for (final entity in scanDir.list(recursive: true, followLinks: false)) {
        try {
          if (entity is File && entity.path.endsWith('.mp4')) {
            mp4Files.add(entity.path);
          }
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint('═══ ERROR Processing File: ${entity.path} ═══');
            debugPrint('Error: $e');
            debugPrint('StackTrace: $stackTrace');
          }
        }
      }

      final existingVideos = await _videoRepository.getAllVideos();
      final videoMap = <String, Video>{};
      for (final v in existingVideos) {
        videoMap[v.filePath] = v;
      }

      if (kDebugMode) {
        debugPrint('[Scan] Found ${mp4Files.length} MP4 files, ${videoMap.length} in DB');
      }

      // 预加载黑名单到内存
      final ignoredCodesList = await _videoRepository.getAllIgnoredCodes();
      final ignoredSet = <String>{};
      for (final item in ignoredCodesList) {
        final code = item['code'] as String?;
        if (code != null) ignoredSet.add(code.toUpperCase());
      }

      // 预加载演员和分类到内存缓存
      final actorCache = <String, Actor>{};
      final allActors = await _actorRepository.getAllActors();
      for (final a in allActors) {
        actorCache[a.name] = a;
      }

      final categoryCache = <String, Category>{};
      final allCategories = await _categoryRepository.getAllCategories();
      for (final c in allCategories) {
        categoryCache['${c.type}:${c.name}'] = c;
      }

      int skippedCount = 0;
      int processedCount = 0;
      int totalProcessed = 0;
      final totalFiles = mp4Files.length;

      // 通知初始进度
      onProgress?.call(0, totalFiles);

      // ═══ 第一阶段：确定哪些文件需要处理 ═══
      final needProcess = <String, Video?>{};
      for (final filePath in mp4Files) {
        final folderPath = path.dirname(filePath);
        final folderName = path.basename(folderPath);
        final codeMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(folderName);
        final code = codeMatch?.group(0) ?? folderName;

        if (ignoredSet.contains(code.toUpperCase())) {
          skippedCount++;
          continue;
        }

        final existingVideo = videoMap[filePath];
        final nfoPath = path.join(folderPath, 'movie.nfo');
        final nfoFile = File(nfoPath);
        final hasNfo = await nfoFile.exists();

        if (existingVideo != null) {
          if (!hasNfo || (existingVideo.nfoPath != null && !await File(existingVideo.nfoPath!).exists())) {
            skippedCount++;
            continue;
          }
          if (hasNfo) {
            final nfoModified = await nfoFile.lastModified();
            final dbNfoModified = await File(existingVideo.nfoPath!).lastModified();
            if (!nfoModified.isAfter(dbNfoModified)) {
              skippedCount++;
              continue;
            }
          }
        }

        needProcess[filePath] = existingVideo;
      }

      _log.info('Scan', '${mp4Files.length} files: ${needProcess.length} need processing, $skippedCount skipped');

      // ═══ 第二阶段：分批并行解析NFO文件 ═══
      final nfoDataMap = <String, Map<String, dynamic>?>{};
      if (needProcess.isNotEmpty) {
        final filePaths = needProcess.keys.toList();
        for (var i = 0; i < filePaths.length; i += _nfoBatchSize) {
          if (shouldCancel?.call() == true) break;

          final batch = filePaths.sublist(i, i + _nfoBatchSize > filePaths.length ? filePaths.length : i + _nfoBatchSize);
          final results = await Future.wait(
            batch.map((filePath) async {
              final folderPath = path.dirname(filePath);
              final nfoPath = path.join(folderPath, 'movie.nfo');
              Map<String, dynamic>? nfoData;
              try {
                if (await File(nfoPath).exists()) {
                  nfoData = await _parseNfoFile(nfoPath);
                }
              } catch (e) {
                if (kDebugMode) debugPrint('[Scan] Warning: Failed to parse NFO $nfoPath: $e');
              }
              return MapEntry(filePath, nfoData);
            }),
          );
          nfoDataMap.addEntries(results);
        }

        if (kDebugMode) {
          debugPrint('[Scan] NFO parsing complete: ${nfoDataMap.length} files parsed');
        }
      }

      // ═══ 第三阶段：批量事务写入数据库 ═══
      if (needProcess.isNotEmpty) {
        final db = await DatabaseHelper.database;
        final entries = needProcess.entries.toList();

        // 分批处理，每批一个事务
        for (var batchStart = 0; batchStart < entries.length; batchStart += _dbBatchSize) {
          if (shouldCancel?.call() == true) {
            if (kDebugMode) debugPrint('[Scan] Scan cancelled by user');
            break;
          }

          final batchEnd = batchStart + _dbBatchSize > entries.length ? entries.length : batchStart + _dbBatchSize;
          final batchEntries = entries.sublist(batchStart, batchEnd);

          try {
            await db.transaction((txn) async {
              for (final entry in batchEntries) {
                final filePath = entry.key;
                final existingVideo = entry.value;
                final nfoData = nfoDataMap[filePath];

                try {
                  await _processVideoInTransaction(
                    txn: txn,
                    videoPath: filePath,
                    existingVideo: existingVideo,
                    nfoData: nfoData,
                    actorCache: actorCache,
                    categoryCache: categoryCache,
                  );
                  processedCount++;
                } catch (e) {
                  if (kDebugMode) debugPrint('[Scan] Error processing $filePath: $e');
                  skippedCount++;
                }

                totalProcessed++;
              }
            });
          } catch (e) {
            if (kDebugMode) debugPrint('[Scan] Transaction error for batch starting at $batchStart: $e');
            // 事务失败时，尝试逐条处理该批次
            for (final entry in batchEntries) {
              if (shouldCancel?.call() == true) break;
              try {
                await _processVideoFileWithCache(
                  videoPath: entry.key,
                  existingVideoOverride: entry.value,
                  nfoDataOverride: nfoDataMap[entry.key],
                  actorCache: actorCache,
                  categoryCache: categoryCache,
                );
                processedCount++;
              } catch (e) {
                if (kDebugMode) debugPrint('[Scan] Fallback error processing ${entry.key}: $e');
                skippedCount++;
              }
              totalProcessed++;
            }
          }

          // 通知进度
          final progressCount = (skippedCount + totalProcessed).clamp(0, totalFiles);
          onProgress?.call(progressCount, totalFiles);

          if (totalProcessed % 20 == 0 || batchEnd >= entries.length) {
            onVideoProcessed?.call();
          }

          if (kDebugMode && totalProcessed % 100 == 0) {
            debugPrint('[Scan] Progress: $totalProcessed/${needProcess.length} (processed=$processedCount)');
          }
        }
      }

      // 最终刷新
      onVideoProcessed?.call();

      _log.info('Scan', 'Completed: ${mp4Files.length} files (processed=$processedCount, skipped=$skippedCount)');

      final scannedSet = mp4Files.toSet();
      for (final video in existingVideos) {
        try {
          if (!scannedSet.contains(video.filePath)) {
            final f = File(video.filePath);
            if (!await f.exists()) {
              if (video.isFavorite) {
                final backupRoot = path.join(libraryPath, 'Backup');
                String backupDirPath;
                if (video.folderPath.startsWith(backupRoot)) {
                  backupDirPath = video.folderPath;
                } else {
                  backupDirPath = path.join(backupRoot,
                      path.basename(path.dirname(video.folderPath)),
                      path.basename(video.folderPath));
                }
                final backupDir = Directory(backupDirPath);
                final backupExists = await backupDir.exists();

                if (kDebugMode) {
                  debugPrint('[Scan-Delete] video.filePath=${video.filePath}');
                  debugPrint('[Scan-Delete] video.folderPath=${video.folderPath}');
                  debugPrint('[Scan-Delete] video.isFavorite=${video.isFavorite}, video.isDeleted=${video.isDeleted}');
                  debugPrint('[Scan-Delete] backupDirPath=$backupDirPath');
                  debugPrint('[Scan-Delete] backupExists=$backupExists');
                  if (backupExists) {
                    final contents = await backupDir.list().toList();
                    debugPrint('[Scan-Delete] backupContents=${contents.map((e) => path.basename(e.path)).join(', ')}');
                  }
                }

                if (backupExists) {
                  final backupNfo = path.join(backupDirPath, 'movie.nfo');
                  final backupPoster = path.join(backupDirPath, 'poster.jpg');
                  final backupFanart = path.join(backupDirPath, 'fanart.jpg');
                  final nfoExists = await File(backupNfo).exists();
                  final posterExists = await File(backupPoster).exists();
                  final fanartExists = await File(backupFanart).exists();

                  if (kDebugMode) {
                    debugPrint('[Scan-Delete] nfoExists=$nfoExists, posterExists=$posterExists, fanartExists=$fanartExists');
                  }

                  await _videoRepository.updateVideo(video.copyWith(
                    isDeleted: true,
                    folderPath: backupDirPath,
                    nfoPath: nfoExists ? backupNfo : null,
                    posterPath: posterExists ? backupPoster : null,
                    fanartPath: fanartExists ? backupFanart : null,
                  ));

                  if (kDebugMode) {
                    debugPrint('[Scan-Delete] Updated video paths to backup: ${video.title}');
                  }
                } else {
                  if (kDebugMode) {
                    debugPrint('[Scan-Delete] No backup found, just marking deleted: ${video.title}');
                  }
                  await _videoRepository.updateVideo(video.copyWith(isDeleted: true));
                }
              } else {
                if (kDebugMode) {
                  debugPrint('[Scan] Removing DB entry for missing file: ${video.filePath} (watched=${video.isWatched}, watchCount=${video.watchCount})');
                }
                await _videoRepository.deleteVideoByPath(video.filePath);
              }
            }
          } else if (video.isDeleted) {
            if (kDebugMode) {
              debugPrint('[Scan] Restoring deleted video (file found again): ${video.title}');
            }
            await _videoRepository.updateVideo(video.copyWith(isDeleted: false));
          } else if (video.isFavorite && (video.posterPath == null || video.fanartPath == null || video.nfoPath == null)) {
            final backupRoot = path.join(libraryPath, 'Backup');
            String backupDirPath;
            if (video.folderPath.startsWith(backupRoot)) {
              backupDirPath = video.folderPath;
            } else {
              backupDirPath = path.join(backupRoot,
                  path.basename(path.dirname(video.folderPath)),
                  path.basename(video.folderPath));
            }
            final backupDir = Directory(backupDirPath);
            if (await backupDir.exists()) {
              final backupNfo = path.join(backupDirPath, 'movie.nfo');
              final backupPoster = path.join(backupDirPath, 'poster.jpg');
              final backupFanart = path.join(backupDirPath, 'fanart.jpg');
              final nfoExists = await File(backupNfo).exists();
              final posterExists = await File(backupPoster).exists();
              final fanartExists = await File(backupFanart).exists();
              if (nfoExists || posterExists || fanartExists) {
                if (kDebugMode) {
                  debugPrint('[Scan] Patching missing paths from backup: ${video.title}');
                }
                await _videoRepository.updateVideo(video.copyWith(
                  folderPath: backupDirPath,
                  nfoPath: nfoExists ? backupNfo : video.nfoPath,
                  posterPath: posterExists ? backupPoster : video.posterPath,
                  fanartPath: fanartExists ? backupFanart : video.fanartPath,
                ));
              }
            }
          }
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint('═══ ERROR Processing Video: ${video.filePath} ═══');
            debugPrint('Error: $e');
            debugPrint('StackTrace: $stackTrace');
          }
        }
      }

      await _cleanupIgnoredVideos();

      await _scanBackupDirectory(libraryPath);

      await _cleanupOrphanedActors();

      _log.info('Scan', 'Media Scan Complete, scanned ${mp4Files.length} files');
    } catch (e, stackTrace) {
      _log.error('Scan', 'FATAL ERROR in Media Scan', e, stackTrace);
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 在事务内处理单个视频的所有数据库操作
  Future<void> _processVideoInTransaction({
    required Transaction txn,
    required String videoPath,
    required Video? existingVideo,
    required Map<String, dynamic>? nfoData,
    required Map<String, Actor> actorCache,
    required Map<String, Category> categoryCache,
  }) async {
    final folderPath = path.dirname(videoPath);
    final posterPath = path.join(folderPath, 'poster.jpg');
    final fanartPath = path.join(folderPath, 'fanart.jpg');

    // 检查文件是否存在（文件I/O不在事务中，但这里需要结果）
    final posterExists = await File(posterPath).exists();
    final fanartExists = await File(fanartPath).exists();
    final nfoFilePath = path.join(folderPath, 'movie.nfo');
    final nfoExists = await File(nfoFilePath).exists();

    String? title = nfoData?['title'];
    if (title == null || title.isEmpty) {
      title = _extractTitleFromFolderName(folderPath);
    }

    final video = Video(
      id: existingVideo?.id,
      filePath: videoPath,
      folderPath: folderPath,
      title: title,
      plot: nfoData?['plot'],
      posterPath: posterExists ? posterPath : null,
      fanartPath: fanartExists ? fanartPath : null,
      nfoPath: nfoExists ? nfoFilePath : null,
      watchCount: existingVideo?.watchCount ?? 0,
      lastWatchedTime: existingVideo?.lastWatchedTime,
      isFavorite: existingVideo?.isFavorite ?? false,
      isWatched: existingVideo?.isWatched ?? false,
    );

    int videoId;
    if (existingVideo != null) {
      await txn.update(
        'videos',
        video.toMap(),
        where: 'id = ?',
        whereArgs: [video.id],
      );
      videoId = existingVideo.id!;
    } else {
      videoId = await txn.insert(
        'videos',
        video.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    if (nfoData != null) {
      await _processNfoDataInTransaction(
        txn: txn,
        videoId: videoId,
        nfoData: nfoData,
        actorCache: actorCache,
        categoryCache: categoryCache,
      );
    }
  }

  /// 在事务内处理NFO关联数据
  Future<void> _processNfoDataInTransaction({
    required Transaction txn,
    required int videoId,
    required Map<String, dynamic> nfoData,
    required Map<String, Actor> actorCache,
    required Map<String, Category> categoryCache,
  }) async {
    // 处理演员
    final actors = nfoData['actors'] as List<Map<String, dynamic>>?;
    if (actors != null) {
      for (final actorData in actors) {
        try {
          final actorName = actorData['name'] as String?;
          if (actorName != null && actorName.isNotEmpty) {
            var actor = actorCache[actorName];
            if (actor == null) {
              // 在事务内插入演员
              final id = await txn.insert(
                'actors',
                Actor(name: actorName).toMap(),
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              if (id > 0) {
                // 新插入的演员，从DB获取完整信息
                final maps = await txn.query('actors', where: 'name = ?', whereArgs: [actorName], limit: 1);
                if (maps.isNotEmpty) {
                  actor = Actor.fromMap(maps.first);
                  actorCache[actorName] = actor;
                }
              } else {
                // 已存在的演员，从缓存中无法获取id，需要查询
                final maps = await txn.query('actors', where: 'name = ?', whereArgs: [actorName], limit: 1);
                if (maps.isNotEmpty) {
                  actor = Actor.fromMap(maps.first);
                  actorCache[actorName] = actor;
                }
              }
            }
            if (actor != null) {
              await txn.insert(
                'video_actors',
                {'video_id': videoId, 'actor_id': actor.id},
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Warning: Failed to link actor in txn: $e');
        }
      }
    }

    // 处理标签
    final genres = nfoData['genres'] as List<String>?;
    if (genres != null) {
      for (final genreName in genres) {
        try {
          if (genreName.isNotEmpty) {
            await _linkCategoryInTransaction(
              txn: txn,
              videoId: videoId,
              type: Category.typeTag,
              name: genreName,
              categoryCache: categoryCache,
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Warning: Failed to link genre "$genreName" in txn: $e');
        }
      }
    }

    // 处理系列
    final seriesName = nfoData['set'] as String?;
    if (seriesName != null && seriesName.isNotEmpty) {
      try {
        await _linkCategoryInTransaction(
          txn: txn,
          videoId: videoId,
          type: Category.typeSeries,
          name: seriesName,
          categoryCache: categoryCache,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Scan] Warning: Failed to link series "$seriesName" in txn: $e');
      }
    }

    // 处理制作商
    final studioName = nfoData['studio'] as String?;
    if (studioName != null && studioName.isNotEmpty) {
      try {
        await _linkCategoryInTransaction(
          txn: txn,
          videoId: videoId,
          type: Category.typeStudio,
          name: studioName,
          categoryCache: categoryCache,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Scan] Warning: Failed to link studio "$studioName" in txn: $e');
      }
    }
  }

  /// 在事务内关联分类
  Future<void> _linkCategoryInTransaction({
    required Transaction txn,
    required int videoId,
    required String type,
    required String name,
    required Map<String, Category> categoryCache,
  }) async {
    final cacheKey = '$type:$name';
    var category = categoryCache[cacheKey];
    if (category == null) {
      await txn.insert(
        'categories',
        Category(type: type, name: name).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final maps = await txn.query(
        'categories',
        where: 'type = ? AND name = ?',
        whereArgs: [type, name],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        category = Category.fromMap(maps.first);
        categoryCache[cacheKey] = category;
      }
    }
    if (category != null) {
      await txn.insert(
        'video_categories',
        {'video_id': videoId, 'category_id': category.id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _cleanupIgnoredVideos() async {
    try {
      final ignoredCodes = await _videoRepository.getAllIgnoredCodes();
      if (ignoredCodes.isEmpty) return;

      final ignoredSet = <String>{};
      for (final item in ignoredCodes) {
        final code = item['code'] as String?;
        if (code != null) ignoredSet.add(code.toUpperCase());
      }
      if (ignoredSet.isEmpty) return;

      if (kDebugMode) {
        debugPrint('[Cleanup] Ignored codes: ${ignoredSet.join(', ')}');
      }

      final allVideos = await _videoRepository.getAllVideos();
      int removedCount = 0;
      for (final video in allVideos) {
        String videoCode = '';
        final titleMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(video.title ?? '');
        if (titleMatch != null) {
          videoCode = titleMatch.group(0)!.toUpperCase();
        } else {
          final folderName = path.basename(video.folderPath);
          final folderMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(folderName);
          if (folderMatch != null) {
            videoCode = folderMatch.group(0)!.toUpperCase();
          }
        }

        if (videoCode.isNotEmpty && ignoredSet.contains(videoCode)) {
          await _videoRepository.deleteVideo(video.id!);
          removedCount++;
          if (kDebugMode) {
            debugPrint('[Cleanup] Removed ignored video: $videoCode - ${video.title}');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[Cleanup] Removed $removedCount videos matching ignored codes');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Cleanup] Error cleaning ignored videos: $e');
        debugPrint('StackTrace: $stackTrace');
      }
    }
  }

  /// 清理没有关联视频且未收藏的演员及其本地头像文件
  Future<void> _cleanupOrphanedActors() async {
    try {
      final orphanedActors = await _actorRepository.getOrphanedActors();
      if (orphanedActors.isEmpty) return;

      if (kDebugMode) {
        debugPrint('[Cleanup] Found ${orphanedActors.length} orphaned actors');
      }

      for (final actor in orphanedActors) {
        try {
          // 删除本地头像文件
          if (actor.avatarUrl != null && actor.avatarUrl!.isNotEmpty) {
            final avatarFile = File(actor.avatarUrl!);
            if (await avatarFile.exists()) {
              await avatarFile.delete();
              if (kDebugMode) debugPrint('[Cleanup] Deleted avatar: ${actor.avatarUrl}');
            }
          }

          // 删除演员记录
          if (actor.id != null) {
            await _actorRepository.deleteActor(actor.id!);
            if (kDebugMode) debugPrint('[Cleanup] Deleted actor: ${actor.name} (id=${actor.id})');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Cleanup] Error cleaning actor ${actor.name}: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[Cleanup] Actor cleanup complete');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Cleanup] Error during orphaned actor cleanup: $e');
        debugPrint('StackTrace: $stackTrace');
      }
    }
  }

  /// 使用缓存的视频处理（降级方案，事务失败时逐条处理）
  Future<void> _processVideoFileWithCache({
    required String videoPath,
    Video? existingVideoOverride,
    Map<String, dynamic>? nfoDataOverride,
    required Map<String, Actor> actorCache,
    required Map<String, Category> categoryCache,
  }) async {
    try {
      final folderPath = path.dirname(videoPath);
      final posterPath = path.join(folderPath, 'poster.jpg');
      final fanartPath = path.join(folderPath, 'fanart.jpg');

      Map<String, dynamic>? nfoData = nfoDataOverride;
      // 如果没有预解析的NFO数据，则现场解析
      if (nfoData == null) {
        final nfoPath = path.join(folderPath, 'movie.nfo');
        final nfoFile = File(nfoPath);
        if (await nfoFile.exists()) {
          nfoData = await _parseNfoFile(nfoPath);
        }
      }

      final existingVideo = existingVideoOverride;

      if (existingVideo != null && nfoData == null) {
        if (existingVideo.nfoPath == null || !await File(existingVideo.nfoPath!).exists()) {
          String? poster = null;
          if (await File(posterPath).exists()) {
            poster = posterPath;
          }

          String? fanart = null;
          if (await File(fanartPath).exists()) {
            fanart = fanartPath;
          }

          if (existingVideo.posterPath != poster || existingVideo.fanartPath != fanart) {
            await _videoRepository.updateVideoPaths(
              existingVideo.id!,
              posterPath: poster,
              fanartPath: fanart,
            );
          }
          return;
        }

        final existingNfoModified = await File(existingVideo.nfoPath!).lastModified();
        final nfoPath = path.join(folderPath, 'movie.nfo');
        final currentNfoModified = await File(nfoPath).lastModified();

        if (!existingNfoModified.isAfter(currentNfoModified) && existingVideo.filePath == videoPath) {
          return;
        }
      }

      String? title = nfoData?['title'];
      if (title == null || title.isEmpty) {
        title = _extractTitleFromFolderName(folderPath);
      }

      String? poster = null;
      if (await File(posterPath).exists()) {
        poster = posterPath;
      }

      String? fanart = null;
      if (await File(fanartPath).exists()) {
        fanart = fanartPath;
      }

      String? nfo = null;
      final nfoFilePath = path.join(folderPath, 'movie.nfo');
      if (await File(nfoFilePath).exists()) {
        nfo = nfoFilePath;
      }

      final video = Video(
        id: existingVideo?.id,
        filePath: videoPath,
        folderPath: folderPath,
        title: title,
        plot: nfoData?['plot'],
        posterPath: poster,
        fanartPath: fanart,
        nfoPath: nfo,
        watchCount: existingVideo?.watchCount ?? 0,
        lastWatchedTime: existingVideo?.lastWatchedTime,
        isFavorite: existingVideo?.isFavorite ?? false,
        isWatched: existingVideo?.isWatched ?? false,
      );

      int videoId;
      if (existingVideo != null) {
        await _videoRepository.updateVideo(video);
        videoId = existingVideo.id!;
      } else {
        videoId = await _videoRepository.insertVideo(video);
      }

      if (nfoData != null) {
        await _processNfoDataWithCache(videoId, nfoData, actorCache, categoryCache);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('═══ ERROR Processing Video: $videoPath ═══');
        debugPrint('Error: $e');
        debugPrint('StackTrace: $stackTrace');
      }
      rethrow;
    }
  }

  /// 使用内存缓存处理NFO关联数据（降级方案）
  Future<void> _processNfoDataWithCache(
    int videoId,
    Map<String, dynamic> nfoData,
    Map<String, Actor> actorCache,
    Map<String, Category> categoryCache,
  ) async {
    try {
      final actors = nfoData['actors'] as List<Map<String, dynamic>>?;
      if (actors != null) {
        for (final actorData in actors) {
          try {
            final actorName = actorData['name'] as String?;
            if (actorName != null && actorName.isNotEmpty) {
              var actor = actorCache[actorName];
              if (actor == null) {
                await _actorRepository.insertActorIfNotExists(Actor(name: actorName));
                actor = await _actorRepository.getActorByName(actorName);
                if (actor != null) {
                  actorCache[actorName] = actor;
                }
              }
              if (actor != null) {
                await _videoRepository.addActorToVideo(videoId, actor.id!);
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[Scan] Warning: Failed to link actor: $e');
          }
        }
      }

      final genres = nfoData['genres'] as List<String>?;
      if (genres != null) {
        for (final genreName in genres) {
          try {
            if (genreName.isNotEmpty) {
              final cacheKey = '${Category.typeTag}:$genreName';
              var category = categoryCache[cacheKey];
              if (category == null) {
                await _categoryRepository.insertCategoryIfNotExists(
                  Category(type: Category.typeTag, name: genreName),
                );
                category = await _categoryRepository.getCategoryByNameAndType(genreName, Category.typeTag);
                if (category != null) {
                  categoryCache[cacheKey] = category;
                }
              }
              if (category != null) {
                await _videoRepository.addCategoryToVideo(videoId, category.id!);
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[Scan] Warning: Failed to link genre "$genreName": $e');
          }
        }
      }

      final seriesName = nfoData['set'] as String?;
      if (seriesName != null && seriesName.isNotEmpty) {
        try {
          final cacheKey = '${Category.typeSeries}:$seriesName';
          var category = categoryCache[cacheKey];
          if (category == null) {
            await _categoryRepository.insertCategoryIfNotExists(
              Category(type: Category.typeSeries, name: seriesName),
            );
            category = await _categoryRepository.getCategoryByNameAndType(seriesName, Category.typeSeries);
            if (category != null) {
              categoryCache[cacheKey] = category;
            }
          }
          if (category != null) {
            await _videoRepository.addCategoryToVideo(videoId, category.id!);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Warning: Failed to link series "$seriesName": $e');
        }
      }

      final studioName = nfoData['studio'] as String?;
      if (studioName != null && studioName.isNotEmpty) {
        try {
          final cacheKey = '${Category.typeStudio}:$studioName';
          var category = categoryCache[cacheKey];
          if (category == null) {
            await _categoryRepository.insertCategoryIfNotExists(
              Category(type: Category.typeStudio, name: studioName),
            );
            category = await _categoryRepository.getCategoryByNameAndType(studioName, Category.typeStudio);
            if (category != null) {
              categoryCache[cacheKey] = category;
            }
          }
          if (category != null) {
            await _videoRepository.addCategoryToVideo(videoId, category.id!);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Warning: Failed to link studio "$studioName": $e');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Scan] Warning: NFO data processing partially failed for videoId=$videoId: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _parseNfoFile(String nfoPath) async {
    try {
      final content = await File(nfoPath).readAsString();
      final document = XmlDocument.parse(content);
      final root = document.rootElement;

      final Map<String, dynamic> data = {};

      final titleElement = root.findElements('title').firstOrNull;
      if (titleElement != null) {
        data['title'] = titleElement.innerText;
      }

      final plotElement = root.findElements('plot').firstOrNull;
      if (plotElement != null) {
        data['plot'] = plotElement.innerText;
      }

      final yearElement = root.findElements('year').firstOrNull;
      if (yearElement != null) {
        data['year'] = yearElement.innerText;
      }

      final runtimeElement = root.findElements('runtime').firstOrNull;
      if (runtimeElement != null) {
        data['runtime'] = runtimeElement.innerText;
      }

      final actorElements = root.findElements('actor');
      final List<Map<String, dynamic>> actors = [];
      for (final actorElement in actorElements) {
        final nameElement = actorElement.findElements('name').firstOrNull;
        if (nameElement != null) {
          actors.add({
            'name': nameElement.innerText,
          });
        }
      }
      data['actors'] = actors;

      final genreElements = root.findElements('genre');
      final List<String> genres = [];
      for (final genreElement in genreElements) {
        genres.add(genreElement.innerText);
      }
      data['genres'] = genres;

      final setElement = root.findElements('set').firstOrNull;
      if (setElement != null) {
        data['set'] = setElement.innerText;
      }

      final studioElement = root.findElements('studio').firstOrNull;
      if (studioElement != null) {
        data['studio'] = studioElement.innerText;
      }

      return data;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('═══ ERROR Parsing NFO: $nfoPath ═══');
        debugPrint('Error: $e');
        debugPrint('StackTrace: $stackTrace');
      }
      rethrow;
    }
  }

  String _extractTitleFromFolderName(String folderPath) {
    final folderName = path.basename(folderPath);
    final cleanName = folderName
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\d{4}'), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    return cleanName.isEmpty ? folderName : cleanName;
  }

  Future<void> _scanBackupDirectory(String libraryPath) async {
    try {
      final backupPath = path.join(libraryPath, 'Backup');
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        if (kDebugMode) debugPrint('[Backup] Backup directory does not exist: $backupPath');
        return;
      }

      final allVideos = await _videoRepository.getAllVideos();
      final allCodes = <String, String>{};
      for (final v in allVideos) {
        final titleMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(v.title ?? '');
        if (titleMatch != null) {
          allCodes[titleMatch.group(0)!.toUpperCase()] = v.filePath;
        } else {
          final folderName = path.basename(v.folderPath);
          final folderMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(folderName);
          if (folderMatch != null) {
            allCodes[folderMatch.group(0)!.toUpperCase()] = v.filePath;
          }
        }
      }

      // if (kDebugMode) {
      //   debugPrint('[Backup] allCodes in DB: ${allCodes.keys.join(', ')}');
      // }

      final actorCache = <String, Actor>{};
      final allActors = await _actorRepository.getAllActors();
      for (final a in allActors) {
        actorCache[a.name] = a;
      }

      final categoryCache = <String, Category>{};
      final allCategories = await _categoryRepository.getAllCategories();
      for (final c in allCategories) {
        categoryCache['${c.type}:${c.name}'] = c;
      }

      await for (final actorEntity in backupDir.list(followLinks: false)) {
        if (actorEntity is! Directory) continue;
        await for (final episodeEntity in actorEntity.list(followLinks: false)) {
          if (episodeEntity is! Directory) continue;

          final episodeDirName = path.basename(episodeEntity.path);
          final codeMatch = RegExp(r'[A-Za-z]{2,5}[-_]?\d{3,5}', caseSensitive: false).firstMatch(episodeDirName);
          if (codeMatch == null) continue;
          final code = codeMatch.group(0)!;

          if (allCodes.containsKey(code.toUpperCase())) continue;

          final nfoFilePath = path.join(episodeEntity.path, 'movie.nfo');
          final posterFilePath = path.join(episodeEntity.path, 'poster.jpg');
          final fanartFilePath = path.join(episodeEntity.path, 'fanart.jpg');

          String? title;
          Map<String, dynamic>? nfoData;
          if (await File(nfoFilePath).exists()) {
            try {
              nfoData = await _parseNfoFile(nfoFilePath);
              title = nfoData['title'] as String?;
            } catch (e) {
              if (kDebugMode) debugPrint('[Backup] Failed to parse NFO: $nfoFilePath');
            }
          }
          if (title == null || title.isEmpty) {
            title = _extractTitleFromFolderName(episodeEntity.path);
          }

          final existingByPath = await _videoRepository.getVideoByPath(nfoFilePath);
          if (existingByPath != null) continue;

          final video = Video(
            filePath: nfoFilePath,
            folderPath: episodeEntity.path,
            title: title,
            plot: nfoData?['plot'] as String?,
            posterPath: await File(posterFilePath).exists() ? posterFilePath : null,
            fanartPath: await File(fanartFilePath).exists() ? fanartFilePath : null,
            nfoPath: await File(nfoFilePath).exists() ? nfoFilePath : null,
            isFavorite: true,
            isDeleted: true,
          );

          final videoId = await _videoRepository.insertVideo(video);

          if (nfoData != null) {
            await _processNfoDataWithCache(videoId, nfoData, actorCache, categoryCache);
          }

          if (kDebugMode) {
            debugPrint('[Backup] Restored virtual video: $code - $title');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Backup] Error scanning backup directory: $e');
      }
    }
  }

  Future<void> backupFavoriteFiles(Video video, String libraryPath) async {
    try {
      final backupRoot = path.join(libraryPath, 'Backup');
      final actorDirName = path.basename(path.dirname(video.folderPath));
      final episodeDirName = path.basename(video.folderPath);

      final backupDir = Directory(path.join(backupRoot, actorDirName, episodeDirName));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      if (video.nfoPath != null) {
        final src = File(video.nfoPath!);
        if (await src.exists()) {
          await src.copy(path.join(backupDir.path, 'movie.nfo'));
        }
      }

      if (video.posterPath != null) {
        final src = File(video.posterPath!);
        if (await src.exists()) {
          await src.copy(path.join(backupDir.path, 'poster.jpg'));
        }
      }

      if (video.fanartPath != null) {
        final src = File(video.fanartPath!);
        if (await src.exists()) {
          await src.copy(path.join(backupDir.path, 'fanart.jpg'));
        }
      }

      if (kDebugMode) {
        debugPrint('[Backup] Backed up favorite files to: ${backupDir.path}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Backup] Error backing up favorite files: $e');
      }
    }
  }

  Future<void> deleteBackupFiles(Video video, String libraryPath) async {
    try {
      final backupRoot = path.join(libraryPath, 'Backup');
      String backupDirPath;

      if (video.isDeleted) {
        backupDirPath = video.folderPath;
      } else {
        final actorDirName = path.basename(path.dirname(video.folderPath));
        final episodeDirName = path.basename(video.folderPath);
        backupDirPath = path.join(backupRoot, actorDirName, episodeDirName);
      }

      final backupDir = Directory(backupDirPath);
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
        if (kDebugMode) {
          debugPrint('[Backup] Deleted backup directory: $backupDirPath');
        }
      }

      final actorDir = backupDir.parent;
      if (await actorDir.exists()) {
        final contents = await actorDir.list().toList();
        if (contents.isEmpty) {
          await actorDir.delete();
          if (kDebugMode) {
            debugPrint('[Backup] Deleted empty actor directory: ${actorDir.path}');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Backup] Error deleting backup files: $e');
      }
    }
  }

  Future<void> moveVideoToWatched(Video video, String watchedFolder) async {
    try {
      final sourceDir = Directory(video.folderPath);
      if (!await sourceDir.exists()) {
        if (kDebugMode) debugPrint('[MoveToWatched] Source directory does not exist: ${video.folderPath}');
        return;
      }

      final actorDirName = path.basename(path.dirname(video.folderPath));
      final episodeDirName = path.basename(video.folderPath);

      if (kDebugMode) {
        debugPrint('[MoveToWatched] Moving: ${video.title}');
        debugPrint('[MoveToWatched]   Source: ${video.folderPath}');
        debugPrint('[MoveToWatched]   Actor dir: $actorDirName');
        debugPrint('[MoveToWatched]   Episode dir: $episodeDirName');
        debugPrint('[MoveToWatched]   Target base: $watchedFolder');
      }

      final targetActorDir = Directory(path.join(watchedFolder, actorDirName));
      if (!await targetActorDir.exists()) {
        await targetActorDir.create(recursive: true);
        if (kDebugMode) debugPrint('[MoveToWatched] Created actor directory: ${targetActorDir.path}');
      }
      final targetEpisodeDir = Directory(path.join(targetActorDir.path, episodeDirName));
      // Use a temporary location first to avoid data loss if rename fails
      final tempTargetDir = Directory(path.join(targetActorDir.path, '${episodeDirName}.moving'));
      if (await tempTargetDir.exists()) {
        await tempTargetDir.delete(recursive: true);
      }
      if (await targetEpisodeDir.exists()) {
        // Move existing target to temp location instead of deleting
        await targetEpisodeDir.rename(tempTargetDir.path);
      }

      try {
        await sourceDir.rename(targetEpisodeDir.path);
        // Success - delete the old target that was moved to temp
        if (await tempTargetDir.exists()) {
          await tempTargetDir.delete(recursive: true);
          if (kDebugMode) debugPrint('[MoveToWatched] Deleted old target directory');
        }
      } catch (e) {
        // Rename failed - restore the original target from temp
        if (await tempTargetDir.exists()) {
          await tempTargetDir.rename(targetEpisodeDir.path);
          if (kDebugMode) debugPrint('[MoveToWatched] Restored original target directory after failed move');
        }
        rethrow;
      }

      if (kDebugMode) {
        debugPrint('[MoveToWatched] Successfully renamed to: ${targetEpisodeDir.path}');
      }

      final newFolderPath = targetEpisodeDir.path;
      final fileName = path.basename(video.filePath);
      final newFilePath = path.join(newFolderPath, fileName);

      String? newPosterPath;
      if (video.posterPath != null) {
        final p = File(path.join(newFolderPath, 'poster.jpg'));
        if (await p.exists()) newPosterPath = p.path;
      }
      String? newFanartPath;
      if (video.fanartPath != null) {
        final f = File(path.join(newFolderPath, 'fanart.jpg'));
        if (await f.exists()) newFanartPath = f.path;
      }
      String? newNfoPath;
      if (video.nfoPath != null) {
        final n = File(path.join(newFolderPath, 'movie.nfo'));
        if (await n.exists()) newNfoPath = n.path;
      }

      await _videoRepository.updateVideoPaths(
        video.id!,
        filePath: newFilePath,
        folderPath: newFolderPath,
        posterPath: newPosterPath,
        fanartPath: newFanartPath,
        nfoPath: newNfoPath,
      );

      if (kDebugMode) {
        debugPrint('[MoveToWatched] Database paths updated successfully');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('═══ ERROR Moving Video to Watched ═══');
        debugPrint('Video: ${video.filePath}');
        debugPrint('Error: $e');
        debugPrint('StackTrace: $stackTrace');
      }
      rethrow;
    }
  }
}
