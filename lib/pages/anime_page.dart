import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/widgets/fluent_ui/fluent_history_all_dialog.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_media_library_tabs.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/widgets/nipaplay_theme/loading_overlay.dart';
import 'package:nipaplay/widgets/nipaplay_theme/loading_placeholder.dart';
import '../providers/watch_history_provider.dart';
import '../providers/appearance_settings_provider.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/widgets/nipaplay_theme/library_management_tab.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/history_all_modal.dart';
import 'package:nipaplay/widgets/nipaplay_theme/switchable_view.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_library_view.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_library_view.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

// Custom ScrollBehavior for NoScrollbarBehavior is removed as NestedScrollView handles scrolling differently.

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> with WidgetsBindingObserver {
  final bool _loadingVideo = false;
  final List<String> _loadingMessages = ['正在初始化播放器...'];
  VideoPlayerState? _videoPlayerState;
  final ScrollController _mainPageScrollController = ScrollController(); // Used for NestedScrollView
  final ScrollController _watchHistoryListScrollController = ScrollController();
  
  // 仅保留当前标签页索引用于初始化_MediaLibraryTabs
  final int _currentTabIndex = 0;

  final int _mediaLibraryVersion = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
    _setupThumbnailUpdateListener();
  }

  void _setupThumbnailUpdateListener() {
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.addThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {
      //debugPrint('设置缩略图更新监听器时出错: $e');
    }
  }

  void _onThumbnailUpdated() {
    if (!mounted) return;
    // 不再清理所有图片缓存，避免影响番剧卡片的封面显示
    // 只触发UI重建来显示新的缩略图
    setState(() {
      // 触发UI重建，让新的缩略图能够显示
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.removeThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {}
    _mainPageScrollController.dispose();
    _watchHistoryListScrollController.dispose();
    super.dispose();
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    debugPrint('[AnimePage] _onWatchHistoryItemTap: Received item: $item');

    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
      if (isEmbyProtocol) {
        try {
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      if (!kIsWeb) {
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          item = item.copyWith(filePath: filePath);
          fileExists = true;
        }
      }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        return Builder(
          builder: (context) {
            final scanService = Provider.of<ScanService>(context);

            // 移除DefaultTabController，直接使用Stack
            return Stack(
              children: [
                NestedScrollView(
                  controller: _mainPageScrollController,
                  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                    ];
                  },
                  body: Builder(
                    builder: (context) {
                      final uiThemeProvider = Provider.of<UIThemeProvider>(context);
                      if (uiThemeProvider.isFluentUITheme) {
                        return FluentMediaLibraryTabs(
                          initialIndex: _currentTabIndex,
                          onPlayEpisode: _onWatchHistoryItemTap,
                          mediaLibraryVersion: _mediaLibraryVersion,
                        );
                      }
                      return _MediaLibraryTabs(
                        initialIndex: _currentTabIndex,
                        onPlayEpisode: _onWatchHistoryItemTap,
                        mediaLibraryVersion: _mediaLibraryVersion,
                      );
                    },
                  ),
                ),
                if (_loadingVideo)
                  Positioned.fill(
                    child: LoadingOverlay(
                      messages: _loadingMessages,
                      animeTitle: null,
                      episodeTitle: null,
                      fileName: null,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// 在文件末尾添加新的类用于管理媒体库标签页
class _MediaLibraryTabs extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<WatchHistoryItem> onPlayEpisode;
  final int mediaLibraryVersion;

  const _MediaLibraryTabs({
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  });

  @override
  State<_MediaLibraryTabs> createState() => _MediaLibraryTabsState();
}

class _MediaLibraryTabsState extends State<_MediaLibraryTabs> with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  bool _isJellyfinConnected = false;
  bool _isEmbyConnected = false;
  bool _hasSharedRemoteHosts = false;
  
  // 动态计算标签页数量
  int get _tabCount {
    int count = 2; // 基础标签: 媒体库, 库管理
    if (_hasSharedRemoteHosts) count++;
    if (_isJellyfinConnected) count++;
    if (_isEmbyConnected) count++;
    return count;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _checkConnectionStates();
    _tabController = TabController(
      length: _tabCount, 
      vsync: this, 
      initialIndex: _currentIndex
    );
    _tabController.addListener(_handleTabChange);
    
    // 监听子标签切换通知
    _setupSubTabListener();
    
    // 立即检查是否有待处理的子标签切换请求
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingSubTabChange();
    });
    
    print('_MediaLibraryTabs创建TabController：动态长度${_tabController.length}');
  }

  void _checkConnectionStates() {
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final sharedProvider = Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
    _isJellyfinConnected = jellyfinProvider.isConnected;
    _isEmbyConnected = embyProvider.isConnected;
    _hasSharedRemoteHosts = sharedProvider.hasReachableActiveHost;
    print('_MediaLibraryTabs: 连接状态检查 - Jellyfin: $_isJellyfinConnected, Emby: $_isEmbyConnected');
  }

  TabChangeNotifier? _tabChangeNotifierRef;

  void _setupSubTabListener() {
    try {
      _tabChangeNotifierRef = Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifierRef?.addListener(_onSubTabChangeRequested);
      debugPrint('[_MediaLibraryTabs] 已设置子标签切换监听器');
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 设置子标签切换监听器失败: $e');
    }
  }

  void _onSubTabChangeRequested() {
    try {
      final subTabIndex = _tabChangeNotifierRef?.targetMediaLibrarySubTabIndex;
      
      if (subTabIndex != null && subTabIndex != _currentIndex) {
        debugPrint('[_MediaLibraryTabs] 接收到子标签切换请求: $subTabIndex');
        
        // 确保索引在有效范围内
        if (subTabIndex >= 0 && subTabIndex < _tabCount) {
          _tabController.animateTo(subTabIndex);
          debugPrint('[_MediaLibraryTabs] 已切换到子标签: $subTabIndex');
          
          // 清除切换请求
          _tabChangeNotifierRef?.clearSubTabIndex();
        } else {
          debugPrint('[_MediaLibraryTabs] 子标签索引超出范围: $subTabIndex (最大: ${_tabCount - 1})');
        }
      }
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 处理子标签切换请求失败: $e');
    }
  }

  void _checkPendingSubTabChange() {
    try {
      final subTabIndex = _tabChangeNotifierRef?.targetMediaLibrarySubTabIndex;
      
      if (subTabIndex != null && subTabIndex != _currentIndex) {
        debugPrint('[_MediaLibraryTabs] 发现待处理的子标签切换请求: $subTabIndex');
        
        // 确保索引在有效范围内
        if (subTabIndex >= 0 && subTabIndex < _tabCount) {
          _tabController.animateTo(subTabIndex);
          debugPrint('[_MediaLibraryTabs] 执行待处理的子标签切换: $subTabIndex');
          
          // 清除切换请求
          _tabChangeNotifierRef?.clearSubTabIndex();
        } else {
          debugPrint('[_MediaLibraryTabs] 待处理子标签索引超出范围: $subTabIndex (最大: ${_tabCount - 1})');
        }
      } else {
        debugPrint('[_MediaLibraryTabs] 无待处理的子标签切换请求');
      }
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 检查待处理子标签切换请求失败: $e');
    }
  }

  @override
  void dispose() {
    //debugPrint('[CPU-泄漏排查] _MediaLibraryTabsState dispose 被调用');
    _tabController.removeListener(_handleTabChange);
    
    // 移除子标签切换监听器，使用缓存的引用避免访问已销毁的context
    try {
      _tabChangeNotifierRef?.removeListener(_onSubTabChangeRequested);
      _tabChangeNotifierRef = null;
      debugPrint('[_MediaLibraryTabs] 已移除子标签切换监听器');
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 移除子标签切换监听器失败: $e');
    }
    
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    //debugPrint('[CPU-泄漏排查] TabController索引变化: ${_tabController.index}，indexIsChanging: ${_tabController.indexIsChanging}');
    if (!_tabController.indexIsChanging) return;
    
    if (_currentIndex != _tabController.index) {
      setState(() {
        _currentIndex = _tabController.index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    
    return Consumer3<JellyfinProvider, EmbyProvider, SharedRemoteLibraryProvider>(
      builder: (context, jellyfinProvider, embyProvider, sharedProvider, child) {
        final currentJellyfinConnectionState = jellyfinProvider.isConnected;
        final currentEmbyConnectionState = embyProvider.isConnected;
        final currentSharedState = sharedProvider.hasReachableActiveHost;
        
        // 检查连接状态是否改变
        if (_isJellyfinConnected != currentJellyfinConnectionState || 
            _isEmbyConnected != currentEmbyConnectionState ||
            _hasSharedRemoteHosts != currentSharedState) {
          print('_MediaLibraryTabs: 连接状态发生变化 - Jellyfin: $_isJellyfinConnected -> $currentJellyfinConnectionState, Emby: $_isEmbyConnected -> $currentEmbyConnectionState, Shared: $_hasSharedRemoteHosts -> $currentSharedState');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _updateTabController(currentJellyfinConnectionState, currentEmbyConnectionState, currentSharedState);
            }
          });
        }
        
        // 动态生成标签页内容
        final List<Widget> pageChildren = [
          RepaintBoundary(
            child: MediaLibraryPage(
              key: ValueKey('mediaLibrary_${widget.mediaLibraryVersion}'),
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
          RepaintBoundary(
            child: LibraryManagementTab(
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
        ];
        
        if (currentSharedState) {
          pageChildren.add(
            RepaintBoundary(
              child: SharedRemoteLibraryView(
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }

        if (_isJellyfinConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: NetworkMediaLibraryView(
                serverType: NetworkMediaServerType.jellyfin,
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }
        
        if (_isEmbyConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: NetworkMediaLibraryView(
                serverType: NetworkMediaServerType.emby,
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }
        
        // 动态生成标签
        final List<Tab> tabs = [
          const Tab(text: "本地媒体库"),
          const Tab(text: "库管理"),
        ];
        
        if (currentSharedState) {
          tabs.add(const Tab(text: "共享媒体"));
        }

        if (_isJellyfinConnected) {
          tabs.add(const Tab(text: "Jellyfin"));
        }
        
        if (_isEmbyConnected) {
          tabs.add(const Tab(text: "Emby"));
        }
        
        // 验证标签数量与内容数量是否匹配
        if (tabs.length != pageChildren.length || tabs.length != _tabCount) {
          print('警告：标签数量(${tabs.length})、内容数量(${pageChildren.length})与预期数量($_tabCount)不匹配');
        }
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // 检查可用高度，如果太小则使用最小安全布局
            final availableHeight = constraints.maxHeight;
            final isHeightConstrained = availableHeight < 100; // 小于100像素视为高度受限
            
            if (isHeightConstrained) {
              // 高度受限时，使用简化布局避免溢出
              return SizedBox(
                height: availableHeight,
                child: const Center(
                  child: Text(
                    '布局空间不足',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              );
            }
            
            return Column(
              children: [
                // TabBar - 使用Flexible包装以防溢出
                Flexible(
                  flex: 0,
                  child: Builder(
                    builder: (context) {
                      final colors = context.nipaplayColors;
                      return TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabs: tabs,
                        labelColor: colors.textPrimary,
                        unselectedLabelColor: colors.textSecondary,
                        labelStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        indicatorPadding: const EdgeInsets.only(
                          top: 45,
                          left: 0,
                          right: 0,
                        ),
                        indicator: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        tabAlignment: TabAlignment.start,
                        dividerColor: colors.divider,
                        dividerHeight: 3.0,
                        indicatorSize: TabBarIndicatorSize.tab,
                      );
                    },
                  ),
                ),
                // 内容区域 - 确保占用剩余所有空间
                Expanded(
                  child: SwitchableView(
                    enableAnimation: false, // 🔥 CPU优化：强制禁用媒体库内部动画，避免TabBarView同时渲染所有页面
                    currentIndex: _currentIndex,
                    controller: _tabController,
                    physics: enableAnimation 
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      if (_currentIndex != index) {
                        setState(() {
                          _currentIndex = index;
                        });
                        _tabController.animateTo(index);
                        print('页面变更到: $index (启用动画: $enableAnimation)');
                      }
                    },
                    children: pageChildren,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _updateTabController(bool isJellyfinConnected, bool isEmbyConnected, bool hasSharedHosts) {
    if (_isJellyfinConnected == isJellyfinConnected &&
        _isEmbyConnected == isEmbyConnected &&
        _hasSharedRemoteHosts == hasSharedHosts) {
      return;
    }
    
    final oldIndex = _currentIndex;
    _isJellyfinConnected = isJellyfinConnected;
    _isEmbyConnected = isEmbyConnected;
    _hasSharedRemoteHosts = hasSharedHosts;
    
    // 创建新的TabController
    final newController = TabController(
      length: _tabCount, 
      vsync: this, 
      initialIndex: oldIndex >= _tabCount ? 0 : oldIndex
    );
    
    // 移除旧监听器并释放资源
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    
    // 更新到新的控制器
    _tabController = newController;
    _tabController.addListener(_handleTabChange);
    
    // 调整当前索引
    if (_currentIndex >= _tabCount) {
      _currentIndex = 0;
    }
    
    setState(() {
      // 触发重建以使用新的TabController
    });
    
    print('TabController已更新：新长度=$_tabCount, 当前索引=$_currentIndex');
  }
}

// 鼠标拖动滚动包装器
class _MouseDragScrollWrapper extends StatefulWidget {
  final ScrollController scrollController;
  final Widget child;

  const _MouseDragScrollWrapper({
    required this.scrollController,
    required this.child,
  });

  @override
  State<_MouseDragScrollWrapper> createState() => _MouseDragScrollWrapperState();
}

class _MouseDragScrollWrapperState extends State<_MouseDragScrollWrapper> {
  bool _isDragging = false;
  double _lastPanPosition = 0.0;
  
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // 只响应鼠标左键
        if (event.buttons == 1) {
          _isDragging = true;
          _lastPanPosition = event.position.dx;
        }
      },
      onPointerMove: (PointerMoveEvent event) {
        if (_isDragging && widget.scrollController.hasClients) {
          final double delta = _lastPanPosition - event.position.dx;
          _lastPanPosition = event.position.dx;
          
          // 计算新的滚动位置
          final double newScrollOffset = widget.scrollController.offset + delta;
          
          // 限制滚动范围
          final double maxScrollExtent = widget.scrollController.position.maxScrollExtent;
          final double minScrollExtent = widget.scrollController.position.minScrollExtent;
          
          final double clampedOffset = newScrollOffset.clamp(minScrollExtent, maxScrollExtent);
          
          // 应用滚动
          widget.scrollController.jumpTo(clampedOffset);
        }
      },
      onPointerUp: (PointerUpEvent event) {
        _isDragging = false;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _isDragging = false;
      },
      child: MouseRegion(
        cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: widget.child,
      ),
    );
  }
}
