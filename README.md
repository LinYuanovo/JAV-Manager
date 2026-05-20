<h1 align="center"><img src="app_icon.png" alt="JAV-Manager" width="80" height="80" align="middle"> &nbsp;JAV-Manager</h1>

<p align="center">
  <nobr>
    <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
    <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
    <img src="https://img.shields.io/badge/Version-1.3.0-blue?style=flat-square" alt="Version">
  </nobr>
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地视频媒体管理器</b><br>
  <i>现代化 UI · 玻璃拟态设计 · 智能整理 · 纯净模式</i>
</p>

***

## 🚀 快速开始

### 环境要求

<details>
<summary>点击展开查看环境要求</summary>

- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5
- **操作系统**: Windows 10/11 (64位)
- **内存**: 建议 8GB+
- **磁盘空间**: 2GB+ (用于构建)

</details>

### 安装步骤

#### 直接使用

Windows系统在[releases](https://github.com/LinYuanovo/JAV-Manager/releases)页面直接下载zip压缩包后**解压**即可使用

#### 自行构建

<details>
<summary>点击展开查看自行构建方式</summary>

```bash
# 克隆仓库
git clone https://github.com/LinYuanovo/JAV-Manager.git
cd JAV-Manager

# 安装依赖
flutter pub get

# 运行应用（开发模式）
flutter run -d windows

# 构建发布版本
flutter build windows --release
```

可执行文件位于：
```
build/windows/x64/runner/Release/jav_manager.exe
```

</details>

## 📂 媒体库目录结构

应用期望以下目录结构（[如何得到？JavSP刮削](https://github.com/Yuukiy/JavSP)）来正确识别和管理视频：

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

<details>
<summary>点击展开查看NFO 文件格式示例</summary>

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

</details>

## ✨ 功能特性

### 📺 媒体管理

- **多种视图模式**：列表 / 海报 / 海报+标题 / 海报墙
- **灵活排序**：标题、随机、最近观看
- **自适应网格布局**，支持固定列数
- **手动/自动扫描**媒体库，实时更新
- **纯净模式**：仅显示番号，海报图马赛克处理

<figure class="half">
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/media_page.png" title="media_page"/> 
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/video_detail_page.png" title="video_detail_page"/> 
</figure>

### 👤 演员管理

- **NFO 自动解析**：从 NFO 文件提取演员信息
- **在线头像获取**：通过 gfriends 仓库获取演员头像
- **详细信息**：Wikipedia 解析演员资料（生日、身高、三围等）
- **批量操作**：支持一键获取所有演员的头像和信息

<figure class="half">
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/actors_page.png" title="actors_page"/> 
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/actor_detail_page.png" title="actor_detail_page"/> 
</figure>

### 🏷️ 分类系统

- **多类型分类**：按标签、系列、片商进行分类

<figure class="half">
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/categories_page.png" title="categories_page"/> 
  <img src="https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/category_detail_page.png" title="category_detail_page"/> 
</figure>

### ❤️ 收藏功能

- **多类型收藏**：影片、演员、分类均可收藏
- **独立收藏页面**：支持搜索、排序

![favorites_page](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/favorites_page.png)

### 📋 已观看追踪

- **观看记录**：记录观看次数和最后观看时间
- **自动整理**：将已观看视频移动到指定目录（安全移动防数据丢失）
- **智能标记**：自动标记观看状态，媒体库不再显示已观看内容

![watched_page](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/JAV-Manager/watched_page.png)

## 🛠️ 技术栈

| 技术 | 版本 | 用途 |
| --- | --- | --- |
| [Flutter](https://flutter.dev) | 3.41.9 | 跨平台 UI 框架 |
| [Dart](https://dart.dev) | 3.11.5 | 编程语言 |
| [Riverpod](https://riverpod.dev) | ^2.4.9 | 状态管理 |
| [SQLite](https://www.sqlite.org) | via sqflite | 本地数据存储 |
| [window\_manager](https://pub.dev/packages/window_manager) | ^0.3.7 | 窗口管理（尺寸、位置、状态持久化） |
| [http](https://pub.dev/packages/http) | ^1.1.0 | HTTP 客户端（代理支持） |

## 📁 项目结构

<details>
<summary>📂 点击展开查看完整目录结构</summary>

```
JAV-Manager/
├── lib/                          # 应用源代码
│   ├── main.dart                 # 应用入口
│   ├── core/                     # 核心业务逻辑
│   │   ├── database/             # 数据库层
│   │   ├── models/               # 数据模型
│   │   ├── providers/            # Riverpod 状态管理
│   │   ├── repositories/         # 数据访问层
│   │   ├── services/             # 业务服务
│   │   └── utils/                # 工具类
│   └── ui/                       # 用户界面
│       ├── theme/                # 主题配置
│       ├── widgets/              # 共享组件
│       └── pages/                # 页面模块
├── windows/                      # Windows 平台代码
├── fonts/                        # 自定义字体
├── prompt/                       # 项目文档
├── .github/workflows/            # CI/CD 配置
├── app_icon.png                  # 应用图标
├── CHANGELOG.md                  # 版本日志
├── README.md                     # 说明文档
├── pubspec.yaml                  # 项目配置
└── pubspec.lock                  # 依赖锁定
```

</details>

## 🙏 致谢

- [gfriends](https://github.com/gfriends/gfriends) - 演员头像资源仓库
- [JavSP](https://github.com/Yuukiy/JavSP) - 元数据刮削器
- [VideoCaptioner](https://github.com/WEIFENG2333/VideoCaptioner) - 视频字幕处理工具
