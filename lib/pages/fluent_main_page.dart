import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/pages/fluent_settings_page.dart';
import 'package:nipaplay/pages/fluent_dashboard_home_page.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/pages/anime_page.dart';
import 'package:nipaplay/pages/new_series_page.dart';
import 'package:nipaplay/widgets/nipaplay_theme/splash_screen.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FluentMainPage extends StatefulWidget {
  final String? launchFilePath;

  const FluentMainPage({super.key, this.launchFilePath});

  @override
  State<FluentMainPage> createState() => _FluentMainPageState();
}

class _FluentMainPageState extends State<FluentMainPage> with SingleTickerProviderStateMixin, WindowListener {
  bool isMaximized = false;
  bool _showSplash = true;
  int _selectedIndex = 0;

  // 热键管理相关变量
  VideoPlayerState? _videoPlayerState;
  bool _hotkeysAreRegistered = false;

  // 页面列表
  final List<material.Widget> _pages = [
    const FluentDashboardHomePage(),
    const PlayVideoPage(),
    const AnimePage(), 
    const NewSeriesPage(),
    const FluentSettingsPage(),
  ];

  final List<String> _pageNames = [
    '仪表盘',
    '视频播放',
    '动画',
    '新番',
    '设置',
  ];

  @override
  void initState() {
    super.initState();
    _loadStartupPage();
    
    // 隐藏启动画面
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });

    // 桌面端窗口管理
    if (globals.winLinDesktop) {
      windowManager.addListener(this);
      _checkWindowMaximizedState();
    }
    
    // 延迟监听 TabChangeNotifier，确保 Provider 已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
        tabChangeNotifier.addListener(_onTabChange);
        
        // 初始化 HotkeyService
        HotkeyService().initialize(context);
        //debugPrint('[FluentHotkeyManager] HotkeyService已初始化');
      }
    });
  }

  Future<void> _loadStartupPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedIndex = prefs.getInt('default_page_index') ?? 0;
      final clampedIndex = storedIndex.clamp(0, _pages.length - 1);
      if (!mounted) return;
      setState(() {
        _selectedIndex = clampedIndex;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final tabChangeNotifier =
            Provider.of<TabChangeNotifier>(context, listen: false);
        tabChangeNotifier.changeTab(_selectedIndex);
      });
    } catch (e) {
      debugPrint('[FluentMainPage] 加载默认页面失败: $e');
    }
  }

  @override
  void dispose() {
    // 移除 VideoPlayerState 监听器
    _videoPlayerState?.removeListener(_manageHotkeys);
    
    // 移除 TabChangeNotifier 监听器
    if (mounted) {
      try {
        final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
        tabChangeNotifier.removeListener(_onTabChange);
      } catch (e) {
        // Provider 可能已经被释放，忽略错误
      }
    }
    
    if (globals.winLinDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // 处理 TabChangeNotifier 的变化
  void _onTabChange() {
    if (mounted) {
      final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      final newIndex = tabChangeNotifier.targetTabIndex;
      if (newIndex != null && newIndex != _selectedIndex && newIndex >= 0 && newIndex < _pages.length) {
        setState(() {
          _selectedIndex = newIndex;
        });
      }
      // FluentUI主题：当标签切换时管理热键
      _manageHotkeys();
    }
  }
  
  // 热键管理方法
  void _manageHotkeys() {
    final videoState = _videoPlayerState;
    if (videoState == null || !mounted) {
      //debugPrint('[FluentHotkeyManager] 跳过热键管理: videoState=${videoState != null}, mounted=$mounted');
      return;
    }

    // FluentUI主题：检查是否在视频播放页面（索引1）且有视频
    final shouldBeRegistered = _selectedIndex == 1 && videoState.hasVideo;
    
    //debugPrint('[FluentHotkeyManager] FluentUI主题: selectedIndex=$_selectedIndex, hasVideo=${videoState.hasVideo}, shouldBeRegistered=$shouldBeRegistered');
    //debugPrint('[FluentHotkeyManager] 最终判断: shouldBeRegistered=$shouldBeRegistered, currentlyRegistered=$_hotkeysAreRegistered');

    if (shouldBeRegistered && !_hotkeysAreRegistered) {
      //debugPrint('[FluentHotkeyManager] 开始注册热键...');
      HotkeyService().registerHotkeys().then((_) {
        _hotkeysAreRegistered = true;
        //debugPrint('[FluentHotkeyManager] 热键注册完成');
      }).catchError((e) {
        //debugPrint('[FluentHotkeyManager] 热键注册失败: $e');
      });
    } else if (!shouldBeRegistered && _hotkeysAreRegistered) {
      //debugPrint('[FluentHotkeyManager] 开始注销热键...');
      HotkeyService().unregisterHotkeys().then((_) {
        _hotkeysAreRegistered = false;
        //debugPrint('[FluentHotkeyManager] 热键注销完成');
      }).catchError((e) {
        //debugPrint('[FluentHotkeyManager] 热键注销失败: $e');
      });
    } else {
      //debugPrint('[FluentHotkeyManager] 无需更改热键状态');
    }
  }

  // 检查窗口是否已最大化
  Future<void> _checkWindowMaximizedState() async {
    if (globals.winLinDesktop) {
      final maximized = await windowManager.isMaximized();
      if (maximized != isMaximized) {
        setState(() {
          isMaximized = maximized;
        });
      }
    }
  }

  // 切换窗口大小
  void _toggleWindowSize() async {
    if (globals.winLinDesktop) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    }
  }

  void _minimizeWindow() async {
    await windowManager.minimize();
  }

  void _closeWindow() async {
    await windowManager.close();
  }

  // WindowListener回调
  @override
  void onWindowMaximize() {
    setState(() {
      isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      isMaximized = false;
    });
  }

  @override
  void onWindowResize() {
    _checkWindowMaximizedState();
  }

  @override
  void onWindowEvent(String eventName) {
    // 监听所有窗口事件
  }

  @override
  Widget build(BuildContext context) {
    return material.Stack(
      children: [
        // 主要内容区域
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            // 设置VideoPlayerState监听器
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_videoPlayerState != videoState) {
                _videoPlayerState?.removeListener(_manageHotkeys);
                _videoPlayerState = videoState;
                _videoPlayerState?.addListener(_manageHotkeys);
                //debugPrint('[FluentHotkeyManager] VideoPlayerState监听器已设置');
                _manageHotkeys(); // 初始状态检查
              }
            });
            
            return NavigationView(
          appBar: NavigationAppBar(
            title: Text(_pageNames[_selectedIndex]),
            automaticallyImplyLeading: false,
            actions: globals.winLinDesktop ? 
              material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.IconButton(
                    onPressed: _minimizeWindow,
                    icon: const Icon(FluentIcons.chrome_minimize),
                    iconSize: 16,
                  ),
                  material.IconButton(
                    onPressed: _toggleWindowSize,
                    icon: Icon(isMaximized ? FluentIcons.chrome_restore : FluentIcons.checkbox_composite),
                    iconSize: 16,
                  ),
                  material.IconButton(
                    onPressed: _closeWindow,
                    icon: const Icon(FluentIcons.chrome_close),
                    iconSize: 16,
                  ),
                ],
              ) : null,
          ),
          pane: NavigationPane(
            selected: _selectedIndex,
            onChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
              // 同步更新 TabChangeNotifier
              final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
              tabChangeNotifier.changeTab(index);
            },
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.home),
                title: const Text('仪表盘'),
                body: _pages[0],
              ),
              PaneItem(
                icon: const Icon(FluentIcons.play),
                title: const Text('视频播放'),
                body: _pages[1],
              ),
              PaneItem(
                icon: const Icon(FluentIcons.video),
                title: const Text('动画'),
                body: _pages[2],
              ),
              PaneItem(
                icon: const Icon(FluentIcons.new_folder),
                title: const Text('新番'),
                body: _pages[3],
              ),
              PaneItem(
                icon: const Icon(FluentIcons.settings),
                title: const Text('设置'),
                body: _pages[4],
              ),
            ],
          ),
            );
          },
        ),
        
        // 启动画面
        material.AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (material.Widget child, material.Animation<double> animation) {
            return material.FadeTransition(opacity: animation, child: child);
          },
          child: _showSplash
              ? const SplashScreen(key: material.ValueKey('splash'))
              : const material.SizedBox.shrink(key: material.ValueKey('no_splash')),
        ),
        
        // 可拖拽区域 (桌面端)
        if (globals.winLinDesktop)
          material.Positioned(
            top: 0,
            left: 0,
            right: 120,
            child: material.SizedBox(
              height: 40,
              child: material.GestureDetector(
                onDoubleTap: _toggleWindowSize,
                onPanStart: (details) async {
                  await windowManager.startDragging();
                },
              ),
            ),
          ),
      ],
    );
  }
}
