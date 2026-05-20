import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static Database? _database;
  static const String _databaseName = 'jav_manager.db';
  static const int _databaseVersion = 2;

  static Future<String> getAppDir() async {
    return File(Platform.resolvedExecutable).parent.path;
  }

  static Future<String> getDatabasePath() async {
    final appDir = await getAppDir();
    return join(appDir, _databaseName);
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final appDir = await getAppDir();
    final path = join(appDir, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT UNIQUE NOT NULL,
        folder_path TEXT NOT NULL,
        title TEXT,
        plot TEXT,
        poster_path TEXT,
        fanart_path TEXT,
        nfo_path TEXT,
        watch_count INTEGER DEFAULT 0,
        last_watched_time DATETIME,
        is_favorite INTEGER DEFAULT 0,
        is_watched INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE actors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        avatar_url TEXT,
        is_favorite INTEGER DEFAULT 0,
        info_json TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE video_actors (
        video_id INTEGER NOT NULL,
        actor_id INTEGER NOT NULL,
        PRIMARY KEY (video_id, actor_id),
        FOREIGN KEY (video_id) REFERENCES videos (id) ON DELETE CASCADE,
        FOREIGN KEY (actor_id) REFERENCES actors (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        name_traditional TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(type, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE video_categories (
        video_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        PRIMARY KEY (video_id, category_id),
        FOREIGN KEY (video_id) REFERENCES videos (id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_videos_title ON videos(title)
    ''');

    await db.execute('''
      CREATE INDEX idx_videos_watch_count ON videos(watch_count)
    ''');

    await db.execute('''
      CREATE INDEX idx_videos_last_watched ON videos(last_watched_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_actors_name ON actors(name)
    ''');

    await db.execute('''
      CREATE INDEX idx_categories_type ON categories(type)
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE videos ADD COLUMN plot TEXT');
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
