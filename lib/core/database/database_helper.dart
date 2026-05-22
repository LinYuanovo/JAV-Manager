import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/app_paths.dart';

class DatabaseHelper {
  static Database? _database;
  static Future<Database>? _databaseFuture;
  static const int _databaseVersion = 3;

  /// Returns the root data directory where all app data is stored.
  static Future<String> getDataDir() => AppPaths.rootDir;

  static Future<String> getDatabasePath() => AppPaths.databaseFile;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    return _databaseFuture ??= _initDatabase();
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasePath();

    final db = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    // 安全检查：确保 ignored_codes 表存在（防止升级中断导致表缺失）
    await _ensureTableExists(db, 'ignored_codes', '''
      CREATE TABLE ignored_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        title TEXT,
        folder_path TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''', indexSql: 'CREATE INDEX IF NOT EXISTS idx_ignored_codes_code ON ignored_codes(code)');

    _database = db;
    return db;
  }

  static Future<void> _ensureTableExists(Database db, String tableName, String createSql, {String? indexSql}) async {
    final result = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tableName]);
    if (result.isEmpty) {
      await db.execute(createSql);
      if (indexSql != null) await db.execute(indexSql);
    }
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
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE ignored_codes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          title TEXT,
          folder_path TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_ignored_codes_code ON ignored_codes(code)
      ''');
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _databaseFuture = null;
    }
  }
}
