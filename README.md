# JAV-Manager

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.24+-02569B?style=flat-square&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x+-0175C2?style=flat-square&logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地视频媒体管理器</b><br>
  <i>现代化 UI · 玻璃拟态设计 · 智能整理</i>
</p>

---

## ✨ 功能特性

### 📺 媒体管理
- 多种视图模式：列表 / 海报 / 海报+标题 / 海报墙
- 灵活排序：标题、随机、最近观看
- 自适应网格布局，支持固定列数
- 手动/自动扫描媒体库

### 👤 演员管理
- 自动从 NFO 文件提取演员信息
- 在线获取演员头像（gfriends 仓库）
- Wikipedia 解析演员详细资料（生日、身高、三围等）
- 批量获取头像和信息

### 🏷️ 分类系统
- **标签** - 从 NFO 的 tag 字段提取
- **系列** - 从 NFO 的 set 字段提取  
- **片商** - 从 NFO 的 studio 字段提取
- 繁简转换，避免重复分类

### ❤️ 收藏功能
- 收藏影片、演员、分类
- 独立收藏页面，支持搜索和筛选
- 实时同步更新

### 📋 已观看追踪
- 记录观看次数和最后观看时间
- 自动整理已观看视频到指定目录
- 可配置自动整理间隔

### ⚙️ 设置中心
- 媒体库目录配置
- 自定义播放器路径
- 已观看目录设置
- 代理服务器配置
- 字体和字号调整
- 窗口状态记忆

## 🛠️ 技术栈

| 技术 | 用途 |
|------|------|
| [Flutter](https://flutter.dev) | 跨平台 UI 框架 |
| [Riverpod](https://riverpod.dev) | 状态管理 |
| [SQLite](https://www.sqlite.org) | 本地数据存储 |
| [window_manager](https://pub.dev/packages/window_manager) | 窗口管理 |
| [SharedPreferences](https://pub.dev/packages/shared_preferences) | 用户偏好设置 |

## 📁 项目结构

```
lib/
├── main.dart                    # 应用入口
├── core/
│   ├── database/               # 数据库助手
│   ├── models/                 # 数据模型 (Video, Actor, Category)
│   ├── providers/              # Riverpod Provider
│   ├── repositories/           # 数据访问层
│   │   ├── video_repository.dart
│   │   ├── actor_repository.dart
│   │   └── category_repository.dart
│   ├── services/               # 业务逻辑
│   │   ├── media_scanner_service.dart   # 媒体扫描
│   │   ├── auto_task_service.dart       # 自动任务
│   │   ├── avatar_service.dart          # 头像服务
│   │   └── wikipedia_service.dart       # Wikipedia 解析
│   └── utils/                  # 工具类
├── ui/
│   ├── theme/                  # 主题配置 (玻璃拟态)
│   └── pages/
│       ├── home_page.dart      # 主页 (侧边栏导航)
│       ├── media/              # 媒体页面
│       ├── actors/             # 演员页面
│       ├── categories/         # 分类页面
│       ├── favorites/          # 收藏页面
│       ├── watched/            # 已观看页面
│       └── settings/           # 设置页面
└── fonts/                      # 自定义字体
```

## 🚀 快速开始

### 环境要求

- **Flutter SDK**: >= 3.24.0
- **Dart SDK**: >= 3.x
- **操作系统**: Windows 10/11

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

3. **运行应用**
   ```bash
   flutter run -d windows
   ```

4. **构建发布版本**
   ```bash
   flutter build windows
   ```
   可执行文件位于 `build/windows/x64/runner/Release/`

## 📂 媒体库目录结构

应用期望以下目录结构：

```
媒体库根目录/
├── #整理完成/
│   ├── 演员名/
│   │   └── [番号] 视频标题/
│   │       ├── poster.jpg      # 海报图
│   │       ├── fanart.jpg      # 背景图 (可选)
│   │       ├── movie.nfo       # 元数据文件
│   │       └── 视频文件.mp4
│   └── 演员2,演员3/             # 多演员用逗号分隔
└── Watched/                     # 已观看目录 (可自定义)
    └── ...
```

### NFO 文件格式示例

```xml
<movie>
  <title>视频标题</title>
  <actor>
    <name>演员名</name>
  </actor>
  <genre>标签1</genre>
  <set>系列名</set>
  <studio>片商名</studio>
  <plot>剧情简介</plot>
</movie>
```

## 🎨 设计特点

- **玻璃拟态 (Glassmorphism)**: 毛玻璃背景效果
- **呼吸感界面**: 流畅动画与自然过渡
- **圆润设计**: 大圆角 + 柔和阴影
- **响应式布局**: 自适应不同窗口尺寸
- **深色主题**: 护眼配色方案

## 📝 开发说明

本项目使用以下开发规范：

- 状态管理: Riverpod (`ConsumerWidget`, `ConsumerStatefulWidget`)
- 数据库: SQLite 通过 `sqflite` 操作
- 文件操作: `dart:io` + `path` 包
- 网络请求: `http` 包 (带代理支持)
- UI 组件: 高度复用的卡片、网格组件

## 📄 License

MIT License

## 🙏 致谢

- [Flutter Team](https://flutter.dev) - 跨平台框架
- [Riverpod](https://riverpod.dev) - 状态管理方案
- [gfriends](https://github.com/gfriends/gfriends) - 演员头像资源
