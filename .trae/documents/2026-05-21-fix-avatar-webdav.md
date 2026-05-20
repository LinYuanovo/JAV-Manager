# Fix: 头像不显示 + Add: WebDAV 备份

## 摘要
1. **Fix**: 演员手动更换头像后，下次启动可能不显示头像
2. **Add**: 设置页新增 WebDAV 备份功能区（查看云端备份列表、备份数据、服务地址/用户名/密码配置）

---

## Part 1: 头像不显示修复

### 根因分析

问题出在 `Image.file` 加载失败时 `errorBuilder` 静默返回 placeholder，不给用户任何反馈。新旧代码在这一点上行为一致（旧代码 `FutureBuilder` 的 `snapshot.hasError` 也未处理），所以更可能的原因是：

1. **文件路径不一致**: `Image.file` 需要**绝对路径**，但从 DB 读出的 `avatar_url` 可能是相对路径（旧代码 `File.readAsBytesSync()` 也需绝对路径，但 `FutureBuilder` 中的 `file.readAsBytes()` 返回 Future，即使路径无效也不抛异常到 builder，而是 snapshot.data 为空 → 走到 placeholder）

2. **Image.file 的 FileImage 缓存机制**: 首次加载成功（缓存热），重启后缓存冷 → 如果文件因某些原因不可访问（权限、路径变化），`errorBuilder` 接管但无日志

### 修复方案

**文件**: `lib/ui/widgets/actor_avatar.dart`

在 `build()` 中增加文件存在性检查 + errorBuilder 增加 debugPrint：

```dart
@override
Widget build(BuildContext context) {
  if (avatarUrl != null && avatarUrl!.isNotEmpty) {
    final file = File(avatarUrl!);
    // Only attempt Image.file if the file actually exists
    if (file.existsSync()) {
      return SizedBox(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        child: Image.file(
          file,
          key: imageKey,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[ActorAvatar] Failed to load: $avatarUrl, error: $error');
            return _buildPlaceholder();
          },
        ),
      );
    }
    debugPrint('[ActorAvatar] File not found: $avatarUrl');
  }
  return _buildPlaceholder();
}
```

添加 `import 'package:flutter/foundation.dart';` 用于 `debugPrint`。

同时检查 `cacheWidth` 重建机会：对于 actors_page 中的小头像（通常是 ~80px 缩略图），可以在调用处加 `width` 参数（之前 `_ActorCard` 没有传 width/height，我们可以在 `actors_page.dart` 中添加 `cacheWidth: 160`）。

但更简单的：在 `actors_page.dart` 调用 `ActorAvatar` 时传入 `cacheWidth: 160` 控制内存。演员列表页头像较小，加缓存宽度合理；详情页头像 180×180 不加 limit 保证清晰度。

**修改 `actors_page.dart` 和 `favorites_page.dart` 中的 `ActorAvatar` 调用，添加 `cacheWidth: 160`**:

```dart
ActorAvatar(
  avatarUrl: widget.actor.avatarUrl,
  name: widget.actor.name,
  cacheWidth: 160,
),
```

并在 `ActorAvatar` 中新增 `cacheWidth` 可选参数。

---

## Part 2: WebDAV 备份功能

### 新增文件

#### `lib/core/services/webdav_service.dart`

WebDAV 服务类，封装标准 WebDAV 协议操作：

- `listBackups(String serverUrl, String username, String password)` → `Future<List<WebDavFile>>` — PROPFIND 请求列出 `/backups/` 目录下文件
- `uploadBackup(String serverUrl, String username, String password, String localDbPath, String fileName)` → `Future<bool>` — PUT 请求上传 .db 文件
- `downloadBackup(String serverUrl, String username, String password, String remotePath, String localPath)` → `Future<bool>` — GET 请求下载备份文件
- `deleteBackup(String serverUrl, String username, String password, String remotePath)` → `Future<bool>` — DELETE 请求删除远程备份
- `importBackup(String serverUrl, String username, String password, String remotePath)` → `Future<bool>` — 下载备份 → 关闭当前 DB → 替换本地 DB 文件 → 提示重启

WebDAV 使用标准 HTTP 方法（PUT/GET/DELETE/PROPFIND），通过 `http` 包（已有依赖）实现。需处理深度 PROPFIND 的 XML 响应解析（已有 `xml` 包）。

`WebDavFile` 数据类：
```dart
class WebDavFile {
  final String name;
  final int sizeBytes;
  final DateTime modifiedDate;
}
```

#### Provider 注册

在 `providers.dart` 中新增：
```dart
final webdavServiceProvider = Provider<WebdavService>((ref) {
  return WebdavService();
});
```

### 修改文件

#### `lib/ui/pages/settings/settings_page.dart`

在 build() 中插入新的 WebDAV section（放在"网络代理设置"之前）：

新增字段：
```dart
late TextEditingController _webdavUrlController;
late TextEditingController _webdavUsernameController;
late TextEditingController _webdavPasswordController;
bool _webdavPasswordVisible = false;
bool _isBackingUp = false;
bool _isLoadingBackups = false;
List<WebDavFile>? _backupFiles;
```

在 `_loadSettings()` 中加载：
```dart
final webdavUrl = prefs.getString('webdav_url') ?? '';
final webdavUsername = prefs.getString('webdav_username') ?? '';
final webdavPassword = prefs.getString('webdav_password') ?? '';
_webdavUrlController = TextEditingController(text: webdavUrl);
_webdavUsernameController = TextEditingController(text: webdavUsername);
_webdavPasswordController = TextEditingController(text: webdavPassword);
```

在 `_saveSettings()` 中保存：
```dart
await prefs.setString('webdav_url', _webdavUrlController.text);
await prefs.setString('webdav_username', _webdavUsernameController.text);
await prefs.setString('webdav_password', _webdavPasswordController.text);
```

在 `dispose()` 中释放新 controller。

新增 `_buildWebdavSection()` 方法——UI 布局：

**第一排**：两个按钮
- "查看备份" → 点击打开 `showDialog`，内含 `FutureBuilder` 调用 `webdavService.listBackups()`，展示表格：
  - 列：文件名、文件大小、备份日期、操作（删除/下载/导入）
  - 刷新按钮
- "备份数据" → 上传当前 `jav_manager.db` 到 WebDAV `/backups/jav_manager_{timestamp}.db`

**第二排**：服务地址
- 带 label "服务地址" 的 TextField
- 占位符 hint：`https://your-webdav-server.com/remote.php/dav/files/username/`

**第三排**：用户名
- 带 label "用户名" 的 TextField

**第四排**：密码
- 带 label "密码" 的 TextField
- suffixIcon: `IconButton` 切换 `_webdavPasswordVisible` 状态，图标在 `Icons.visibility` / `Icons.visibility_off` 之间切换

#### `lib/core/database/database_helper.dart`

新增静态方法获取数据库文件路径：
```dart
static Future<String> getDatabasePath() async {
  final appDir = await getAppDir();
  return join(appDir, _databaseName);
}
```

（该路径用于 WebDAV 上传时定位 .db 文件）

---

## 修改文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/ui/widgets/actor_avatar.dart` | 修改 | `build()` 加 `file.existsSync()` 检查 + errorBuilder 加 debugPrint |
| `lib/ui/pages/actors/actors_page.dart` | 修改 | `ActorAvatar` 调用加 `cacheWidth: 160` |
| `lib/ui/pages/favorites/favorites_page.dart` | 修改 | `ActorAvatar` 调用加 `cacheWidth: 160` |
| `lib/core/services/webdav_service.dart` | **新建** | WebDAV 协议封装（PROPFIND/PUT/GET/DELETE） |
| `lib/core/providers/providers.dart` | 修改 | 注册 `webdavServiceProvider` |
| `lib/core/database/database_helper.dart` | 修改 | 新增 `getDatabasePath()` 静态方法 |
| `lib/ui/pages/settings/settings_page.dart` | 修改 | 新增 WebDAV section UI + 对应逻辑 |

## 验证
1. `flutter analyze` 零错误
2. 演员头像：重启后头像正常显示，手动更换后再重启也正常
3. 设置页 WebDAV 区域 UI 正确排列
4. WebDAV 上传/列出/删除/下载功能正常（需配置有效 WebDAV 服务器测试）