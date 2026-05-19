# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
