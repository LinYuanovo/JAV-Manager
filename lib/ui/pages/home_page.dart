import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../theme/app_theme.dart';
import '../controllers/window_controller.dart';
import '../controllers/sidebar_controller.dart';
import '../widgets/title_bar_widget.dart';
import '../widgets/sidebar_widget.dart';
import 'app_router.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final WindowController _windowController;
  late final SidebarController _sidebarController;

  @override
  void initState() {
    super.initState();
    _windowController = WindowController(ref.read(sharedPreferencesProvider));
    _sidebarController = SidebarController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _windowController.initialize();

      final taskEventListener = ref.read(taskEventListenerProvider);
      await taskEventListener.initialize();

      ref.read(mediaCountServiceProvider).syncMediaCount();
    });
  }

  @override
  void dispose() {
    _windowController.dispose();
    _sidebarController.dispose();
    ref.read(taskEventListenerProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedNavIndexProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          TitleBarWidget(windowController: _windowController),
          Expanded(
            child: Row(
              children: [
                SidebarWidget(
                  controller: _sidebarController,
                  selectedIndex: selectedIndex,
                ),
                Expanded(
                  child: AppRouter.getCurrentPage(selectedIndex),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
