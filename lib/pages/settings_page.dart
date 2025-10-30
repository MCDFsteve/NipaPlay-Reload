// settings_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/pages/settings/theme_mode_page.dart'; // 导入 ThemeModePage
import 'package:nipaplay/pages/settings/general_page.dart';
import 'package:nipaplay/pages/settings/developer_options_page.dart'; // 导入开发者选项页面
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/widgets/nipaplay_theme/custom_scaffold.dart';
import 'package:nipaplay/widgets/nipaplay_theme/responsive_container.dart'; // 导入响应式容器
import 'package:nipaplay/pages/settings/about_page.dart'; // 导入 AboutPage
import 'package:nipaplay/utils/globals.dart'
    as globals; // 导入包含 isDesktop 的全局变量文件
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/pages/settings/account_page.dart';
import 'package:nipaplay/pages/settings/player_settings_page.dart'; // 导入播放器设置页面
import 'package:nipaplay/pages/settings/remote_media_library_page.dart'; // 导入远程媒体库设置页面
import 'package:nipaplay/pages/settings/remote_access_page.dart'; // 导入远程访问设置页面
import 'package:nipaplay/pages/settings/ui_theme_page.dart'; // 导入UI主题设置页面
import 'package:nipaplay/pages/settings/watch_history_page.dart';
import 'package:nipaplay/pages/settings/backup_restore_page.dart';
import 'package:nipaplay/pages/settings/network_settings_page.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  // currentPage 状态现在用于桌面端的右侧面板
  // 也可以考虑给它一个初始值，这样桌面端一进来右侧不是空的
  Widget? currentPage; // 初始可以为 null
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 初始化TabController
    _tabController = TabController(length: 1, vsync: this);

    // 可以在这里为桌面端和平板设备设置一个默认显示的页面
    if (globals.isDesktop || globals.isTablet) {
      currentPage = const AboutPage(); // 例如默认显示 AboutPage
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 封装导航或更新状态的逻辑
  void _handleItemTap(Widget pageToShow, String title) {
    List<Widget> settingsTabLabels() {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ];
    }

    final List<Widget> pages = [pageToShow];
    if (globals.isDesktop || globals.isTablet) {
      // 桌面端和平板设备：更新状态，改变右侧面板内容
      setState(() {
        currentPage = pageToShow;
      });
    } else {
      // 移动端：导航到新页面
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CustomScaffold(
                  pages: pages,
                  tabPage: settingsTabLabels(),
                  pageIsHome: false,
                  tabController: _tabController,
                )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = [
      _buildNavTile(
        context,
        title: '账号',
        onTap: () => _handleItemTap(const AccountPage(), '账号设置'),
      ),
      _buildNavTile(
        context,
        title: '外观',
        onTap: () {
          final themeNotifier = context.read<ThemeNotifier>();
          _handleItemTap(
            ThemeModePage(themeNotifier: themeNotifier),
            '外观设置',
          );
        },
      ),
    ];

    if (!Platform.isAndroid) {
      tiles.add(
        _buildNavTile(
          context,
          title: '主题（实验性）',
          onTap: () => _handleItemTap(const UIThemePage(), '主题设置'),
        ),
      );
    }

    tiles.addAll([
      _buildNavTile(
        context,
        title: '通用',
        onTap: () => _handleItemTap(const GeneralPage(), '通用设置'),
      ),
      _buildNavTile(
        context,
        title: '网络',
        onTap: () => _handleItemTap(const NetworkSettingsPage(), '网络设置'),
      ),
      _buildNavTile(
        context,
        title: '观看记录',
        onTap: () => _handleItemTap(const WatchHistoryPage(), '观看记录'),
      ),
      _buildNavTile(
        context,
        title: '播放器',
        onTap: () => _handleItemTap(const PlayerSettingsPage(), '播放器设置'),
      ),
    ]);

    if (!globals.isPhone) {
      tiles.addAll([
        _buildNavTile(
          context,
          title: '备份与恢复',
          onTap: () => _handleItemTap(const BackupRestorePage(), '备份与恢复'),
        ),
        _buildNavTile(
          context,
          title: '快捷键',
          onTap: () => _handleItemTap(const ShortcutsSettingsPage(), '快捷键设置'),
        ),
        _buildNavTile(
          context,
          title: '远程访问（实验性）',
          onTap: () => _handleItemTap(const RemoteAccessPage(), '远程访问'),
        ),
      ]);
    }

    tiles.addAll([
      _buildNavTile(
        context,
        title: '远程媒体库',
        onTap: () => _handleItemTap(const RemoteMediaLibraryPage(), '远程媒体库'),
      ),
      _buildNavTile(
        context,
        title: '关于',
        onTap: () => _handleItemTap(const AboutPage(), '关于NipaPlay'),
      ),
    ]);

    if (globals.isDesktop || globals.isTablet) {
      tiles.add(
        _buildNavTile(
          context,
          title: '开发者选项',
          onTap: () => _handleItemTap(const DeveloperOptionsPage(), '开发者选项'),
        ),
      );
    }

    return ResponsiveContainer(
      currentPage: currentPage ?? Container(),
      child: ListView(children: tiles),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final colors = context.nipaplayColors;
    final iconColor = enabled
        ? colors.iconSecondary
        : colors.iconSecondary.withOpacity(0.4);

    return ListTile(
      enabled: enabled,
      title: Text(
        title,
        locale: const Locale('zh-Hans', 'zh'),
        style: TextStyle(
          color: enabled ? colors.textPrimary : colors.textMuted,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: Icon(
        Ionicons.chevron_forward_outline,
        color: iconColor,
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
