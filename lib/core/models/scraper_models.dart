import 'dart:convert';

/// 刮削状态枚举
enum ScrapeStatus {
  pending,    // 待刮削
  scraping,   // 刮削中
  success,    // 刮削成功
  failed,     // 刮削失败
  completed,  // 全部完成
}

/// 刮削任务整体状态
enum ScrapingTaskState {
  idle,       // 空闲
  scanning,   // 扫描中
  running,    // 运行中
  stopping,   // 停止中
}

/// 刮削配置
class ScraperConfig {
  final String scanDir;                  // 扫描目录
  final List<String> ignoreFolders;      // 忽略的文件夹列表
  final String? javdbCookie;             // JavDB Cookie（可选）
  final bool translateTitle;             // 是否翻译标题
  final bool translatePlot;              // 是否翻译剧情简介
  final int maxWorkers;                  // 最大线程数
  final bool useProxy;                   // 是否使用代理
  final String proxyUrl;                 // 代理地址

  const ScraperConfig({
    this.scanDir = '',
    this.ignoreFolders = const [],
    this.javdbCookie,
    this.translateTitle = true,
    this.translatePlot = true,
    this.maxWorkers = 4,
    this.useProxy = false,
    this.proxyUrl = '',
  });

  factory ScraperConfig.fromJson(Map<String, dynamic> json) {
    return ScraperConfig(
      scanDir: json['scan_dir'] ?? '',
      ignoreFolders: (json['ignore_folders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      javdbCookie: json['javdb_cookie'],
      translateTitle: json['translate_title'] ?? true,
      translatePlot: json['translate_plot'] ?? true,
      maxWorkers: json['max_workers'] ?? 4,
      useProxy: json['use_proxy'] ?? false,
      proxyUrl: json['proxy_url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'scan_dir': scanDir,
        'ignore_folders': ignoreFolders,
        'javdb_cookie': javdbCookie,
        'translate_title': translateTitle,
        'translate_plot': translatePlot,
        'max_workers': maxWorkers,
        'use_proxy': useProxy,
        'proxy_url': proxyUrl,
      };

  /// 转换为 Python 端期望的完整配置格式（包含网络、爬虫等子配置）
  Map<String, dynamic> toPythonConfig() {
    // 防御热重载导致的字段未初始化问题（新增字段后旧实例无此字段）
    bool safeUseProxy;
    String safeProxyUrl;
    try {
      safeUseProxy = useProxy;
      safeProxyUrl = proxyUrl;
    } catch (_) {
      safeUseProxy = false;
      safeProxyUrl = '';
    }
    return {
        'network': {
          'use_proxy': safeUseProxy,
          'proxy': safeProxyUrl,
          'retry': 3,
          'timeout': 10,
        },
        'crawler': {
          'required_keys': 'cover,title',
          'javdb_cookie': javdbCookie ?? '',
          'hardworking_mode': true,
          'respect_site_avid': true,
          'title_remove_actor': true,
          'title_chinese_first': true,
          'sleep_after_scraping': 1,
          'ignore_javdb_cover': 'auto',
          'unify_actress_name': true,
        },
        'translate': {
          'engine': 'google',
          'translate_title': translateTitle,
          'translate_plot': translatePlot,
        },
        'file_config': {
          'scan_dir': scanDir,
          'media_ext':
              '3gp;avi;f4v;flv;iso;m2ts;m4v;mkv;mov;mp4;mpeg;rm;rmvb;ts;vob;webm;wmv;strm;mpg',
          'ignore_folder': ignoreFolders.join(';'),
          'ignore_video_file_less_than': 232,
          'enable_file_move': false,
        },
        'crawler_select': {
          'normal': ['javbus', 'jav321', 'javdb'],
          'fc2': ['fc2', 'javmenu', 'fc2ppvdb', 'javdb'],
          'cid': ['fanza'],
          'getchu': ['dl_getchu'],
          'gyutto': ['gyutto'],
        },
        'max_workers': maxWorkers,
      };
  }

  ScraperConfig copyWith({
    String? scanDir,
    List<String>? ignoreFolders,
    String? javdbCookie,
    bool? translateTitle,
    bool? translatePlot,
    int? maxWorkers,
    bool? useProxy,
    String? proxyUrl,
    bool clearJavdbCookie = false,
  }) {
    return ScraperConfig(
      scanDir: scanDir ?? this.scanDir,
      ignoreFolders: ignoreFolders ?? this.ignoreFolders,
      javdbCookie: clearJavdbCookie ? null : (javdbCookie ?? this.javdbCookie),
      translateTitle: translateTitle ?? this.translateTitle,
      translatePlot: translatePlot ?? this.translatePlot,
      maxWorkers: maxWorkers ?? this.maxWorkers,
      useProxy: useProxy ?? this.useProxy,
      proxyUrl: proxyUrl ?? this.proxyUrl,
    );
  }
}

/// 待刮削影片信息
class ScrapableMovie {
  final String id;                        // 唯一标识
  final String avid;                      // 番号
  final String movieType;                 // 影片类型: normal/fc2/cid/getchu/gyutto
  final String filePath;                  // 文件路径
  ScrapeStatus status;                    // 当前状态
  double progress;                        // 进度 (0.0 - 1.0)
  String? crawlerName;                    // 当前使用的爬虫名称
  MovieInfo? info;                        // 已获取的信息（成功时）
  String? errorMessage;                   // 错误消息（失败时）

  ScrapableMovie({
    required this.id,
    required this.avid,
    required this.movieType,
    required this.filePath,
    this.status = ScrapeStatus.pending,
    this.progress = 0.0,
    this.crawlerName,
    this.info,
    this.errorMessage,
  });

  factory ScrapableMovie.fromJson(Map<String, dynamic> json) {
    return ScrapableMovie(
      id: json['id'].toString(),
      avid: json['avid'] ?? '',
      movieType: json['movie_type'] ?? 'normal',
      filePath: json['file_path'] ?? '',
      status: _parseStatus(json['status']),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      crawlerName: json['crawler_name'],
      info: json['info'] != null ? MovieInfo.fromJson(json['info']) : null,
      errorMessage: json['error'],
    );
  }

  static ScrapeStatus _parseStatus(dynamic status) {
    switch (status?.toString()) {
      case 'scraping':
        return ScrapeStatus.scraping;
      case 'success':
        return ScrapeStatus.success;
      case 'failed':
        return ScrapeStatus.failed;
      case 'completed':
        return ScrapeStatus.completed;
      default:
        return ScrapeStatus.pending;
    }
  }

  ScrapableMovie copyWith({
    ScrapeStatus? status,
    double? progress,
    String? crawlerName,
    MovieInfo? info,
    String? errorMessage,
  }) {
    return ScrapableMovie(
      id: id,
      avid: avid,
      movieType: movieType,
      filePath: filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      crawlerName: crawlerName ?? this.crawlerName,
      info: info ?? this.info,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 影片详细信息（从爬虫获取）
class MovieInfo {
  final String? dvdid;
  final String? cid;
  final String? title;
  final String? oriTitle;
  final String? plot;
  final String? cover;
  final String? bigCover;
  final List<String> genre;
  final List<String> actress;
  final String? director;
  final int? duration;
  final String? publisher;
  final String? publishDate;
  final double? score;

  const MovieInfo({
    this.dvdid,
    this.cid,
    this.title,
    this.oriTitle,
    this.plot,
    this.cover,
    this.bigCover,
    this.genre = const [],
    this.actress = const [],
    this.director,
    this.duration,
    this.publisher,
    this.publishDate,
    this.score,
  });

  factory MovieInfo.fromJson(Map<String, dynamic> json) {
    return MovieInfo(
      dvdid: json['dvdid'],
      cid: json['cid'],
      title: json['title'],
      oriTitle: json['ori_title'],
      plot: json['plot'],
      cover: json['cover'],
      bigCover: json['big_cover'],
      genre: (json['genre'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      actress: (json['actress'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      director: json['director'],
      duration: json['duration'] != null ? int.tryParse(json['duration'].toString()) : null,
      publisher: json['publisher'],
      publishDate: json['publish_date'],
      score: (json['score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'dvdid': dvdid,
        'cid': cid,
        'title': title,
        'ori_title': oriTitle,
        'plot': plot,
        'cover': cover,
        'big_cover': bigCover,
        'genre': genre,
        'actress': actress,
        'director': director,
        'duration': duration,
        'publisher': publisher,
        'publish_date': publishDate,
        'score': score,
      };
}

/// 刮削进度事件
class ScrapeProgress {
  final String movieId;
  final String avid;
  final ScrapeStatus status;
  final double progress;
  final String? crawlerName;
  final MovieInfo? info;
  final String? error;

  const ScrapeProgress({
    required this.movieId,
    required this.avid,
    required this.status,
    this.progress = 0.0,
    this.crawlerName,
    this.info,
    this.error,
  });

  factory ScrapeProgress.fromJson(Map<String, dynamic> json) {
    return ScrapeProgress(
      movieId: json['movie_id'] ?? '',
      avid: json['avid'] ?? '',
      status: ScrapableMovie._parseStatus(json['status']),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      crawlerName: json['crawler_name'],
      info: json['info'] != null ? MovieInfo.fromJson(json['info']) : null,
      error: json['error'],
    );
  }
}

/// 刮削统计信息
class ScrapeStats {
  final int total;
  final int pending;
  final int scraping;
  final int success;
  final int failed;

  const ScrapeStats({
    this.total = 0,
    this.pending = 0,
    this.scraping = 0,
    this.success = 0,
    this.failed = 0,
  });

  factory ScrapeStats.fromList(List<ScrapableMovie> movies) {
    int pending = 0, scraping = 0, success = 0, failed = 0;
    for (var movie in movies) {
      switch (movie.status) {
        case ScrapeStatus.pending:
          pending++;
          break;
        case ScrapeStatus.scraping:
          scraping++;
          break;
        case ScrapeStatus.success:
          success++;
          break;
        case ScrapeStatus.failed:
          failed++;
          break;
        case ScrapeStatus.completed:
          break;
      }
    }
    return ScrapeStats(
      total: movies.length,
      pending: pending,
      scraping: scraping,
      success: success,
      failed: failed,
    );
  }

  ScrapeStats copyWith({
    int? total,
    int? pending,
    int? scraping,
    int? success,
    int? failed,
  }) {
    return ScrapeStats(
      total: total ?? this.total,
      pending: pending ?? this.pending,
      scraping: scraping ?? this.scraping,
      success: success ?? this.success,
      failed: failed ?? this.failed,
    );
  }

  int get completed => success + failed;
  double get successRate =>
      total > 0 ? (success / total * 100) : 0;
}
