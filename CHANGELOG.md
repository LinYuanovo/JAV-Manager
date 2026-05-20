# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-05-20

### Added
- 全局玻璃风格菜单主题（PopupMenuThemeData 圆角20px + 半透明背景 + 柔和阴影）
- 右键上下文菜单统一使用 `AppTheme.showGlassMenu()` 玻璃样式
- 搜索防抖工具类 `Debouncer`（300ms 延迟，媒体页/演员页/已看页）
- `LayoutConstants` 常量类（窗口尺寸、卡片宽度、详情页尺寸等统一管理）
- `VideoExtension.extractCode()` 扩展方法（替代3处重复的 `_extractCode`）
- `AppSettings` 单例缓存（避免每次调用重复读磁盘）
- `AppSettings.invalidateCache()` 方法（导入备份后刷新缓存）
- 收藏页面 tab 持久化（`favorites_last_tab`）
- 分类页面 tab 持久化（`categories_last_tab`）

### Fixed
- **严重**：修复 DatabaseHelper 竞态条件导致 "Future already completed" 崩溃（Completer → Future 缓存模式）
- **严重**：修复点击影片卡死 / RenderBox was not laid out（移除 Expanded 外层 RepaintBoundary）
- **严重**：修复 N+1 查询问题（1000 视频从 2001 次查询降至 3 次）
- **严重**：修复 HTTP 客户端泄漏（avatar_service / wikipedia_service 添加 try/finally）
- **严重**：修复 _mapToJson 手动拼接 JSON 导致特殊字符损坏（改用 jsonEncode）
- **严重**：修复 AppSettings 非原子写入导致崩溃时文件损坏（先写 .tmp 再 rename）
- **严重**：修复 ViewMode/SortMode 枚举索引越界崩溃（添加 .clamp 边界检查）
- **严重**：修复 Timer 回调未防并发扫描（_isScanning/_isMoving 锁标志）
- **严重**：修复 WebDAV response stream 未消费导致连接泄漏（drain<void>()）
- **严重**：修复 moveVideoToWatched 先删目标再重命名数据丢失风险（临时位置安全移动）
- 修复所有 Image.file/Image.network 缺少 errorBuilder 导致红屏崩溃
- 修复 AutoTaskService.dispose() 未被调用导致 StreamController 泄漏
- 修复 copyWith 无法将 nullable 字段设为 null（_undefined 哨兵值模式）
- 修复分类/收藏页面 tab 初始化从第一个切换动画（initialIndex 同步传入）
- 修复 ActorAvatar 同步文件检查阻塞 UI 线程（_fileExistsCache 缓存）
- 修复 showCopyToast 动画无效（创建 StatefulWidget 实现淡出效果）
- 修复已看页面列表模式下纯净模式显示原始图片
- 修复媒体页面收藏按钮在纯净模式下消失
- 修复影片详情页海报墙在纯净模式下显示原始图片
- 修复 TabController 监听过度触发 setState（indexIsChanging 检查）
- 修复 dynamic 类型滥用（watched_page 全部替换为 Video 类型）
- 修复异步操作缺少 try/catch（6 个文件的 toggleFavorite 添加错误处理）

### Changed
- 版本号升级至 1.3.0
- 全面代码审查与性能优化（26 项改进）
- 所有 PopupMenuButton 自动应用玻璃拟态风格
- 右键菜单、排序菜单、视图菜单统一圆润风格
- 窗口最大化图标动态切换（未最大化 ▢ / 最大化后 ▢▢）
- 已看页面标题栏移除数字徽章和图标
- 收藏页面标题栏移除图标
- 6 处空状态 UI 统一复用 EmptyStateWidget 组件
- 数据库查询性能大幅提升（批量关联加载替代逐条查询）

## [1.2.0] - 2026-05-20

### Added
- WebDAV 云备份功能（上传/下载/列表/删除/导入数据库备份）
- 本地备份功能（导出/导入 .db 文件，调用系统文件选择器）
- 全局排序函数 `sortVideos` 统一至 `home_page.dart`，支持 `separateFavorites` 参数
- 全局视图模式图标函数 `getViewModeIcon` 提取至 `app_theme.dart`
- 共享组件 `ActorAvatar`（`Image.file` + 缓存失效 + 文件存在性检查）
- 空状态占位组件 `EmptyStateWidget`
- 数据库路径获取方法 `DatabaseHelper.getDatabasePath()`

### Fixed
- 修复 WebDAV 导入备份时 DB 文件被占用导致失败（先关闭连接再替换）
- 修复 WebDAV 删除备份后弹窗堆叠问题（关闭旧弹窗再刷新）
- 修复演员头像更换后重启不显示的问题（添加 `evictCache()` 缓存失效）
- 修复 WebDAV PROPFIND 响应解析不支持多 namespace 前缀（D:/d:/lp1:）
- 修复所有静默 catch 块添加 debugPrint 日志输出

### Changed
- 版本号升级至 1.2.0+4
- 代码审查优化：消除 ~170 行重复代码（排序/图标/头像组件）
- 模型层 JSON 解析器从手写改为标准 `jsonEncode`/`jsonDecode`
- 收藏视频在所有页面优先排序显示（媒体页/演员详情/分类详情）
- 演员头像使用 `Image.file` 替代 `FutureBuilder` + `Image.memory`
- 移除未使用的 `test_page.dart` 和未引用的 import

## [1.1.1] - 2026-05-19

### Added
- 双击视频标题复制番号，正则提取纯番号（如 BACJ-180）
- 双击演员名字复制名字
- 双击分类/标签/片商名称复制
- 玻璃拟态复制提示弹窗（顶部居中，白底蓝字，毛玻璃效果）
- 无视频未收藏演员自动清理：演员页面即时过滤 + 扫描时删除DB记录和本地头像

### Fixed
- 修复GitHub Actions打包后exe图标为默认Flutter图标
- 修复自动整理后已看页面海报空白问题
- 修复分类页数量显示包含已观看视频导致虚高
- 修复演员/分类全部SQL查询统计已观看视频的问题
- 修复SQLite未开启外键约束导致ON DELETE CASCADE无效

### Changed
- 版本号升级至1.1.1+3
- 演员页面不再显示无视频且未收藏的演员
- README版本徽章和技术栈版本号同步更新

## [1.1.0] - 2026-05-19

### Added
- 应用图标配置（app_icon.png）
- GitHub Actions自动打包发布工作流
- CHANGELOG.md版本记录文件
- 按钮透明度统一调整为0.7，提升视觉一致性
- Prompt文件整理到独立prompt文件夹

### Changed
- 版本号升级至1.1.0+2
- README.md精简优化，移除冗余章节

## [1.0.0] - 2026-05-19

### Added
- 初始版本发布
- 媒体库管理功能（扫描、分类、搜索）
- 演员信息管理（头像获取、详情展示）
- 收藏系统（视频/演员收藏）
- 已观看视频管理
- 自动整理功能（移动已观看视频）
- 设置中心（路径配置、字体调整、代理设置）
- 玻璃拟态UI设计
- 窗口状态持久化
- 数据本地化存储

### Features
- 📁 媒体库管理：视频扫描、分类展示、搜索排序
- 👤 演员管理：信息获取、头像显示、作品列表
- ⭐ 收藏系统：快速收藏、分类查看
- ✅ 已观看：自动标记、手动管理
- ⚙️ 设置中心：个性化配置
- 🔄 自动整理：智能归档已观看内容

### Technical
- Flutter/Dart框架
- Riverpod状态管理
- SQLite本地数据库
- Windows桌面应用支持
