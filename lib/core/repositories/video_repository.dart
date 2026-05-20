import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class VideoRepository {
  Future<Database> get _db => DatabaseHelper.database;

  Future<List<Video>> _fillVideoRelations(List<Video> videos) async {
    if (videos.isEmpty) return videos;

    final db = await _db;
    final videoIds = videos.where((v) => v.id != null).map((v) => v.id!).toList();
    if (videoIds.isEmpty) return videos;

    final placeholders = List.filled(videoIds.length, '?').join(', ');

    final actorMaps = await db.rawQuery('''
      SELECT a.*, va.video_id FROM actors a
      INNER JOIN video_actors va ON a.id = va.actor_id
      WHERE va.video_id IN ($placeholders)
    ''', videoIds);

    final categoryMaps = await db.rawQuery('''
      SELECT c.*, vc.video_id FROM categories c
      INNER JOIN video_categories vc ON c.id = vc.category_id
      WHERE vc.video_id IN ($placeholders)
    ''', videoIds);

    final actorsByVideoId = <int, List<Actor>>{};
    for (final map in actorMaps) {
      final videoId = map['video_id'] as int;
      actorsByVideoId.putIfAbsent(videoId, () => []);
      actorsByVideoId[videoId]!.add(Actor.fromMap(map));
    }

    final categoriesByVideoId = <int, List<Category>>{};
    for (final map in categoryMaps) {
      final videoId = map['video_id'] as int;
      categoriesByVideoId.putIfAbsent(videoId, () => []);
      categoriesByVideoId[videoId]!.add(Category.fromMap(map));
    }

    return videos.map((video) {
      return video.copyWith(
        actors: actorsByVideoId[video.id!] ?? [],
        categories: categoriesByVideoId[video.id!] ?? [],
      );
    }).toList();
  }

  Future<List<Video>> getAllVideos() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      orderBy: 'title ASC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getUnwatchedVideos() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'is_watched = 0 AND watch_count = 0',
      orderBy: 'title ASC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosByFolder(String folderPath) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'folder_path LIKE ?',
      whereArgs: ['$folderPath%'],
      orderBy: 'title ASC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getWatchedVideos() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'is_watched = 1 OR watch_count > 0',
      orderBy: 'last_watched_time DESC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getFavoriteVideos() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'is_favorite = 1',
      orderBy: 'title ASC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosByActor(int actorId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT v.* FROM videos v
      INNER JOIN video_actors va ON v.id = va.video_id
      WHERE va.actor_id = ?
      ORDER BY v.title ASC
    ''', [actorId]);
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosByCategory(int categoryId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT v.* FROM videos v
      INNER JOIN video_categories vc ON v.id = vc.video_id
      WHERE vc.category_id = ?
      ORDER BY v.title ASC
    ''', [categoryId]);
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosByTag(String tag) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT v.* FROM videos v
      INNER JOIN video_categories vc ON v.id = vc.video_id
      INNER JOIN categories c ON vc.category_id = c.id
      WHERE c.type = 'tag' AND c.name = ?
      ORDER BY v.title ASC
    ''', [tag]);
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosBySeries(String series) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT v.* FROM videos v
      INNER JOIN video_categories vc ON v.id = vc.video_id
      INNER JOIN categories c ON vc.category_id = c.id
      WHERE c.type = 'series' AND c.name = ?
      ORDER BY v.title ASC
    ''', [series]);
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getVideosByStudio(String studio) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT v.* FROM videos v
      INNER JOIN video_categories vc ON v.id = vc.video_id
      INNER JOIN categories c ON vc.category_id = c.id
      WHERE c.type = 'studio' AND c.name = ?
      ORDER BY v.title ASC
    ''', [studio]);
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> getRecentlyWatched({int limit = 20}) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'last_watched_time IS NOT NULL',
      orderBy: 'last_watched_time DESC',
      limit: limit,
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<List<Video>> searchVideos(String query) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'title LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'title ASC',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }

  Future<int> insertVideo(Video video) async {
    final db = await _db;
    return await db.insert(
      'videos',
      video.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateVideo(Video video) async {
    final db = await _db;
    await db.update(
      'videos',
      video.toMap(),
      where: 'id = ?',
      whereArgs: [video.id],
    );
  }

  Future<void> updateVideoPaths(int id, {
    String? filePath,
    String? folderPath,
    String? posterPath,
    String? fanartPath,
    String? nfoPath,
  }) async {
    final db = await _db;
    final updates = <String, dynamic>{};
    if (filePath != null) updates['file_path'] = filePath;
    if (folderPath != null) updates['folder_path'] = folderPath;
    if (posterPath != null) updates['poster_path'] = posterPath;
    if (fanartPath != null) updates['fanart_path'] = fanartPath;
    if (nfoPath != null) updates['nfo_path'] = nfoPath;
    if (updates.isEmpty) return;
    await db.update('videos', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteVideo(int id) async {
    final db = await _db;
    await db.delete(
      'videos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteVideoByPath(String filePath) async {
    final db = await _db;
    await db.delete(
      'videos',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  Future<void> incrementWatchCount(int id) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE videos 
      SET watch_count = watch_count + 1,
          last_watched_time = ?,
          is_watched = 1
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'videos',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resetWatchStatus(int id) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE videos
      SET watch_count = 0,
          last_watched_time = NULL,
          is_watched = 0
      WHERE id = ?
    ''', [id]);
  }

  Future<Video?> getVideoById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final video = Video.fromMap(maps.first);
    final actors = await getVideoActors(video.id!);
    final categories = await getVideoCategories(video.id!);
    return video.copyWith(actors: actors, categories: categories);
  }

  Future<Video?> getVideoByPath(String filePath) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    if (maps.isEmpty) return null;
    final video = Video.fromMap(maps.first);
    final actors = await getVideoActors(video.id!);
    final categories = await getVideoCategories(video.id!);
    return video.copyWith(actors: actors, categories: categories);
  }

  Future<List<Actor>> getVideoActors(int videoId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.* FROM actors a
      INNER JOIN video_actors va ON a.id = va.actor_id
      WHERE va.video_id = ?
    ''', [videoId]);
    return maps.map((map) => Actor.fromMap(map)).toList();
  }

  Future<List<Category>> getVideoCategories(int videoId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.* FROM categories c
      INNER JOIN video_categories vc ON c.id = vc.category_id
      WHERE vc.video_id = ?
    ''', [videoId]);
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<void> addActorToVideo(int videoId, int actorId) async {
    final db = await _db;
    await db.insert(
      'video_actors',
      {'video_id': videoId, 'actor_id': actorId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addCategoryToVideo(int videoId, int categoryId) async {
    final db = await _db;
    await db.insert(
      'video_categories',
      {'video_id': videoId, 'category_id': categoryId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Video>> getVideosWithWatchCountGreaterThanZero() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: 'watch_count > 0',
    );
    final videos = maps.map((map) => Video.fromMap(map)).toList();
    return _fillVideoRelations(videos);
  }
}
