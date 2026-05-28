import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_settings.dart';
import '../utils/proxy_client.dart';
import '../repositories/video_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/category_repository.dart';
import '../services/media_scanner_service.dart';
import '../services/wikipedia_service.dart';
import '../services/auto_task_service.dart';
import '../services/avatar_service.dart';
import '../services/webdav_service.dart';
import '../services/scraper_service.dart';
import '../services/media_count_service.dart';
import '../services/task_event_listener.dart';
import '../services/smart_sort_service.dart';
import '../models/models.dart';
import '../models/scraper_models.dart';

final sharedPreferencesProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('AppSettings not initialized');
});

final videoRepositoryProvider = Provider<VideoRepository>((ref) {
  return VideoRepository();
});

final actorRepositoryProvider = Provider<ActorRepository>((ref) {
  return ActorRepository();
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository();
});

final mediaScannerServiceProvider = Provider<MediaScannerService>((ref) {
  final service = MediaScannerService(
    videoRepository: ref.watch(videoRepositoryProvider),
    actorRepository: ref.watch(actorRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
  );
  // 全局回调：扫描过程中实时刷新所有相关 Provider，不依赖任何页面生命周期
  service.onVideoProcessed = () {
    ref.invalidate(allVideosProvider);
    ref.invalidate(watchedVideosProvider);
    ref.invalidate(favoriteVideosProvider);
    ref.invalidate(allActorsProvider);
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
    ref.invalidate(allStudiosProvider);
  };
  // 进度回调
  service.onProgress = (processed, total) {
    ref.read(scanProcessedProvider.notifier).state = processed;
    ref.read(scanTotalProvider.notifier).state = total;
  };
  // 取消检查回调
  service.shouldCancel = () => ref.read(scanCancelProvider);
  return service;
});

final wikipediaServiceProvider = Provider<WikipediaService>((ref) {
  return WikipediaService();
});

final autoTaskServiceProvider = Provider<AutoTaskService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final mediaScannerService = ref.watch(mediaScannerServiceProvider);
  return AutoTaskService(
    prefs: prefs,
    mediaScannerService: mediaScannerService,
  );
});

final avatarServiceProvider = Provider<AvatarService>((ref) {
  return AvatarService(
    actorRepository: ref.watch(actorRepositoryProvider),
  );
});

final webdavServiceProvider = Provider<WebdavService>((ref) {
  return WebdavService();
});

final allVideosProvider = FutureProvider<List<Video>>((ref) async {
  if (kDebugMode) {
    debugPrint('📦 Loading all videos...');
  }
  try {
    final repository = ref.watch(videoRepositoryProvider);
    final allVideos = await repository.getAllVideos();
    final result = allVideos.where((v) => !v.isWatched).toList();
    if (kDebugMode) {
      debugPrint('✅ Loaded ${result.length} videos (filtered watched)');
    }
    return result;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Videos ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      debugPrint('═══════════════════════════════');
    }
    rethrow;
  }
});

final mediaCountStateProvider = StateProvider<int>((ref) => 0);

final mediaCountServiceProvider = Provider<MediaCountService>((ref) {
  return MediaCountService(ref);
});

final taskEventListenerProvider = Provider<TaskEventListener>((ref) {
  return TaskEventListener(ref);
});

final fontSizeProvider = StateProvider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getDouble('font_size') ?? 14.0;
});

final enableGridAnimationProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('enable_grid_animation') ?? true;
});

final pureModeProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('pure_mode_enabled') ?? false;
});

final watchedVideosProvider = FutureProvider<List<Video>>((ref) async {
  if (kDebugMode) {
    debugPrint('📺 Loading watched videos...');
  }
  try {
    final repository = ref.watch(videoRepositoryProvider);
    final result = await repository.getWatchedVideos();
    if (kDebugMode) {
      debugPrint('✅ Loaded ${result.length} watched videos');
    }
    return result;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Watched Videos ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final favoriteVideosProvider = FutureProvider<List<Video>>((ref) async {
  if (kDebugMode) {
    debugPrint('❤️ Loading favorite videos...');
  }
  try {
    final repository = ref.watch(videoRepositoryProvider);
    final result = await repository.getFavoriteVideos();
    if (kDebugMode) {
      debugPrint('✅ Loaded ${result.length} favorite videos');
    }
    return result;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Favorite Videos ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final recentlyWatchedVideosProvider = FutureProvider<List<Video>>((ref) async {
  try {
    final repository = ref.watch(videoRepositoryProvider);
    return await repository.getRecentlyWatched();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Recently Watched ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final allActorsProvider = FutureProvider<List<Actor>>((ref) async {
  if (kDebugMode) {
    debugPrint('👤 Loading all actors...');
  }
  try {
    final repository = ref.watch(actorRepositoryProvider);
    final actors = await repository.getAllActors();
    // 过滤掉没有未观看视频且未收藏的演员
    final result = actors.where((a) => a.videoCount > 0 || a.isFavorite).toList();
    if (kDebugMode) {
      debugPrint('✅ Loaded ${result.length} actors (filtered ${actors.length - result.length} orphaned)');
    }
    return result;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Actors ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final favoriteActorsProvider = FutureProvider<List<Actor>>((ref) async {
  try {
    final repository = ref.watch(actorRepositoryProvider);
    return await repository.getFavoriteActors();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Favorite Actors ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final allTagsProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final repository = ref.watch(categoryRepositoryProvider);
    return await repository.getCategoriesByType(Category.typeTag);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Tags ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final allSeriesProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final repository = ref.watch(categoryRepositoryProvider);
    return await repository.getCategoriesByType(Category.typeSeries);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Series ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final allStudiosProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final repository = ref.watch(categoryRepositoryProvider);
    return await repository.getCategoriesByType(Category.typeStudio);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Studios ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final favoriteCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final repository = ref.watch(categoryRepositoryProvider);
    return await repository.getFavoriteCategories();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Favorite Categories ═══');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final videosByActorProvider = FutureProvider.family<List<Video>, int>((ref, actorId) async {
  try {
    final repository = ref.watch(videoRepositoryProvider);
    return await repository.getVideosByActor(actorId);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Videos By Actor ═══');
      debugPrint('ActorId: $actorId');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final videosByCategoryProvider = FutureProvider.family<List<Video>, int>((ref, categoryId) async {
  try {
    final repository = ref.watch(videoRepositoryProvider);
    return await repository.getVideosByCategory(categoryId);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Videos By Category ═══');
      debugPrint('CategoryId: $categoryId');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final actorDetailProvider = FutureProvider.family<Actor?, int>((ref, actorId) async {
  try {
    final repository = ref.watch(actorRepositoryProvider);
    return await repository.getActorById(actorId);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Loading Actor Detail ═══');
      debugPrint('ActorId: $actorId');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final searchVideosProvider = FutureProvider.family<List<Video>, String>((ref, query) async {
  try {
    final repository = ref.watch(videoRepositoryProvider);
    return await repository.searchVideos(query);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('═══ ERROR Searching Videos ═══');
      debugPrint('Query: $query');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }
    rethrow;
  }
});

final selectedNavIndexProvider = StateProvider<int>((ref) {
  if (kDebugMode) {
    debugPrint('📍 Navigation index changed to: 0');
  }
  return 0;
});

final viewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('view_mode') ?? 0;
  return ViewMode.values[index.clamp(0, ViewMode.values.length - 1)];
});

final sortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('sort_mode') ?? 0;
  return SortMode.values[index.clamp(0, SortMode.values.length - 1)];
});

final favoriteSortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('favorite_sort_mode') ?? 0;
  return SortMode.values[index.clamp(0, SortMode.values.length - 1)];
});

final favoriteViewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('favorite_view_mode') ?? 0;
  return ViewMode.values[index.clamp(0, ViewMode.values.length - 1)];
});

final isFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('media_is_fixed_column') ?? false;
});

final fixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('media_fixed_column_count') ?? 4;
});

final favoriteFixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('favorite_fixed_column_count') ?? 0; // 0 means auto
});

final favoriteIsFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('favorite_is_fixed_column') ?? false;
});

final isScanningProvider = StateProvider<bool>((ref) => false);

/// 扫描进度：已处理数
final scanProcessedProvider = StateProvider<int>((ref) => 0);

/// 扫描进度：总数
final scanTotalProvider = StateProvider<int>((ref) => 0);

/// 扫描取消标志
final scanCancelProvider = StateProvider<bool>((ref) => false);

final isActorFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('actor_is_fixed_column') ?? false;
});

final actorFixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('actor_fixed_column_count') ?? 5;
});

final actorSortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final sortIndex = prefs.getInt('actor_sort_mode') ?? 0;
  return SortMode.values[sortIndex.clamp(0, SortMode.values.length - 1)];
});

final actorViewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final viewIndex = prefs.getInt('actor_view_mode') ?? 2;
  return ViewMode.values[viewIndex.clamp(0, ViewMode.values.length - 1)];
});

final isCategoryFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('category_is_fixed_column') ?? false;
});

final categoryFixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('category_fixed_column_count') ?? 4;
});

final categorySortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final sortIndex = prefs.getInt('category_sort_mode') ?? 0;
  return SortMode.values[sortIndex.clamp(0, SortMode.values.length - 1)];
});

final categoryViewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final viewIndex = prefs.getInt('category_view_mode') ?? 2;
  return ViewMode.values[viewIndex.clamp(0, ViewMode.values.length - 1)];
});

// ===== 刮削相关 Providers =====

/// 刮削服务 Provider
final scraperServiceProvider = Provider<ScraperService>((ref) {
  return ScraperService();
});

/// 刮削配置 Provider（从设置加载）
final scraperConfigProvider = StateProvider<ScraperConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  
  // 从 SharedPreferences 加载配置
  final scanDir = prefs.getString('scraper_scan_dir') ?? '';
  final ignoreFoldersStr = prefs.getString('scraper_ignore_folders') ?? '';
  final ignoreFolders = ignoreFoldersStr.isNotEmpty
      ? ignoreFoldersStr.split('|').where((s) => s.isNotEmpty).toList()
      : <String>[];
  final javdbCookie = prefs.getString('scraper_javdb_cookie');
  final translateTitle = prefs.getBool('scraper_translate_title') ?? true;
  final translatePlot = prefs.getBool('scraper_translate_plot') ?? true;
  final maxWorkers = prefs.getInt('scraper_max_workers') ?? 4;
  
  // 读取代理设置（与设置页面共享的 proxy_mode / proxy_url）
  final proxyMode = prefs.getString('proxy_mode') ?? 'none';
  final proxyUrl = prefs.getString('proxy_url') ?? '';
  bool useProxy = false;
  String actualProxyUrl = '';

  if (proxyMode == 'custom' && proxyUrl.isNotEmpty) {
    useProxy = true;
    actualProxyUrl = proxyUrl;
  } else if (proxyMode == 'system') {
    // 尝试读取 Windows 系统代理（如 Clash 设置的 http://127.0.0.1:7897）
    final sysProxy = readWindowsSystemProxy();
    if (sysProxy != null && sysProxy.isNotEmpty) {
      useProxy = true;
      actualProxyUrl = sysProxy.startsWith('http') ? sysProxy : 'http://$sysProxy';
    }
  }
  
  return ScraperConfig(
    scanDir: scanDir,
    ignoreFolders: ignoreFolders,
    javdbCookie: javdbCookie,
    translateTitle: translateTitle,
    translatePlot: translatePlot,
    maxWorkers: maxWorkers,
    useProxy: useProxy,
    proxyUrl: actualProxyUrl,
  );
});

/// 刮削任务状态 Provider
final scrapingTaskStateProvider = StateProvider<ScrapingTaskState>((ref) {
  return ScrapingTaskState.idle;
});

/// Python 进程运行状态 Provider（用于 UI 实时刷新）
final scraperProcessRunningProvider = StateProvider<bool>((ref) {
  return false;
});

/// 待刮削影片列表 Provider
final scrapableMoviesProvider = StateProvider<List<ScrapableMovie>>((ref) {
  return [];
});

/// 刮削统计信息 Provider
final scrapeStatsProvider = Provider<ScrapeStats>((ref) {
  final movies = ref.watch(scrapableMoviesProvider);
  return ScrapeStats.fromList(movies);
});

// ===== 智能排序相关 Providers =====

/// 智能排序服务 Provider
final smartSortServiceProvider = Provider<SmartSortService>((ref) {
  final service = SmartSortService(
    videoRepository: ref.watch(videoRepositoryProvider),
    actorRepository: ref.watch(actorRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
  );
  return service;
});

/// 智能排序权重缓存 Provider
final smartSortWeightsProvider = FutureProvider<SmartSortWeights>((ref) async {
  final service = ref.watch(smartSortServiceProvider);
  return await service.getWeights();
});

// ===== 分页相关 Providers =====

/// 媒体页面分页模式
final mediaPaginationModeProvider = StateProvider<PaginationMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('media_pagination_mode') ?? 0;
  return PaginationMode.values[index.clamp(0, PaginationMode.values.length - 1)];
});

/// 已看页面分页模式
final watchedPaginationModeProvider = StateProvider<PaginationMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('watched_pagination_mode') ?? 0;
  return PaginationMode.values[index.clamp(0, PaginationMode.values.length - 1)];
});

/// 收藏页面分页模式
final favoritesPaginationModeProvider = StateProvider<PaginationMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('favorites_pagination_mode') ?? 0;
  return PaginationMode.values[index.clamp(0, PaginationMode.values.length - 1)];
});

/// 演员页面分页模式
final actorsPaginationModeProvider = StateProvider<PaginationMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('actors_pagination_mode') ?? 0;
  return PaginationMode.values[index.clamp(0, PaginationMode.values.length - 1)];
});

/// 分类页面分页模式
final categoriesPaginationModeProvider = StateProvider<PaginationMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('categories_pagination_mode') ?? 0;
  return PaginationMode.values[index.clamp(0, PaginationMode.values.length - 1)];
});

/// 媒体页面当前页码
final mediaCurrentPageProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('media_current_page') ?? 1;
});

/// 已看页面当前页码
final watchedCurrentPageProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('watched_current_page') ?? 1;
});

/// 收藏页面当前页码
final favoritesCurrentPageProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('favorites_current_page') ?? 1;
});

/// 演员页面当前页码
final actorsCurrentPageProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('actors_current_page') ?? 1;
});

/// 分类页面当前页码
final categoriesCurrentPageProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('categories_current_page') ?? 1;
});
