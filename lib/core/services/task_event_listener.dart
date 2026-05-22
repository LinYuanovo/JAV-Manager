import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';

/// 自动任务事件监听器，将任务事件与业务逻辑解耦
class TaskEventListener {
  final Ref _ref;
  StreamSubscription? _autoMoveSubscription;

  TaskEventListener(this._ref);

  /// 初始化：启动自动任务服务并监听事件
  Future<void> initialize() async {
    final autoTask = _ref.read(autoTaskServiceProvider);
    if (!autoTask.isRunning) {
      autoTask.start();
    }

    _autoMoveSubscription = autoTask.onAutoMoveComplete.listen((movedCount) {
      if (movedCount > 0) {
        final mediaCountService = _ref.read(mediaCountServiceProvider);
        mediaCountService.refreshAllProviders();
        mediaCountService.updateMediaCount(-movedCount);
      }
    });
  }

  /// 释放资源
  void dispose() {
    _autoMoveSubscription?.cancel();
    _ref.read(autoTaskServiceProvider).dispose();
  }
}
