import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class CategoryRepository {
  Future<Database> get _db => DatabaseHelper.database;

  Future<List<Category>> getAllCategories() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      GROUP BY c.id
      ORDER BY c.name ASC
    ''');
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<List<Category>> getCategoriesByType(String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.type = ?
      GROUP BY c.id
      ORDER BY c.is_favorite DESC, c.name ASC
    ''', [type]);
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<List<Category>> getFavoriteCategories() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.is_favorite = 1
      GROUP BY c.id
      ORDER BY c.name ASC
    ''');
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<List<Category>> getFavoriteTags() async {
    return getFavoriteCategoriesByType(Category.typeTag);
  }

  Future<List<Category>> getFavoriteSeries() async {
    return getFavoriteCategoriesByType(Category.typeSeries);
  }

  Future<List<Category>> getFavoriteStudios() async {
    return getFavoriteCategoriesByType(Category.typeStudio);
  }

  Future<List<Category>> getFavoriteCategoriesByType(String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.type = ? AND c.is_favorite = 1
      GROUP BY c.id
      ORDER BY c.name ASC
    ''', [type]);
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<Category?> getCategoryById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.id = ?
      GROUP BY c.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return Category.fromMap(maps.first);
  }

  Future<Category?> getCategoryByNameAndType(String name, String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.name = ? AND c.type = ?
      GROUP BY c.id
    ''', [name, type]);
    if (maps.isEmpty) return null;
    return Category.fromMap(maps.first);
  }

  Future<Category?> getCategoryByName(String name) async {
    return getCategoryByNameAndType(name, Category.typeTag);
  }

  Future<int> insertCategory(Category category) async {
    final db = await _db;
    return await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertOrGetCategory(String name, String type, {String? nameTraditional}) async {
    final existing = await getCategoryByNameAndType(name, type);
    if (existing != null) return existing.id!;

    final db = await _db;
    return await db.insert(
      'categories',
      {
        'type': type,
        'name': name,
        'name_traditional': nameTraditional,
        'is_favorite': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertCategoryIfNotExists(Category category) async {
    final existing = await getCategoryByNameAndType(category.name, category.type);
    if (existing != null) return existing.id!;
    return await insertCategory(category);
  }

  Future<void> updateCategory(Category category) async {
    final db = await _db;
    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteCategory(int id) async {
    final db = await _db;
    await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'categories',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Category>> searchCategories(String query, String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(v.id) as video_count,
             CASE WHEN COUNT(v.id) > 0 THEN 1 ELSE 0 END as has_videos
      FROM categories c
      LEFT JOIN video_categories vc ON c.id = vc.category_id
      LEFT JOIN videos v ON vc.video_id = v.id AND v.is_watched = 0
      WHERE c.type = ? AND c.name LIKE ?
      GROUP BY c.id
      ORDER BY c.name ASC
    ''', [type, '%$query%']);
    return maps.map((map) => Category.fromMap(map)).toList();
  }
}
