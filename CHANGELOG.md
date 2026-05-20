# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
