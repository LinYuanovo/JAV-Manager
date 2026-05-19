import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class ActorRepository {
  Future<Database> get _db => DatabaseHelper.database;

  Future<List<Actor>> getAllActors() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, COUNT(v.id) as video_count
      FROM actors a
      LEFT JOIN video_actors va ON a.id = va.actor_id
      LEFT JOIN videos v ON va.video_id = v.id
      GROUP BY a.id
      ORDER BY a.name ASC
    ''');
    return maps.map((map) => Actor.fromMap(map)).toList();
  }

  Future<List<Actor>> getFavoriteActors() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, COUNT(v.id) as video_count
      FROM actors a
      LEFT JOIN video_actors va ON a.id = va.actor_id
      LEFT JOIN videos v ON va.video_id = v.id
      WHERE a.is_favorite = 1
      GROUP BY a.id
      ORDER BY a.name ASC
    ''');
    return maps.map((map) => Actor.fromMap(map)).toList();
  }

  Future<List<Actor>> getActorsSortedByVideoCount({bool descending = true}) async {
    final db = await _db;
    final order = descending ? 'DESC' : 'ASC';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, COUNT(v.id) as video_count
      FROM actors a
      LEFT JOIN video_actors va ON a.id = va.actor_id
      LEFT JOIN videos v ON va.video_id = v.id
      GROUP BY a.id
      ORDER BY video_count $order
    ''');
    return maps.map((map) => Actor.fromMap(map)).toList();
  }

  Future<Actor?> getActorById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, COUNT(v.id) as video_count
      FROM actors a
      LEFT JOIN video_actors va ON a.id = va.actor_id
      LEFT JOIN videos v ON va.video_id = v.id
      WHERE a.id = ?
      GROUP BY a.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return Actor.fromMap(maps.first);
  }

  Future<Actor?> getActorByName(String name) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, COUNT(v.id) as video_count
      FROM actors a
      LEFT JOIN video_actors va ON a.id = va.actor_id
      LEFT JOIN videos v ON va.video_id = v.id
      WHERE a.name = ?
      GROUP BY a.id
    ''', [name]);
    if (maps.isEmpty) return null;
    return Actor.fromMap(maps.first);
  }

  Future<int> insertActor(Actor actor) async {
    final db = await _db;
    return await db.insert(
      'actors',
      actor.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertActorIfNotExists(Actor actor) async {
    final existing = await getActorByName(actor.name ?? '');
    if (existing != null) return existing.id!;
    return await insertActor(actor);
  }

  Future<void> updateActor(Actor actor) async {
    final db = await _db;
    await db.update(
      'actors',
      actor.toMap(),
      where: 'id = ?',
      whereArgs: [actor.id],
    );
  }

  Future<void> deleteActor(int id) async {
    final db = await _db;
    await db.delete(
      'actors',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'actors',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateActorInfo(int id, Map<String, dynamic> infoJson) async {
    final db = await _db;
    // Merge with existing info to avoid losing previously fetched fields
    final existing = await getActorById(id);
    Map<String, dynamic> merged = {};
    if (existing?.infoJson != null && existing!.infoJson!.isNotEmpty) {
      merged.addAll(existing.infoJson!);
    }
    // New values override old ones
    for (final entry in infoJson.entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty) {
        merged[entry.key] = entry.value;
      }
    }
    final jsonString = _mapToJson(merged);
    await db.update(
      'actors',
      {'info_json': jsonString},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateActorAvatar(int id, String avatarUrl) async {
    final db = await _db;
    await db.update(
      'actors',
      {'avatar_url': avatarUrl},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  String _mapToJson(Map<String, dynamic> map) {
    final entries = map.entries
        .map((e) => '"${e.key}":"${e.value}"')
        .join(',');
    return '{$entries}';
  }
}
