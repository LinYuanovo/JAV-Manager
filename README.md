# JAV-Manager

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.24+-02569B?style=flat-square&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x+-0175C2?style=flat-square&logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Version-1.1.0-blue?style=flat-square" alt="Version">
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地视频媒体管理器</b><br>
  <i>现代化 UI · 玻璃拟态设计 · 智能整理</i>
</p>

***

## ✨ 功能特性

### 📺 媒体管理

- **多种视图模式**：列表 / 海报 / 海报+标题 / 海报墙
- **灵活排序**：标题、随机、最近观看
- **自适应网格布局**，支持固定列数
- **手动/自动扫描**媒体库，实时更新

### 👤 演员管理

- **NFO 自动解析**：从 NFO 文件提取演员信息
- **在线头像获取**：通过 gfriends 仓库获取演员头像
- **详细信息**：Wikipedia 解析演员资料（生日、身高、三围等）
- **批量操作**：支持一键获取所有演员的头像和信息

### ❤️ 收藏功能

- **多类型收藏**：影片、演员、分类均可收藏
- **独立收藏页面**：支持搜索、筛选和排序
- **实时同步**：收藏状态即时更新到各页面

### 📋 已观看追踪

- **观看记录**：记录观看次数和最后观看时间
- **自动整理**：将已观看视频移动到指定目录
- **智能标记**：自动标记观看状态，媒体库不再显示已观看内容

## 🛠️ 技术栈

| 技术                                                                      | 版本          | 用途                |
| ----------------------------------------------------------------------- | ----------- | ----------------- |
| [Flutter](https://flutter.dev)                                          | 3.41.9      | 跨平台 UI 框架         |
| [Dart](https://dart.dev)                                                | 3.11.5      | 编程语言              |
| [Riverpod](https://riverpod.dev)                                        | ^2.4.9      | 状态管理              |
| [SQLite](https://www.sqlite.org)                                        | via sqflite | 本地数据存储            |
| [window\_manager](https://pub.dev/packages/window_manager)              | ^0.3.7      | 窗口管理（尺寸、位置、状态持久化） |
| [SharedPreferences](https://pub.dev/packages/shared_preferences)        | ^2.2.2      | 用户偏好设置持久化         |
| [cached\_network\_image](https://pub.dev/packages/cached_network_image) | ^3.3.0      | 网络图片缓存            |

## 📁 项目结构

```
JAV-Manager/
├── lib/                          # 应用源代码
│   ├── main.dart                 # 应用入口，初始化窗口和数据库
│   │
│   ├── core/                     # 核心业务逻辑
│   │   ├── database/
│   │   │   └── database_helper.dart      # SQLite 数据库助手（建表、CRUD）
│   │   │
│   │   ├── models/
│   │   │   └── models.dart               # 数据模型定义
│   │   │       ├── Video                 # 视频模型（标题、路径、演员、收藏等）
│   │   │       ├── Actor                 # 演员模型（姓名、头像、生日等）
│   │   │       └── Category              # 分类模型（标签、系列、片商）
│   │   │
│   │   ├── providers/
│   │   │   └── providers.dart            # Riverpod 状态管理
│   │   │       ├── allVideosProvider     # 所有视频数据（过滤已观看）
│   │   │       ├── allActorsProvider     # 所有演员数据
│   │   │       ├── favoritesProvider     # 收藏数据
│   │   │       └── settingsProvider      # 设置项（字体大小、排序偏好等）
│   │   │
│   │   ├── repositories/        # 数据访问层
│   │   │   ├── video_repository.dart     # 视频数据 CRUD 操作
│   │   │   ├── actor_repository.dart     # 演员数据 CRUD 操作
│   │   │   └── category_repository.dart  # 分类数据 CRUD 操作
│   │   │
│   │   ├── services/             # 业务服务
│   │   │   ├── media_scanner_service.dart    # 媒体扫描（解析 NFO、提取元数据）
│   │   │   ├── auto_task_service.dart        # 自动任务（定时整理已观看视频）
│   │   │   ├── avatar_service.dart           # 头像获取（gfriends 仓库）
│   │   │   └── wikipedia_service.dart        # Wikipedia 信息解析
│   │   │
│   │   └── utils/                # 工具类
│   │       ├── performance_monitor.dart      # 性能监控
│   │       └── proxy_client.dart             # HTTP 代理客户端
│   │
│   └── ui/                      # 用户界面
│       ├── theme/
│       │   └── app_theme.dart           # 主题配置（玻璃拟态组件）
│       │       ├── GlassContainer         # 玻璃容器
│       │       ├── GlassCard              # 玻璃卡片
│       │       ├── GlassButton            # 玻璃按钮
│       │       ├── GlassAppBar            # 毛玻璃导航栏
│       │       ├── GlassSearchBar         # 搜索栏
│       │       └── GradientBackground     # 渐变背景
│       │
│       └── pages/
│           ├── home_page.dart             # 主页（侧边栏导航 + 内容区）
│           │
│           ├── media/                     # 媒体模块
│           │   ├── media_page.dart        # 媒体列表页（网格/列表视图）
│           │   └── video_detail_dialog.dart  # 视频详情弹窗
│           │
│           ├── actors/                    # 演员模块
│           │   ├── actors_page.dart       # 演员列表页（头像网格）
│           │   └── actor_detail_page.dart # 演员详情页（作品列表、信息展示）
│           │
│           ├── categories/                # 分类模块
│           │   ├── categories_page.dart   # 分类浏览页（标签/系列/片商）
│           │   └── category_videos_page.dart  # 分类下的视频列表
│           │
│           ├── favorites/
│           │   └── favorites_page.dart    # 收藏页面（视频/演员 Tab 切换）
│           │
│           ├── watched/
│           │   └── watched_page.dart      # 已观看视频列表
│           │
│           ├── settings/
│           │   └── settings_page.dart     # 设置中心（路径、字体、代理配置）
│           │
│           └── test_page.dart            # 测试页面（开发调试用）
│
├── windows/                      # Windows 平台特定代码
│   └── runner/                   # 运行时资源
│       └── resources/
│           └── app_icon.ico     # 应用图标
│
├── fonts/                        # 自定义字体
│   └── MapleMonoNL-NF-CN-Medium.ttf  # 等宽中文字体
│
├── prompt/                       # 项目文档和提示词
│   ├── prompt.md                 # 项目需求说明
│   └── ui-prompt.md              # UI 设计规范
│
├── .github/workflows/            # GitHub Actions
│   └── build.yml                 # 自动构建和发布工作流
│
├── app_icon.png                  # 应用图标源文件
├── CHANGELOG.md                  # 版本更新日志
├── README.md                     # 项目说明文档
├── pubspec.yaml                  # 项目配置和依赖
└── pubspec.lock                  # 依赖版本锁定
```

## 🚀 快速开始

### 环境要求

- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5
- **操作系统**: Windows 10/11 (64位)
- **内存**: 建议 8GB+
- **磁盘空间**: 2GB+ (用于构建)

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/LinYuanovo/JAV-Manager.git
   cd JAV-Manager
   ```
2. **安装依赖**
   ```bash
   flutter pub get
   ```
3. **运行应用（开发模式）**
   ```bash
   flutter run -d windows
   ```
4. **构建发布版本**
   ```bash
   flutter build windows --release
   ```
   可执行文件位于：
   ```
   build/windows/x64/runner/Release/jav_manager.exe
   ```

## 📂 媒体库目录结构

应用期望以下目录结构来正确识别和管理视频：

```
媒体库根目录/
├── #整理完成/                    # 主媒体库
│   ├── 演员名/
│   │   └── [番号] 视频标题/
│   │       ├── poster.jpg        # 海报图 (必需)
│   │       ├── fanart.jpg        # 背景图 (可选)
│   │       ├── movie.nfo         # 元数据文件 (必需)
│   │       └── 视频文件.mp4      # 视频文件
│   └── 演员2,演员3/              # 多演员用逗号分隔
│
└── Watched/                      # 已观看目录 (可在设置中自定义路径)
    └── ...
```

### NFO 文件格式示例

应用通过解析 `movie.nfo` 文件提取视频元数据：

```xml
<movie>
  <title>视频标题</title>
  <originaltitle>原始标题</originaltitle>
  <actor>
    <name>演员名</name>
  </actor>
  <genre>标签1</genre>
  <genre>标签2</genre>
  <set>系列名</set>
  <studio>片商名</studio>
  <plot>剧情简介...</plot>
  <premiered>2024-01-01</premiered>
</movie>
```

**关键字段说明：**

- `<actor><name>` - 提取演员名称
- `<genre>` - 提取标签分类
- `<set>` - 提取系列分类
- `<studio>` - 提取片商分类
- `<title>` - 显示标题

## 🙏 致谢

- [Flutter Team](https://flutter.dev) - 优秀的跨平台框架
- [Riverpod](https://riverpod.dev) - 强大的状态管理方案
- [gfriends](https://github.com/gfriends/gfriends) - 演员头像资源仓库
- [Wikipedia](https://www.wikipedia.org) - 演员公开信息来源

