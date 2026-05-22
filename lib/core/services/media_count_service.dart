import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';

/// 媒体计数服务，统一管理所有媒体计数的获取和更新
class MediaCountService {
  final Ref _ref;

  MediaCountService(this._ref);

  int get mediaCount {
    final asyncVideos = _ref.watch(allVideosProvider);
    return asyncVideos.whenOrNull(data: (videos) => videos.length) ?? _ref.read(mediaCountStateProvider);
  }

  int get actorCount {
    final asyncActors = _ref.watch(allActorsProvider);
    return asyncActors.whenOrNull(data: (actors) => actors.length) ?? 0;
  }

  int get watchedCount {
    final asyncVideos = _ref.watch(watchedVideosProvider);
    return asyncVideos.whenOrNull(data: (videos) => videos.length) ?? 0;
  }

  /// 同步媒体计数到 mediaCountStateProvider
  void syncMediaCount() {
    final asyncVideos = _ref.read(allVideosProvider);
    asyncVideos.whenOrNull(data: (videos) {
      _ref.read(mediaCountStateProvider.notifier).state = videos.length;
    });
  }

  /// 增量更新媒体计数
  void updateMediaCount(int delta) {
    final currentCount = _ref.read(mediaCountStateProvider);
    _ref.read(mediaCountStateProvider.notifier).state = (currentCount + delta).clamp(0, 99999);
  }

  /// 刷新所有媒体相关 Provider
  void refreshAllProviders() {
    _ref.invalidate(allVideosProvider);
    _ref.invalidate(watchedVideosProvider);
    _ref.invalidate(favoriteVideosProvider);
  }
}
