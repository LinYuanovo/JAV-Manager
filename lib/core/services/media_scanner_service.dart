import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/video_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/category_repository.dart';

class MediaScannerService {
  final VideoRepository _videoRepository;
  final ActorRepository _actorRepository;
  final CategoryRepository _categoryRepository;

  MediaScannerService({
    VideoRepository? videoRepository,
    ActorRepository? actorRepository,
    CategoryRepository? categoryRepository,
  })  : _videoRepository = videoRepository ?? VideoRepository(),
        _actorRepository = actorRepository ?? ActorRepository(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  Future<void> scanMediaLibrary(String libraryPath) async {
    if (kDebugMode) {
      debugPrint('═══ Starting Media Scan ═══');
      debugPrint('Library Path: $libraryPath');
    }

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
        if (kDebugMode) {
          debugPrint('📁 Scan directory does not exist: $scanPath');
        }
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

      const batchSize = 20;
      int skippedCount = 0;
      int processedCount = 0;

      final batches = <List<String>>[];
      for (var i = 0; i < mp4Files.length; i += batchSize) {
        final end = (i + batchSize > mp4Files.length) ? mp4Files.length : i + batchSize;
        batches.add(mp4Files.sublist(i, end));
      }

      for (final batch in batches) {
        final results = await Future.wait(batch.map((filePath) =>
          _processVideoFileFast(filePath, videoMap)
        ));
        processedCount += results.where((r) => r).length;
        skippedCount += results.where((r) => !r).length;

        if (kDebugMode && (processedCount + skippedCount) % 100 == 0) {
          debugPrint('[Scan] Progress: ${processedCount + skippedCount}/${mp4Files.length} (processed=$processedCount, skipped=$skippedCount)');
        }
      }

      if (kDebugMode) {
        debugPrint('[Scan] Completed processing all ${mp4Files.length} files (processed=$processedCount, skipped=$skippedCount)');
      }

      final scannedSet = mp4Files.toSet();
      for (final video in existingVideos) {
        try {
          if (!scannedSet.contains(video.filePath)) {
            final f = File(video.filePath);
            if (!await f.exists()) {
              if (kDebugMode) {
                debugPrint('[Scan] Removing DB entry for missing file: ${video.filePath} (watched=${video.isWatched}, watchCount=${video.watchCount})');
              }
              await _videoRepository.deleteVideoByPath(video.filePath);
            }
          }
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint('═══ ERROR Deleting Video: ${video.filePath} ═══');
            debugPrint('Error: $e');
            debugPrint('StackTrace: $stackTrace');
          }
        }
      }

      // 清理没有关联视频且未收藏的演员及其本地头像
      await _cleanupOrphanedActors();

      if (kDebugMode) {
        debugPrint('✅ Media Scan Complete');
        debugPrint('Scanned ${mp4Files.length} files');
        debugPrint('═══════════════════════════════');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('═══ FATAL ERROR in Media Scan ═══');
        debugPrint('Error: $e');
        debugPrint('StackTrace: $stackTrace');
        debugPrint('═══════════════════════════════════════');
      }
      rethrow;
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

  Future<bool> _processVideoFileFast(String videoPath, Map<String, Video> videoMap) async {
    try {
      final folderPath = path.dirname(videoPath);
      final nfoPath = path.join(folderPath, 'movie.nfo');

      final existingVideo = videoMap[videoPath];
      final nfoFile = File(nfoPath);
      final hasNfo = await nfoFile.exists();

      if (existingVideo != null) {
        if (!hasNfo || (existingVideo.nfoPath != null && !await File(existingVideo.nfoPath!).exists())) {
          return false;
        }

        if (hasNfo) {
          final nfoModified = await nfoFile.lastModified();
          final dbNfoModified = await File(existingVideo.nfoPath!).lastModified();

          if (!nfoModified.isAfter(dbNfoModified)) {
            return false;
          }
        }
      }

      await _processVideoFile(videoPath, existingVideoOverride: existingVideo);
      return true;
    } catch (e) {
      debugPrint('[Scan] Error processing file $videoPath: $e');
      return false;
    }
  }

  Future<void> _processVideoFile(String videoPath, {Video? existingVideoOverride}) async {
    try {
      final folderPath = path.dirname(videoPath);
      final nfoPath = path.join(folderPath, 'movie.nfo');
      final posterPath = path.join(folderPath, 'poster.jpg');
      final fanartPath = path.join(folderPath, 'fanart.jpg');

      final nfoFile = File(nfoPath);
      Map<String, dynamic>? nfoData;

      if (await nfoFile.exists()) {
        nfoData = await _parseNfoFile(nfoPath);
      }

      final existingVideo = existingVideoOverride ?? await _videoRepository.getVideoByPath(videoPath);

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
        final currentNfoModified = await nfoFile.lastModified();

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
      if (await nfoFile.exists()) {
        nfo = nfoPath;
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
        await _processNfoData(videoId, nfoData, folderPath);
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

  Future<void> _processNfoData(int videoId, Map<String, dynamic> nfoData, String folderPath) async {
    try {
      final actors = nfoData['actors'] as List<Map<String, dynamic>>?;
      if (actors != null) {
        for (final actorData in actors) {
          final actorName = actorData['name'] as String?;
          if (actorName != null && actorName.isNotEmpty) {
            await _actorRepository.insertActorIfNotExists(Actor(name: actorName));
            final actor = await _actorRepository.getActorByName(actorName);
            if (actor != null) {
              await _videoRepository.addActorToVideo(videoId, actor.id!);
            }
          }
        }
      }

      final genres = nfoData['genres'] as List<String>?;
      if (genres != null) {
        for (final genreName in genres) {
          if (genreName.isNotEmpty) {
            await _categoryRepository.insertCategoryIfNotExists(
              Category(type: Category.typeTag, name: genreName),
            );
            final category = await _categoryRepository.getCategoryByNameAndType(genreName, Category.typeTag);
            if (category != null) {
              await _videoRepository.addCategoryToVideo(videoId, category.id!);
            }
          }
        }
      }

      final seriesName = nfoData['set'] as String?;
      if (seriesName != null && seriesName.isNotEmpty) {
        await _categoryRepository.insertCategoryIfNotExists(
          Category(type: Category.typeSeries, name: seriesName),
        );
        final category = await _categoryRepository.getCategoryByNameAndType(seriesName, Category.typeSeries);
        if (category != null) {
          await _videoRepository.addCategoryToVideo(videoId, category.id!);
        }
      }

      final studioName = nfoData['studio'] as String?;
      if (studioName != null && studioName.isNotEmpty) {
        await _categoryRepository.insertCategoryIfNotExists(
          Category(type: Category.typeStudio, name: studioName),
        );
        final category = await _categoryRepository.getCategoryByNameAndType(studioName, Category.typeStudio);
        if (category != null) {
          await _videoRepository.addCategoryToVideo(videoId, category.id!);
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('═══ ERROR Processing NFO Data ═══');
        debugPrint('VideoId: $videoId');
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
      if (await targetEpisodeDir.exists()) {
        await targetEpisodeDir.delete(recursive: true);
        if (kDebugMode) debugPrint('[MoveToWatched] Deleted existing target directory');
      }

      await sourceDir.rename(targetEpisodeDir.path);

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
