import 'dart:io';
import 'package:path/path.dart' as path;

/// Centralized path management for all app data.
/// All data lives under <executable_dir>/jav_manager_data/ to keep
/// everything self-contained in the installation directory.
class AppPaths {
  static String? _rootDir;

  /// Root data directory: <exe_dir>/jav_manager_data/
  static Future<String> get rootDir async {
    _rootDir ??= await _resolveRoot();
    return _rootDir!;
  }

  static Future<String> _resolveRoot() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final dir = Directory(path.join(exeDir, 'jav_manager_data'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  // ---- Subdirectories / files ----

  /// Settings JSON file
  static Future<String> get settingsFile async => path.join(await rootDir, 'settings.json');

  /// SQLite database file
  static Future<String> get databaseFile async => path.join(await rootDir, 'jav_manager.db');

  /// Actor avatars directory
  static Future<String> get avatarsDir async {
    final dir = Directory(path.join(await rootDir, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }
}
