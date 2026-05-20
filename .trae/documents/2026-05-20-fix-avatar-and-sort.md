# 修复头像显示、更新与收藏排序

## 摘要

修复 3 个问题：

1. `Image.file` + `cacheWidth: 200` 导致演员详情页（180x180 容器）在高分屏上头像模糊
2. 更换头像后，`Image.file` 的 `FileImage` 缓存未失效，导致不刷新
3. 媒体页/演员详情/分类详情排序不优先显示收藏视频

***

## 当前状态分析

### 问题 1：头像分辨率不足（\[actor\_avatar.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/widgets/actor\_avatar.dart#L36)）

```dart
cacheWidth: (width ?? 200).toInt(),  // 固定解码为200px宽
```

* 演员详情页头像容器为 180x180 dp（\[actor\_detail\_page.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/actors/actor\_detail\_page.dart#L218)）

* 2x DPI 屏幕需 360px 解码宽度，200px 不足 → 模糊

* 原 `Image.memory` 无此限制，始终全分辨率解码

### 问题 2：头像无法实时更新（\[actor\_detail\_page.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/actors/actor\_detail\_page.dart#L644-L668)）

更换头像流程：

1. 删除旧文件（644-648）
2. 下载新文件并写入**同一路径**（651-658）
3. 更新 DB + 自增 `_avatarKey` + `setState`（660-668）

问题根因：

* `Image.file` 内部使用 `FileImage`，按**文件路径**缓存解码结果

* 旧文件删除 + 新文件写回同路径 → `FileImage` 缓存命中旧数据

* 即使传入 `key: ValueKey(_avatarKey)`，`Image.key` 不影响 `FileImage` 缓存键

### 问题 3：收藏排序未生效

| 页面                                                                                                                                     | 当前调用                                                          | 问题                          |
| -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------- |
| \[media\_page.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/media/media\_page.dart#L59)                            | `sortVideos(filteredVideos, sortMode, randomKey: _randomKey)` | 缺 `separateFavorites: true` |
| \[actor\_detail\_page.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/actors/actor\_detail\_page.dart#L486)          | `sortVideos(videos, _sortMode)`                               | 缺 `separateFavorites: true` |
| \[category\_videos\_page.dart]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/categories/category\_videos\_page.dart#L83) | `sortVideos(videos, _sortMode)`                               | 缺 `separateFavorites: true` |

此外，\[sortVideos 函数]\(file:///e:/Programs/Trae Projects/JAV-Manager/lib/ui/pages/home\_page.dart#L1068-L1115) 在 `randomKey > 0` 时提前 return，完全跳过 `separateFavorites` 逻辑，导致随机排序下收藏不优先。

***

## 修改方案

### 修改 1：ActorAvatar - 移除 `cacheWidth`，解决模糊问题

**文件**: `lib/ui/widgets/actor_avatar.dart`

**变更**: 删除 `Image.file` 的 `cacheWidth` 参数，恢复全分辨率解码（与原 `Image.memory` 行为一致）。现有移动端/桌面端内存完全够用，解码单张头像无性能问题。

```diff
 Image.file(
   File(avatarUrl!),
   key: imageKey,
   fit: BoxFit.cover,
-  cacheWidth: (width ?? 200).toInt(),
   errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
 ),
```

### 修改 2：ActorAvatar - 头像缓存失效支持

**文件**: `lib/ui/widgets/actor_avatar.dart`

**新增方法**: `evictCache(String filePath)` 静态方法，供外部在头像文件更新后调用。

```dart
/// 清除指定路径图片的 Flutter 内存缓存，使下次加载时重新解码
static void evictCache(String filePath) {
  final provider = FileImage(File(filePath));
  PaintingBinding.instance.imageCache.evict(provider);
}
```

同时需要添加 `import 'package:flutter/painting.dart';`（或使用 `PaintingBinding.instance` 已通过 `material.dart` 可用）。

### 修改 3：演员详情页 - 调用缓存失效

**文件**: `lib/ui/pages/actors/actor_detail_page.dart`

在头像更换成功后（`setState` 之前），调用 `ActorAvatar.evictCache()` 清除旧路径的缓存：

```diff
 await File(filePath).writeAsBytes(response.bodyBytes);

+// Clear image cache so Image.file re-decodes the new file
+ActorAvatar.evictCache(filePath);
+
 setState(() {
   _actor = _actor.copyWith(avatarUrl: filePath);
   _avatarKey = DateTime.now().microsecondsSinceEpoch;
 });
```

### 修改 4：sortVideos - 支持随机模式下的收藏优先

**文件**: `lib/ui/pages/home_page.dart`

修改 `randomKey > 0` 分支，当 `separateFavorites=true` 时先分组再分别随机：

```diff
 List<Video> sortVideos(List<Video> videos, SortMode mode, {int randomKey = 0, bool separateFavorites = false}) {
   final sorted = List<Video>.from(videos);
+
+  // Separate favorites first (before any sorting)
+  if (separateFavorites) {
+    final favs = sorted.where((v) => v.isFavorite).toList();
+    final nonFavs = sorted.where((v) => !v.isFavorite).toList();
+
   if (randomKey > 0) {
-    sorted.shuffle(Random(randomKey));
-    return sorted;
+      favs.shuffle(Random(randomKey));
+      nonFavs.shuffle(Random(randomKey * 31 + 7)); // different seed for non-favs
+      return [...favs, ...nonFavs];
   }
+
+    applySort(favs);
+    applySort(nonFavs);
+    return [...favs, ...nonFavs];
+  }
+
   ...
   applySort(sorted);
   return sorted;
 }
```

注意：`applySort` 闭包定义移到 `separateFavorites` 分支之前。

### 修改 5：三个页面启用收藏优先排序

**文件**: `lib/ui/pages/media/media_page.dart` line 59

```diff
-final sortedVideos = sortVideos(filteredVideos, sortMode, randomKey: _randomKey);
+final sortedVideos = sortVideos(filteredVideos, sortMode, randomKey: _randomKey, separateFavorites: true);
```

**文件**: `lib/ui/pages/actors/actor_detail_page.dart` line 486

```diff
-final sorted = sortVideos(videos, _sortMode);
+final sorted = sortVideos(videos, _sortMode, separateFavorites: true);
```

**文件**: `lib/ui/pages/categories/category_videos_page.dart` line 83

```diff
-final sorted = sortVideos(videos, _sortMode);
+final sorted = sortVideos(videos, _sortMode, separateFavorites: true);
```

***

## 假设与决策

* **High-DPI**: 移除 `cacheWidth` 后，180x180 widget 在 3x 屏幕解码 540px，内存增加可忽略（\~1MB/张）

* **缓存失效粒度**: 使用 `FileImage.evict()` 而非 `imageCache.clear()`，只清除目标文件缓存

* **随机+收藏**: 两组使用不同 seed (`randomKey * 31 + 7`) 避免两组相同顺序

* **不涉及业务逻辑变更**: 仅优化显示质量和排序表现

## 验证步骤

1. 运行 `flutter analyze` 确认零错误
2. 编译运行，演员详情页头像清晰度对比
3. 在演员详情页更换头像，确认无需重启即可刷新
4. 在媒体页收藏某视频，随机排序下确认优先显示

