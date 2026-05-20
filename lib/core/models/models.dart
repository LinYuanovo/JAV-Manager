import 'dart:convert';

enum ViewMode {
  poster,
  posterWithTitle,
  posterWall,
  list,
}

enum SortMode {
  titleAsc,
  titleDesc,
  recentlyWatchedAsc,
  recentlyWatchedDesc,
  random,
}

class Video {
  final int? id;
  final String filePath;
  final String folderPath;
  final String? title;
  final String? plot;
  final String? posterPath;
  final String? fanartPath;
  final String? nfoPath;
  final int watchCount;
  final DateTime? lastWatchedTime;
  final bool isFavorite;
  final bool isWatched;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Actor> actors;
  final List<Category> categories;

  Video({
    this.id,
    required this.filePath,
    required this.folderPath,
    this.title,
    this.plot,
    this.posterPath,
    this.fanartPath,
    this.nfoPath,
    this.watchCount = 0,
    this.lastWatchedTime,
    this.isFavorite = false,
    this.isWatched = false,
    this.createdAt,
    this.updatedAt,
    this.actors = const [],
    this.categories = const [],
  });

  factory Video.fromMap(Map<String, dynamic> map) {
    return Video(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      folderPath: map['folder_path'] as String,
      title: map['title'] as String?,
      plot: map['plot'] as String?,
      posterPath: map['poster_path'] as String?,
      fanartPath: map['fanart_path'] as String?,
      nfoPath: map['nfo_path'] as String?,
      watchCount: map['watch_count'] as int? ?? 0,
      lastWatchedTime: map['last_watched_time'] != null
          ? DateTime.parse(map['last_watched_time'] as String)
          : null,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isWatched: (map['is_watched'] as int? ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'folder_path': folderPath,
      'title': title,
      'plot': plot,
      'poster_path': posterPath,
      'fanart_path': fanartPath,
      'nfo_path': nfoPath,
      'watch_count': watchCount,
      'last_watched_time': lastWatchedTime?.toIso8601String(),
      'is_favorite': isFavorite ? 1 : 0,
      'is_watched': isWatched ? 1 : 0,
    };
  }

  Video copyWith({
    int? id,
    String? filePath,
    String? folderPath,
    String? title,
    String? plot,
    String? posterPath,
    String? fanartPath,
    String? nfoPath,
    int? watchCount,
    DateTime? lastWatchedTime,
    bool? isFavorite,
    bool? isWatched,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Actor>? actors,
    List<Category>? categories,
  }) {
    return Video(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      folderPath: folderPath ?? this.folderPath,
      title: title ?? this.title,
      plot: plot ?? this.plot,
      posterPath: posterPath ?? this.posterPath,
      fanartPath: fanartPath ?? this.fanartPath,
      nfoPath: nfoPath ?? this.nfoPath,
      watchCount: watchCount ?? this.watchCount,
      lastWatchedTime: lastWatchedTime ?? this.lastWatchedTime,
      isFavorite: isFavorite ?? this.isFavorite,
      isWatched: isWatched ?? this.isWatched,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      actors: actors ?? this.actors,
      categories: categories ?? this.categories,
    );
  }
}

class Actor {
  final int? id;
  final String name;
  final String? avatarUrl;
  final bool isFavorite;
  final Map<String, dynamic>? infoJson;
  final DateTime? createdAt;
  final int videoCount;

  Actor({
    this.id,
    required this.name,
    this.avatarUrl,
    this.isFavorite = false,
    this.infoJson,
    this.createdAt,
    this.videoCount = 0,
  });

  factory Actor.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parsedInfo;
    final infoRaw = map['info_json'] as String?;
    if (infoRaw != null && infoRaw.isNotEmpty) {
      try {
        parsedInfo = Map<String, dynamic>.from(jsonDecode(infoRaw));
      } catch (_) {
        // Legacy format: try custom parser
        try {
          parsedInfo = _parseLegacyInfoJson(infoRaw);
        } catch (_) {
          parsedInfo = null;
        }
      }
    }

    return Actor(
      id: map['id'] as int?,
      name: map['name'] as String,
      avatarUrl: map['avatar_url'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      infoJson: parsedInfo,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      videoCount: map['video_count'] as int? ?? 0,
    );
  }

  /// Parse legacy custom-format info_json (not standard JSON).
  /// Only used for backwards compatibility during migration.
  static Map<String, dynamic> _parseLegacyInfoJson(String json) {
    final result = <String, dynamic>{};
    if (json.isEmpty || json == '{}') return result;
    final content = json.substring(1, json.length - 1);
    if (content.isEmpty) return result;

    final pairs = <String>[];
    var depth = 0;
    var current = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '{' || char == '[') depth++;
      if (char == '}' || char == ']') depth--;
      if (char == ',' && depth == 0) {
        pairs.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) pairs.add(current.toString());

    for (final pair in pairs) {
      final colonIndex = pair.indexOf(':');
      if (colonIndex == -1) continue;
      var key = pair.substring(0, colonIndex).trim();
      var value = pair.substring(colonIndex + 1).trim();
      key = _unquote(key);
      value = _unquote(value);
      if (value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static String _unquote(String s) {
    if (s.isEmpty) return s;
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'is_favorite': isFavorite ? 1 : 0,
      'info_json': infoJson != null ? jsonEncode(infoJson) : null,
    };
  }

  Actor copyWith({
    int? id,
    String? name,
    String? avatarUrl,
    bool? isFavorite,
    Map<String, dynamic>? infoJson,
    DateTime? createdAt,
    int? videoCount,
  }) {
    return Actor(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isFavorite: isFavorite ?? this.isFavorite,
      infoJson: infoJson ?? this.infoJson,
      createdAt: createdAt ?? this.createdAt,
      videoCount: videoCount ?? this.videoCount,
    );
  }

  String? get birthDate => infoJson?['birthDate'];
  String? get height => infoJson?['height'];
  String? get weight => infoJson?['weight'];
  String? get bust => infoJson?['bust'];
  String? get waist => infoJson?['waist'];
  String? get hip => infoJson?['hip'];
  String? get cupSize => infoJson?['cupSize'];
}

class Category {
  final int? id;
  final String type;
  final String name;
  final String? nameTraditional;
  final bool isFavorite;
  final DateTime? createdAt;
  final int videoCount;
  final bool hasVideos;

  Category({
    this.id,
    required this.type,
    required this.name,
    this.nameTraditional,
    this.isFavorite = false,
    this.createdAt,
    this.videoCount = 0,
    this.hasVideos = true,
  });

  static const String typeTag = 'tag';
  static const String typeSeries = 'series';
  static const String typeStudio = 'studio';

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      type: map['type'] as String,
      name: map['name'] as String,
      nameTraditional: map['name_traditional'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      videoCount: map['video_count'] as int? ?? 0,
      hasVideos: (map['has_videos'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'name': name,
      'name_traditional': nameTraditional,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  Category copyWith({
    int? id,
    String? type,
    String? name,
    String? nameTraditional,
    bool? isFavorite,
    DateTime? createdAt,
    int? videoCount,
    bool? hasVideos,
  }) {
    return Category(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      nameTraditional: nameTraditional ?? this.nameTraditional,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      videoCount: videoCount ?? this.videoCount,
      hasVideos: hasVideos ?? this.hasVideos,
    );
  }
}
