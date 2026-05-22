import 'package:flutter/material.dart';
import 'media/media_page.dart';
import 'actors/actors_page.dart';
import 'categories/categories_page.dart';
import 'favorites/favorites_page.dart';
import 'watched/watched_page.dart';
import 'settings/settings_page.dart';
import 'scraper/scraper_page.dart';

/// 页面路由枚举，集中定义所有导航项及其对应的页面
enum NavRoute {
  scraper(0, '刮削', Icons.cloud_download_outlined, Icons.cloud_download),
  media(1, '媒体', Icons.movie_outlined, Icons.movie),
  actors(2, '演员', Icons.people_outline, Icons.people),
  categories(3, '分类', Icons.category_outlined, Icons.category),
  favorites(4, '收藏', Icons.favorite_outline, Icons.favorite),
  watched(5, '已看', Icons.visibility_outlined, Icons.visibility),
  settings(6, '设置', Icons.settings_outlined, Icons.settings);

  final int navIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavRoute(this.navIndex, this.label, this.icon, this.selectedIcon);

  /// 根据索引获取路由，默认返回媒体页
  static NavRoute fromIndex(int index) {
    return NavRoute.values.firstWhere(
      (route) => route.navIndex == index,
      orElse: () => NavRoute.media,
    );
  }

  /// 构建对应的页面组件
  Widget buildPage() {
    switch (this) {
      case NavRoute.scraper:
        return const ScraperPage();
      case NavRoute.media:
        return const MediaPage();
      case NavRoute.actors:
        return const ActorsPage();
      case NavRoute.categories:
        return const CategoriesPage();
      case NavRoute.favorites:
        return const FavoritesPage();
      case NavRoute.watched:
        return const WatchedPage();
      case NavRoute.settings:
        return const SettingsPage();
    }
  }

  /// 获取侧边栏显示顺序：设置放最底部
  static List<NavRoute> get sidebarOrder {
    final routes = NavRoute.values.where((r) => r != NavRoute.settings).toList();
    routes.add(NavRoute.settings);
    return routes;
  }
}

/// 应用路由管理器
class AppRouter {
  /// 获取当前索引对应的页面
  static Widget getCurrentPage(int selectedIndex) {
    return NavRoute.fromIndex(selectedIndex).buildPage();
  }

  /// 获取所有路由配置
  static List<NavRoute> getAllRoutes() => NavRoute.values;
}
