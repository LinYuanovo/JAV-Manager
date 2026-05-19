import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/video_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/category_repository.dart';
import '../services/media_scanner_service.dart';
import '../services/wikipedia_service.dart';
import '../services/auto_task_service.dart';
import '../services/avatar_service.dart';
import '../models/models.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized');
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
  return MediaScannerService(
    videoRepository: ref.watch(videoRepositoryProvider),
    actorRepository: ref.watch(actorRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
  );
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

final fontSizeProvider = StateProvider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getDouble('font_size') ?? 14.0;
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
    final result = await repository.getAllActors();
    if (kDebugMode) {
      debugPrint('✅ Loaded ${result.length} actors');
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
  return ViewMode.values[index];
});

final sortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('sort_mode') ?? 0;
  return SortMode.values[index];
});

final favoriteSortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('favorite_sort_mode') ?? 0;
  return SortMode.values[index];
});

final favoriteViewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('favorite_view_mode') ?? 0;
  return ViewMode.values[index];
});

final isFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('media_is_fixed_column') ?? false;
});

final fixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('media_fixed_column_count') ?? 4;
});

final isScanningProvider = StateProvider<bool>((ref) => false);

final isActorFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('actor_is_fixed_column') ?? false;
});

final actorFixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('actor_fixed_column_count') ?? 5;
});

final isCategoryFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('category_is_fixed_column') ?? false;
});

final categoryFixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('category_fixed_column_count') ?? 4;
});
