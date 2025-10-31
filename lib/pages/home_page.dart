import 'package:flutter/material.dart';
import 'package:nipaplay/pages/new_series_page.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';
// ... other imports ...

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 懒加载观看记录
    Future.microtask(() {
      final provider = context.read<WatchHistoryProvider>();
      provider.loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBackground = ThemeColorUtils.overlayColor(
      context,
      darkOpacity: 0.3,
      lightOpacity: 0.06,
    );
    final contentBackground = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: scaffoldBackground,
      body: Row(
        children: [
          // ... sidebar ...
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: contentBackground),
              child: IndexedStack(
                index: 0, // 固定显示第一个页面
                children: const [
                  NewSeriesPage(),
                  // ... other pages ...
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
