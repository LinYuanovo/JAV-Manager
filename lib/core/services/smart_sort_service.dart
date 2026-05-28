import '../models/models.dart';
import '../repositories/video_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/category_repository.dart';

class SmartSortWeights {
  final Map<String, double> actorWeights;
  final Map<String, double> tagWeights;
  final Map<String, double> studioWeights;

  SmartSortWeights({
    required this.actorWeights,
    required this.tagWeights,
    required this.studioWeights,
  });
}

class SmartSortService {
  static const int _actorBaseWeight = 15;
  static const int _actorOccurrenceBonus = 8;
  static const int _tagBaseWeight = 10;
  static const int _tagOccurrenceBonus = 5;
  static const int _studioBaseWeight = 5;
  static const int _studioOccurrenceBonus = 3;
  static const int _favoriteActorWeight = 20;
  static const int _favoriteCategoryWeight = 12;

  final VideoRepository _videoRepository;
  final ActorRepository _actorRepository;
  final CategoryRepository _categoryRepository;

  SmartSortWeights? _cachedWeights;
  DateTime? _cacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  SmartSortService({
    VideoRepository? videoRepository,
    ActorRepository? actorRepository,
    CategoryRepository? categoryRepository,
  })  : _videoRepository = videoRepository ?? VideoRepository(),
        _actorRepository = actorRepository ?? ActorRepository(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  void invalidateCache() {
    _cachedWeights = null;
    _cacheTime = null;
  }

  bool get isCacheValid {
    if (_cachedWeights == null || _cacheTime == null) return false;
    return DateTime.now().difference(_cacheTime!) < _cacheValidDuration;
  }

  Future<SmartSortWeights> getWeights() async {
    if (isCacheValid) return _cachedWeights!;

    final weights = await _calculateWeights();
    _cachedWeights = weights;
    _cacheTime = DateTime.now();
    return weights;
  }

  Future<SmartSortWeights> _calculateWeights() async {
    final actorFrequency = <String, int>{};
    final tagFrequency = <String, int>{};
    final studioFrequency = <String, int>{};

    final favoriteVideos = await _videoRepository.getFavoriteVideos();
    for (final video in favoriteVideos) {
      for (final actor in video.actors) {
        actorFrequency[actor.name] = (actorFrequency[actor.name] ?? 0) + 1;
      }
      for (final category in video.categories) {
        if (category.type == Category.typeTag) {
          tagFrequency[category.name] = (tagFrequency[category.name] ?? 0) + 1;
        } else if (category.type == Category.typeStudio) {
          studioFrequency[category.name] = (studioFrequency[category.name] ?? 0) + 1;
        }
      }
    }

    final actorWeights = <String, double>{};
    for (final entry in actorFrequency.entries) {
      final count = entry.value;
      actorWeights[entry.key] = _actorBaseWeight + _actorOccurrenceBonus * (count - 1);
    }

    final tagWeights = <String, double>{};
    for (final entry in tagFrequency.entries) {
      final count = entry.value;
      tagWeights[entry.key] = _tagBaseWeight + _tagOccurrenceBonus * (count - 1);
    }

    final studioWeights = <String, double>{};
    for (final entry in studioFrequency.entries) {
      final count = entry.value;
      studioWeights[entry.key] = _studioBaseWeight + _studioOccurrenceBonus * (count - 1);
    }

    final favoriteActors = await _actorRepository.getFavoriteActors();
    for (final actor in favoriteActors) {
      final existingWeight = actorWeights[actor.name] ?? 0;
      actorWeights[actor.name] = existingWeight + _favoriteActorWeight;
    }

    final favoriteCategories = await _categoryRepository.getFavoriteCategories();
    for (final category in favoriteCategories) {
      if (category.type == Category.typeTag || category.type == Category.typeSeries) {
        final existingWeight = tagWeights[category.name] ?? 0;
        tagWeights[category.name] = existingWeight + _favoriteCategoryWeight;
      } else if (category.type == Category.typeStudio) {
        final existingWeight = studioWeights[category.name] ?? 0;
        studioWeights[category.name] = existingWeight + _favoriteCategoryWeight;
      }
    }

    return SmartSortWeights(
      actorWeights: actorWeights,
      tagWeights: tagWeights,
      studioWeights: studioWeights,
    );
  }

  double calculateVideoScore(Video video, SmartSortWeights weights) {
    double score = 0;

    for (final actor in video.actors) {
      score += weights.actorWeights[actor.name] ?? 0;
    }

    for (final category in video.categories) {
      if (category.type == Category.typeTag || category.type == Category.typeSeries) {
        score += weights.tagWeights[category.name] ?? 0;
      } else if (category.type == Category.typeStudio) {
        score += weights.studioWeights[category.name] ?? 0;
      }
    }

    return score;
  }

  Future<List<Video>> sortVideos(List<Video> videos, {bool descending = true}) async {
    final weights = await getWeights();

    final scoredVideos = videos.map((video) {
      final score = calculateVideoScore(video, weights);
      return MapEntry(video, score);
    }).toList();

    scoredVideos.sort((a, b) {
      final scoreComparison = descending
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      if (scoreComparison != 0) return scoreComparison;
      return (a.key.title ?? '').compareTo(b.key.title ?? '');
    });

    return scoredVideos.map((entry) => entry.key).toList();
  }
}
