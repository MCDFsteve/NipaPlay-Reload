import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/main.dart'; // 用于MainPageState
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';

class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key});

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage>
    with AutomaticKeepAliveClientMixin {
  // 持有Provider实例引用，确保在dispose中能正确移除监听器
  JellyfinProvider? _jellyfinProviderRef;
  EmbyProvider? _embyProviderRef;
  WatchHistoryProvider? _watchHistoryProviderRef;
  ScanService? _scanServiceRef;
  VideoPlayerState? _videoPlayerStateRef;
  // Provider ready 回调引用，便于移除
  VoidCallback? _jellyfinProviderReadyListener;
  VoidCallback? _embyProviderReadyListener;
  // 按服务粒度的监听开关
  bool _jellyfinLiveListening = false;
  bool _embyLiveListening = false;
  // Provider 通知后的轻量防抖（覆盖库选择等状态变化）
  Timer? _jfDebounceTimer;
  Timer? _emDebounceTimer;
  
  
  @override
  bool get wantKeepAlive => true;

  // 推荐内容数据
  List<RecommendedItem> _recommendedItems = [];
  bool _isLoadingRecommended = false;
  
  // 待处理的刷新请求
  bool _pendingRefreshAfterLoad = false;
  String _pendingRefreshReason = '';

  // 播放器状态追踪，用于检测退出播放器时触发刷新
  bool _wasPlayerActive = false;
  Timer? _playerStateCheckTimer;
  
  // 播放器状态缓存，减少频繁的Provider查询
  bool _cachedPlayerActiveState = false;
  DateTime _lastPlayerStateCheck = DateTime.now();

  // 移除老的图片缓存系统，现在使用 CachedNetworkImageWidget

  // 最近添加数据 - 按媒体库分类
  Map<String, List<JellyfinMediaItem>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<EmbyMediaItem>> _recentEmbyItemsByLibrary = {};
  
  // 本地媒体库数据 - 使用番组信息而不是观看历史
  List<LocalAnimeItem> _localAnimeItems = [];
  // 本地媒体库图片持久化缓存（与 MediaLibraryPage 复用同一前缀）
  final Map<int, String> _localImageCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';
  bool _isLoadingLocalImages = false;

  final PageController _heroBannerPageController = PageController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _continueWatchingScrollController = ScrollController();
  final ScrollController _recentJellyfinScrollController = ScrollController();
  final ScrollController _recentEmbyScrollController = ScrollController();
  
  // 动态媒体库的ScrollController映射
  final Map<String, ScrollController> _jellyfinLibraryScrollControllers = {};
  final Map<String, ScrollController> _embyLibraryScrollControllers = {};
  ScrollController? _localLibraryScrollController;
  
  // 自动切换相关
  Timer? _autoSwitchTimer;
  bool _isAutoSwitching = true;
  int _currentHeroBannerIndex = 0;
  late final ValueNotifier<int> _heroBannerIndexNotifier;
  int? _hoveredIndicatorIndex;

  // 缓存映射，用于存储已绘制的缩略图和最后绘制时间
  final Map<String, Map<String, dynamic>> _thumbnailCache = {};

  // 追踪已绘制的文件路径
  // ignore: unused_field
  final Set<String> _renderedThumbnailPaths = {};

  // 静态变量，用于缓存推荐内容
  static List<RecommendedItem> _cachedRecommendedItems = [];
  static DateTime? _lastRecommendedLoadTime;
  // 最近一次数据加载时间，用于合并短时间内的重复触发
  DateTime? _lastLoadTime;

  @override
  void initState() {
    super.initState();
    _heroBannerIndexNotifier = ValueNotifier(0);
    
    // 🔥 修复Flutter状态错误：将数据加载移到addPostFrameCallback中
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupProviderListeners();
      _startAutoSwitch();
      
      // 🔥 在build完成后安全地加载数据，避免setState during build错误
      if (mounted) {
        _loadData();
      }
      
      // 延迟检查WatchHistoryProvider状态，如果已经加载完成但数据为空则重新加载
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
          if (watchHistoryProvider.isLoaded && _localAnimeItems.isEmpty && _recommendedItems.length <= 7) {
            debugPrint('DashboardHomePage: 延迟检查发现WatchHistoryProvider已加载但数据为空，重新加载数据');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadData();
              }
            });
          }
        }
      });
    });
  }
  
  // 获取或创建Jellyfin媒体库的ScrollController
  ScrollController _getJellyfinLibraryScrollController(String libraryName) {
    if (!_jellyfinLibraryScrollControllers.containsKey(libraryName)) {
      _jellyfinLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _jellyfinLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建Emby媒体库的ScrollController
  ScrollController _getEmbyLibraryScrollController(String libraryName) {
    if (!_embyLibraryScrollControllers.containsKey(libraryName)) {
      _embyLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _embyLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建本地媒体库的ScrollController
  ScrollController _getLocalLibraryScrollController() {
    _localLibraryScrollController ??= ScrollController();
    return _localLibraryScrollController!;
  }
  
  void _startAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _autoSwitchTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAutoSwitching && _recommendedItems.length >= 5 && mounted) {
        _currentHeroBannerIndex = (_currentHeroBannerIndex + 1) % 5;
        _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
        if (_heroBannerPageController.hasClients) {
          _heroBannerPageController.animateToPage(
            _currentHeroBannerIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }
  
  void _stopAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _isAutoSwitching = false;
  }
  
  void _resumeAutoSwitch() {
    _isAutoSwitching = true;
    _startAutoSwitch();
  }
  
  void _setupProviderListeners() {
    // 订阅 Provider 级 ready；ready 之前不监听 Provider 的即时变化
    try {
      _jellyfinProviderRef = Provider.of<JellyfinProvider>(context, listen: false);
      _jellyfinProviderReadyListener = () {
        if (!mounted) return;
        debugPrint('DashboardHomePage: 收到 Jellyfin Provider ready 信号');
        // ready 后立即清理待处理请求，避免重复刷新
        _pendingRefreshAfterLoad = false;
        _pendingRefreshReason = '';
        // 先触发首次加载，避免激活监听后立即触发状态变化导致重复刷新
        _triggerLoadIfIdle('Jellyfin Provider ready');
        // 等待首次加载完成后再激活监听，避免加载期间的状态变化被捕获
        _scheduleJellyfinListeningActivation();
      };
      _jellyfinProviderRef!.addReadyListener(_jellyfinProviderReadyListener!);
      // 若进入页面时已 provider-ready，则立即激活监听并首刷
      if (_jellyfinProviderRef!.isReady) {
        _activateJellyfinLiveListening();
        // 不在进入页面时立即刷新，首刷由 initState 的 _loadData 负责，避免重复刷新
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 安装 Jellyfin Provider ready 监听失败: $e');
    }
    try {
      _embyProviderRef = Provider.of<EmbyProvider>(context, listen: false);
      _embyProviderReadyListener = () {
        if (!mounted) return;
        debugPrint('DashboardHomePage: 收到 Emby Provider ready 信号');
        // ready 后立即清理待处理请求，避免重复刷新
        _pendingRefreshAfterLoad = false;
        _pendingRefreshReason = '';
        // 先触发首次加载，避免激活监听后立即触发状态变化导致重复刷新
        _triggerLoadIfIdle('Emby Provider ready');
        // 等待首次加载完成后再激活监听，避免加载期间的状态变化被捕获
        _scheduleEmbyListeningActivation();
      };
      _embyProviderRef!.addReadyListener(_embyProviderReadyListener!);
      if (_embyProviderRef!.isReady) {
        _activateEmbyLiveListening();
        // 不在进入页面时立即刷新，首刷由 initState 的 _loadData 负责，避免重复刷新
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 安装 Emby Provider ready 监听失败: $e');
    }
    
    // 监听WatchHistoryProvider的加载状态变化
    try {
  _watchHistoryProviderRef = Provider.of<WatchHistoryProvider>(context, listen: false);
  _watchHistoryProviderRef!.addListener(_onWatchHistoryStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加WatchHistoryProvider监听器失败: $e');
    }
    
    // 监听ScanService的扫描完成状态变化
    try {
  _scanServiceRef = Provider.of<ScanService>(context, listen: false);
  _scanServiceRef!.addListener(_onScanServiceStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加ScanService监听器失败: $e');
    }
    
    // 监听VideoPlayerState的状态变化，用于检测播放器状态
    try {
  _videoPlayerStateRef = Provider.of<VideoPlayerState>(context, listen: false);
  _videoPlayerStateRef!.addListener(_onVideoPlayerStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加VideoPlayerState监听器失败: $e');
    }
  }

  void _activateJellyfinLiveListening() {
    if (_jellyfinLiveListening || _jellyfinProviderRef == null) return;
    try {
      _jellyfinProviderRef!.addListener(_onJellyfinStateChanged);
      _jellyfinLiveListening = true;
      debugPrint('DashboardHomePage: 已激活 Jellyfin Provider 即时监听');
    } catch (e) {
      debugPrint('DashboardHomePage: 激活 Jellyfin 监听失败: $e');
    }
  }

  void _scheduleJellyfinListeningActivation() {
    // 等待当前数据加载完成后再激活监听，避免加载期间的状态变化被误捕获
    void checkAndActivate() {
      if (!mounted) return;
      if (_isLoadingRecommended) {
        // 如果还在加载，继续等待
        Future.delayed(const Duration(milliseconds: 100), checkAndActivate);
      } else {
        // 加载完成，可以安全激活监听
        _activateJellyfinLiveListening();
      }
    }
    checkAndActivate();
  }

  void _deactivateJellyfinLiveListening() {
    if (!_jellyfinLiveListening) return;
    try {
      _jellyfinProviderRef?.removeListener(_onJellyfinStateChanged);
    } catch (_) {}
    _jellyfinLiveListening = false;
    debugPrint('DashboardHomePage: 已暂停 Jellyfin Provider 即时监听');
  }

  void _activateEmbyLiveListening() {
    if (_embyLiveListening || _embyProviderRef == null) return;
    try {
      _embyProviderRef!.addListener(_onEmbyStateChanged);
      _embyLiveListening = true;
      debugPrint('DashboardHomePage: 已激活 Emby Provider 即时监听');
    } catch (e) {
      debugPrint('DashboardHomePage: 激活 Emby 监听失败: $e');
    }
  }

  void _scheduleEmbyListeningActivation() {
    // 等待当前数据加载完成后再激活监听，避免加载期间的状态变化被误捕获
    void checkAndActivate() {
      if (!mounted) return;
      if (_isLoadingRecommended) {
        // 如果还在加载，继续等待
        Future.delayed(const Duration(milliseconds: 100), checkAndActivate);
      } else {
        // 加载完成，可以安全激活监听
        _activateEmbyLiveListening();
      }
    }
    checkAndActivate();
  }

  void _deactivateEmbyLiveListening() {
    if (!_embyLiveListening) return;
    try {
      _embyProviderRef?.removeListener(_onEmbyStateChanged);
    } catch (_) {}
    _embyLiveListening = false;
    debugPrint('DashboardHomePage: 已暂停 Emby Provider 即时监听');
  }

  // ready 或进入页面即已 ready 时，若空闲则立即刷新一次
  void _triggerLoadIfIdle(String reason) {
    if (!mounted) return;
    debugPrint('DashboardHomePage: 检测到$reason，准备执行首次刷新');
    if (_isVideoPlayerActive()) return;
    // 合并短时间内的重复触发：注意，后端 ready 不参与合并，必须执行；仅合并后续触发
    final now = DateTime.now();
    final bool isBackendReady = reason.contains('后端 ready');
    if (!isBackendReady && _lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
      debugPrint('DashboardHomePage: 距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过这次($reason)');
      return;
    }
    if (_isLoadingRecommended) {
      _pendingRefreshAfterLoad = true;
      _pendingRefreshReason = reason;
      return;
    }
    _loadData();
  }
  
  // 检查播放器是否处于活跃状态（播放中、暂停或准备好播放）
  bool _isVideoPlayerActive() {
    try {
      // 使用缓存机制，避免频繁的Provider查询
      final now = DateTime.now();
      const cacheValidDuration = Duration(milliseconds: 100); // 100ms缓存
      
      if (now.difference(_lastPlayerStateCheck) < cacheValidDuration) {
        return _cachedPlayerActiveState;
      }
      
      final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
      final isActive = videoPlayerState.status == PlayerStatus.playing || 
             videoPlayerState.status == PlayerStatus.paused ||
             videoPlayerState.hasVideo ||
             videoPlayerState.currentVideoPath != null;
      
      // 更新缓存
      _cachedPlayerActiveState = isActive;
      _lastPlayerStateCheck = now;
      
      // 只在状态发生变化时打印调试信息，减少日志噪音
      if (isActive != _wasPlayerActive) {
        debugPrint('DashboardHomePage: 播放器活跃状态变化 - $isActive '
                   '(status: ${videoPlayerState.status}, hasVideo: ${videoPlayerState.hasVideo})');
      }
      
      return isActive;
    } catch (e) {
      debugPrint('DashboardHomePage: _isVideoPlayerActive() 出错: $e');
      return false;
    }
  }

  // 判断是否应该延迟图片加载（避免与HEAD验证竞争）
  bool _shouldDelayImageLoad() {
    // 检查推荐内容中是否包含本地媒体
    final hasLocalContent = _recommendedItems.any((item) => 
      item.source == RecommendedItemSource.local
    );
    
    // 如果有本地媒体，就立即加载以保持最佳性能；没有本地媒体才延迟避免与HEAD验证竞争
    return !hasLocalContent;
  }

  void _onVideoPlayerStateChanged() {
    if (!mounted) return;
    
    final isCurrentlyActive = _isVideoPlayerActive();
    
    // 检测播放器从活跃状态变为非活跃状态（退出播放器）
    if (_wasPlayerActive && !isCurrentlyActive) {
      debugPrint('DashboardHomePage: 检测到播放器状态变为非活跃，启动延迟检查');
      
      // 取消之前的检查Timer
      _playerStateCheckTimer?.cancel();
      
      // 延迟检查，避免快速状态切换时的误触发
      _playerStateCheckTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && !_isVideoPlayerActive()) {
          debugPrint('DashboardHomePage: 确认播放器已退出，异步更新数据');
          _loadData();
        } else {
          debugPrint('DashboardHomePage: 播放器状态已恢复活跃，取消更新');
        }
      });
    }
    
    // 如果播放器重新变为活跃状态，取消待处理的更新
    if (!_wasPlayerActive && isCurrentlyActive) {
      debugPrint('DashboardHomePage: 播放器重新激活，取消待处理的更新检查');
      _playerStateCheckTimer?.cancel();
    }
    
    // 更新播放器活跃状态记录
    _wasPlayerActive = isCurrentlyActive;
  }
  
  void _onJellyfinStateChanged() {
  if (!_jellyfinLiveListening) return; // ready 前不处理
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Jellyfin状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过Jellyfin状态变化处理');
      return;
    }
    
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final connected = jellyfinProvider.isConnected;
    debugPrint('DashboardHomePage: Jellyfin provider 状态变化 - isConnected: $connected, mounted: $mounted');

    // 断开连接时，立即清空“最近添加”并刷新一次UI，避免残留
    if (!connected && mounted) {
      if (_recentJellyfinItemsByLibrary.isNotEmpty) {
        _recentJellyfinItemsByLibrary.clear();
        setState(() {});
      }
      // 继续走防抖以触发后续常规刷新（如空态）
    }

    // 已连接时的即时刷新（保持原有有效逻辑）：
    if (connected && mounted) {
      // 合并短时间内的重复触发（避免与刚刚的 ready/首刷重叠）
      final now = DateTime.now();
      if (_lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
        debugPrint('DashboardHomePage: Jellyfin连接完成，但距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过立即刷新');
        return;
      }
      if (_isLoadingRecommended) {
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Jellyfin连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Jellyfin刷新请求待稍后处理');
      } else {
        debugPrint('DashboardHomePage: Jellyfin连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
      return; // 避免与防抖重复触发
    }

  // 统一处理 provider 状态变化（连接/断开/库选择等）：轻量防抖刷新
    _jfDebounceTimer?.cancel();
    _jfDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _isVideoPlayerActive() || _isLoadingRecommended) return;
      debugPrint('DashboardHomePage: Jellyfin provider 状态变化（防抖触发）刷新');
      _loadData();
    });
  }
  
  void _onEmbyStateChanged() {
  if (!_embyLiveListening) return; // ready 前不处理
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Emby状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过Emby状态变化处理');
      return;
    }
    
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final connected = embyProvider.isConnected;
    debugPrint('DashboardHomePage: Emby provider 状态变化 - isConnected: $connected, mounted: $mounted');

    // 断开连接时，立即清空“最近添加”并刷新一次UI，避免残留
    if (!connected && mounted) {
      if (_recentEmbyItemsByLibrary.isNotEmpty) {
        _recentEmbyItemsByLibrary.clear();
        setState(() {});
      }
      // 继续走防抖以触发后续常规刷新（如空态）
    }

    // 已连接时的即时刷新（保持原有有效逻辑）：
    if (connected && mounted) {
      // 合并短时间内的重复触发（避免与刚刚的 ready/首刷重叠）
      final now = DateTime.now();
      if (_lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
        debugPrint('DashboardHomePage: Emby连接完成，但距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过立即刷新');
        return;
      }
      if (_isLoadingRecommended) {
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Emby连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Emby刷新请求待稍后处理');
      } else {
        debugPrint('DashboardHomePage: Emby连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
      return; // 避免与防抖重复触发
    }

  // 统一处理 provider 状态变化（连接/断开/库选择等）：轻量防抖刷新
    _emDebounceTimer?.cancel();
    _emDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _isVideoPlayerActive() || _isLoadingRecommended) return;
      debugPrint('DashboardHomePage: Emby provider 状态变化（防抖触发）刷新');
      _loadData();
    });
  }
  
  void _onWatchHistoryStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过WatchHistory状态变化处理');
      return;
    }
    
    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
    debugPrint('DashboardHomePage: WatchHistory加载状态变化 - isLoaded: ${watchHistoryProvider.isLoaded}, mounted: $mounted');
    
    if (watchHistoryProvider.isLoaded && mounted) {
      if (_isLoadingRecommended) {
        // 如果正在加载，记录待处理的刷新请求
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'WatchHistory加载完成';
        debugPrint('DashboardHomePage: 正在加载中，记录WatchHistory刷新请求待稍后处理');
      } else {
        // 如果未在加载，检查播放器状态后决定是否刷新
        if (_isVideoPlayerActive()) {
          debugPrint('DashboardHomePage: WatchHistory加载完成，但播放器活跃中，跳过刷新');
        } else {
          debugPrint('DashboardHomePage: WatchHistory加载完成，立即刷新数据');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadData();
            }
          });
        }
      }
    }
  }
  
  void _onScanServiceStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过ScanService状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过ScanService状态变化处理');
      return;
    }
    
    final scanService = Provider.of<ScanService>(context, listen: false);
    debugPrint('DashboardHomePage: ScanService状态变化 - scanJustCompleted: ${scanService.scanJustCompleted}, mounted: $mounted');
    
    if (scanService.scanJustCompleted && mounted) {
      debugPrint('DashboardHomePage: 扫描完成，刷新WatchHistoryProvider和本地媒体库数据');
      
      // 刷新WatchHistoryProvider以获取最新的扫描结果
      try {
        final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.refresh();
      } catch (e) {
        debugPrint('DashboardHomePage: 刷新WatchHistoryProvider失败: $e');
      }
      
      // 🔥 修复Flutter状态错误：使用addPostFrameCallback确保不在build期间调用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
      
      // 确认扫描完成事件已处理
      scanService.acknowledgeScanCompleted();
    }
  }



  @override
  void dispose() {
    debugPrint('DashboardHomePage: 开始销毁Widget');
    
    // 清理定时器和ValueNotifier
    _autoSwitchTimer?.cancel();
    _playerStateCheckTimer?.cancel();
    _playerStateCheckTimer = null;
    
    // 重置播放器状态缓存，防止内存泄漏
    _cachedPlayerActiveState = false;
    _wasPlayerActive = false;
    
    _heroBannerIndexNotifier.dispose();
    
    // 移除监听器 - 使用初始化时保存的实例引用，避免在dispose中再次查找context
    try {
      _jfDebounceTimer?.cancel();
      _deactivateJellyfinLiveListening();
      if (_jellyfinProviderReadyListener != null) {
        try { _jellyfinProviderRef?.removeReadyListener(_jellyfinProviderReadyListener!); } catch (_) {}
        _jellyfinProviderReadyListener = null;
      }
      debugPrint('DashboardHomePage: JellyfinProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除JellyfinProvider监听器失败: $e');
    }
    
    try {
      _emDebounceTimer?.cancel();
      _deactivateEmbyLiveListening();
      if (_embyProviderReadyListener != null) {
        try { _embyProviderRef?.removeReadyListener(_embyProviderReadyListener!); } catch (_) {}
        _embyProviderReadyListener = null;
      }
      debugPrint('DashboardHomePage: EmbyProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除EmbyProvider监听器失败: $e');
    }
    
    try {
      _watchHistoryProviderRef?.removeListener(_onWatchHistoryStateChanged);
      debugPrint('DashboardHomePage: WatchHistoryProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除WatchHistoryProvider监听器失败: $e');
    }
    
    try {
      _scanServiceRef?.removeListener(_onScanServiceStateChanged);
      debugPrint('DashboardHomePage: ScanService监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除ScanService监听器失败: $e');
    }
    
    try {
      _videoPlayerStateRef?.removeListener(_onVideoPlayerStateChanged);
      debugPrint('DashboardHomePage: VideoPlayerState监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除VideoPlayerState监听器失败: $e');
    }
    
    // 销毁ScrollController
    try {
      _heroBannerPageController.dispose();
      _mainScrollController.dispose();
      _continueWatchingScrollController.dispose();
      _recentJellyfinScrollController.dispose();
      _recentEmbyScrollController.dispose();
      
      // 销毁动态创建的ScrollController
      for (final controller in _jellyfinLibraryScrollControllers.values) {
        controller.dispose();
      }
      _jellyfinLibraryScrollControllers.clear();
      
      for (final controller in _embyLibraryScrollControllers.values) {
        controller.dispose();
      }
      _embyLibraryScrollControllers.clear();
      
      _localLibraryScrollController?.dispose();
      _localLibraryScrollController = null;
      
      debugPrint('DashboardHomePage: ScrollController已销毁');
    } catch (e) {
      debugPrint('DashboardHomePage: 销毁ScrollController失败: $e');
    }
    
    debugPrint('DashboardHomePage: Widget销毁完成');
    super.dispose();
  }

  Future<void> _loadData() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('DashboardHomePage: _loadData 被调用 - _isLoadingRecommended: $_isLoadingRecommended, mounted: $mounted');
    _lastLoadTime = DateTime.now();
    
    // 检查Widget状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过数据加载');
      return;
    }
    
    // 如果播放器处于活跃状态，跳过数据加载
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过数据加载');
      return;
    }
    
    // 如果正在加载，先检查是否需要强制重新加载
    if (_isLoadingRecommended) {
      debugPrint('DashboardHomePage: 已在加载中，跳过重复调用 - _isLoadingRecommended: $_isLoadingRecommended');
      return;
    }
    
    // 🔥 修复仪表盘启动问题：确保WatchHistoryProvider已加载
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
        debugPrint('DashboardHomePage: WatchHistoryProvider未加载，主动触发加载');
        await watchHistoryProvider.loadHistory();
      } else if (watchHistoryProvider.isLoaded) {
        debugPrint('DashboardHomePage: WatchHistoryProvider已加载完成，历史记录数量: ${watchHistoryProvider.history.length}');
      } else {
        debugPrint('DashboardHomePage: WatchHistoryProvider正在加载中...');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 加载WatchHistoryProvider失败: $e');
    }
    
    debugPrint('DashboardHomePage: 开始加载数据');
    
    // 并行加载推荐内容和最近内容
    try {
      await Future.wait([
        _loadRecommendedContent(forceRefresh: true),
        _loadRecentContent(),
      ]);
    } catch (e) {
      debugPrint('DashboardHomePage: 并行加载数据时发生错误: $e');
      // 如果并行加载失败，尝试串行加载
      try {
        await _loadRecommendedContent(forceRefresh: true);
        await _loadRecentContent();
      } catch (e2) {
        debugPrint('DashboardHomePage: 串行加载数据也失败: $e2');
      }
    }
    
    stopwatch.stop();
    debugPrint('DashboardHomePage: 数据加载完成，总耗时: ${stopwatch.elapsedMilliseconds}ms');
  }

  // 检查并处理待处理的刷新请求
  void _checkPendingRefresh() {
    if (_pendingRefreshAfterLoad && mounted) {
      debugPrint('DashboardHomePage: 处理待处理的刷新请求 - ${_pendingRefreshReason}');
      _pendingRefreshAfterLoad = false;
      _pendingRefreshReason = '';
      // 使用短延迟避免连续调用，并检查播放器状态
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isLoadingRecommended && !_isVideoPlayerActive()) {
          debugPrint('DashboardHomePage: 执行待处理的刷新请求');
          _loadData();
        } else if (_isVideoPlayerActive()) {
          debugPrint('DashboardHomePage: 播放器活跃中，跳过待处理的刷新请求');
        }
      });
    }
  }

  Future<void> _loadRecommendedContent({bool forceRefresh = false}) async {
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过推荐内容加载');
      return;
    }
    
    // 检查是否强制刷新或缓存已过期
    if (!forceRefresh && _cachedRecommendedItems.isNotEmpty && 
        _lastRecommendedLoadTime != null && 
        DateTime.now().difference(_lastRecommendedLoadTime!).inHours < 24) {
      debugPrint('DashboardHomePage: 使用缓存的推荐内容');
      setState(() {
        _recommendedItems = _cachedRecommendedItems;
        _isLoadingRecommended = false;
      });
      
      // 推荐内容加载完成后启动自动切换
      if (_recommendedItems.length >= 5) {
        _startAutoSwitch();
      }
      
      return;
    }

    debugPrint('DashboardHomePage: 开始加载推荐内容');
    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      // 第一步：快速收集所有候选项目（只收集基本信息）
      List<dynamic> allCandidates = [];

      // 从Jellyfin收集候选项目（按媒体库并行）
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        final jellyfinFutures = <Future<List<JellyfinMediaItem>>>[];
        final jellyfinLibNames = <String>[];
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            jellyfinLibNames.add(library.name);
            jellyfinFutures.add(
              jellyfinService
                  .getRandomMediaItemsByLibrary(library.id, limit: 50)
                  .then((items) {
                    debugPrint('从Jellyfin媒体库 ${library.name} 收集到 ${items.length} 个候选项目');
                    return items;
                  })
                  .catchError((e) {
                    debugPrint('获取Jellyfin媒体库 ${library.name} 随机内容失败: $e');
                    return <JellyfinMediaItem>[];
                  }),
            );
          }
        }
        if (jellyfinFutures.isNotEmpty) {
          final results = await Future.wait(jellyfinFutures, eagerError: false);
          for (final items in results) {
            allCandidates.addAll(items);
          }
        }
      }

      // 从Emby收集候选项目（按媒体库并行）
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        final embyFutures = <Future<List<EmbyMediaItem>>>[];
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            embyFutures.add(
              embyService
                  .getRandomMediaItemsByLibrary(library.id, limit: 50)
                  .then((items) {
                    debugPrint('从Emby媒体库 ${library.name} 收集到 ${items.length} 个候选项目');
                    return items;
                  })
                  .catchError((e) {
                    debugPrint('获取Emby媒体库 ${library.name} 随机内容失败: $e');
                    return <EmbyMediaItem>[];
                  }),
            );
          }
        }
        if (embyFutures.isNotEmpty) {
          final results = await Future.wait(embyFutures, eagerError: false);
          for (final items in results) {
            allCandidates.addAll(items);
          }
        }
      }

      // 从本地媒体库收集候选项目
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();
          
          // 按animeId分组，获取每个动画的最新观看记录
          final Map<int, WatchHistoryItem> latestLocalItems = {};
          for (var item in localHistory) {
            if (item.animeId != null) {
              if (latestLocalItems.containsKey(item.animeId!)) {
                if (item.lastWatchTime.isAfter(latestLocalItems[item.animeId!]!.lastWatchTime)) {
                  latestLocalItems[item.animeId!] = item;
                }
              } else {
                latestLocalItems[item.animeId!] = item;
              }
            }
          }
          
          // 随机选择一些本地项目 - 直接使用WatchHistoryItem作为候选
          final localItems = latestLocalItems.values.toList();
          localItems.shuffle(math.Random());
          final selectedLocalItems = localItems.take(math.min(30, localItems.length)).toList();
          allCandidates.addAll(selectedLocalItems);
          debugPrint('从本地媒体库收集到 ${selectedLocalItems.length} 个候选项目');
        } catch (e) {
          debugPrint('获取本地媒体库随机内容失败: $e');
        }
      } else {
        debugPrint('WatchHistoryProvider未加载完成，跳过本地媒体库推荐内容收集');
      }

      // 第二步：从所有候选中随机选择7个
      List<dynamic> selectedCandidates = [];
      if (allCandidates.isNotEmpty) {
        allCandidates.shuffle(math.Random());
        selectedCandidates = allCandidates.take(7).toList();
        debugPrint('从${allCandidates.length}个候选项目中随机选择了${selectedCandidates.length}个');
      }

      // 第二点五步：预加载本地媒体项目的图片缓存，确保立即显示
      final localAnimeIds = selectedCandidates
          .where((item) => item is WatchHistoryItem && item.animeId != null)
          .map((item) => (item as WatchHistoryItem).animeId!)
          .toSet();
      if (localAnimeIds.isNotEmpty) {
        await _loadPersistedLocalImageUrls(localAnimeIds);
        debugPrint('预加载了 ${localAnimeIds.length} 个本地推荐项目的图片缓存');
      }

      // 第三步：快速构建基础推荐项目，先用缓存的封面图片
      List<RecommendedItem> basicItems = [];
      final itemFutures = selectedCandidates.map((item) async {
        try {
          if (item is JellyfinMediaItem) {
            // Jellyfin项目 - 首屏即加载 Backdrop/Logo/详情（带验证与回退）
            final jellyfinService = JellyfinService.instance;
            final results = await Future.wait([
              _tryGetJellyfinImage(jellyfinService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetJellyfinImage(jellyfinService, item.id, ['Logo', 'Thumb']),
              _getJellyfinItemSubtitle(jellyfinService, item),
            ]);
            final backdropUrl = results[0];
            final logoUrl = results[1];
            final subtitle = results[2];

            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: (subtitle?.isNotEmpty == true) ? subtitle! : (item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息'),
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.jellyfin,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            );
            
          } else if (item is EmbyMediaItem) {
            // Emby项目 - 首屏即加载 Backdrop/Logo/详情（带验证与回退）
            final embyService = EmbyService.instance;
            final results = await Future.wait([
              _tryGetEmbyImage(embyService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetEmbyImage(embyService, item.id, ['Logo', 'Thumb']),
              _getEmbyItemSubtitle(embyService, item),
            ]);
            final backdropUrl = results[0];
            final logoUrl = results[1];
            final subtitle = results[2];

            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: (subtitle?.isNotEmpty == true) ? subtitle! : (item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息'),
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.emby,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            );
            
          } else if (item is WatchHistoryItem) {
            // 本地媒体库项目 - 先用缓存的封面图片
            String? cachedImageUrl;
            String subtitle = '暂无简介信息';
            
            if (item.animeId != null) {
              // 从缓存获取图片URL（来自本地图片缓存）
              cachedImageUrl = _localImageCache[item.animeId!];
              
              // 优先读取持久化的高清图缓存（与媒体库页复用同一Key前缀）
              if (cachedImageUrl == null) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final persisted = prefs.getString('$_localPrefsKeyPrefix${item.animeId!}');
                  if (persisted != null && persisted.isNotEmpty) {
                    cachedImageUrl = persisted;
                    _localImageCache[item.animeId!] = persisted; // 写回内存缓存
                  }
                } catch (_) {}
              }

              // 尝试从SharedPreferences获取已缓存的详情信息
              try {
                final prefs = await SharedPreferences.getInstance();
                final cacheKey = 'bangumi_detail_${item.animeId!}';
                final String? cachedString = prefs.getString(cacheKey);
                if (cachedString != null) {
                  final data = json.decode(cachedString);
                  final animeData = data['animeDetail'] as Map<String, dynamic>?;
                  if (animeData != null) {
                    final summary = animeData['summary'] as String?;
                    final imageUrl = animeData['imageUrl'] as String?;
                    if (summary?.isNotEmpty == true) {
                      subtitle = summary!;
                    }
                    if (cachedImageUrl == null && imageUrl?.isNotEmpty == true) {
                      cachedImageUrl = imageUrl;
                    }
                  }
                }
              } catch (e) {
                // 忽略缓存访问错误
              }
            }
            
            return RecommendedItem(
              id: item.animeId?.toString() ?? item.filePath,
              title: item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画'),
              subtitle: subtitle,
              backgroundImageUrl: cachedImageUrl,
              logoImageUrl: null,
              source: RecommendedItemSource.local,
              rating: null,
            );
          }
        } catch (e) {
          debugPrint('快速构建推荐项目失败: $e');
          return null;
        }
        return null;
      });
      
      // 等待基础项目构建完成
      final processedItems = await Future.wait(itemFutures);
      basicItems = processedItems.where((item) => item != null).cast<RecommendedItem>().toList();

      // 如果还不够7个，添加占位符
      while (basicItems.length < 7) {
        basicItems.add(RecommendedItem(
          id: 'placeholder_${basicItems.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }

      // 第四步：立即显示基础项目
      if (mounted) {
        setState(() {
          _recommendedItems = basicItems;
          _isLoadingRecommended = false;
        });
        
        // 缓存推荐内容和加载时间
        _cachedRecommendedItems = basicItems;
        _lastRecommendedLoadTime = DateTime.now();
        
        // 推荐内容加载完成后启动自动切换
        if (basicItems.length >= 5) {
          _startAutoSwitch();
        }
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
      
      // 第五步：后台异步升级为高清图片（仅对本地媒体生效，Jellyfin/Emby已首屏获取完毕）
      final localCandidates = <dynamic>[];
      final localBasicItems = <RecommendedItem>[];
      for (int i = 0; i < selectedCandidates.length && i < basicItems.length; i++) {
        if (selectedCandidates[i] is WatchHistoryItem) {
          localCandidates.add(selectedCandidates[i]);
          localBasicItems.add(basicItems[i]);
        }
      }
      if (localCandidates.isNotEmpty) {
        _upgradeToHighQualityImages(localCandidates, localBasicItems);
      }
      
      debugPrint('推荐内容基础加载完成，总共 ${basicItems.length} 个项目，后台正在加载高清图片');
    } catch (e) {
      debugPrint('加载推荐内容失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecommended = false;
        });
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
    }
  }

  Future<void> _loadRecentContent() async {
    debugPrint('DashboardHomePage: 开始加载最近内容');
    try {
      // 从Jellyfin按媒体库获取最近添加（按库并行）
  final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
  if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        _recentJellyfinItemsByLibrary.clear();
        final jfFutures = <Future<void>>[];
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            jfFutures.add(() async {
              try {
                final libraryItems = await jellyfinService.getLatestMediaItemsByLibrary(library.id, limit: 25);
                if (libraryItems.isNotEmpty) {
                  _recentJellyfinItemsByLibrary[library.name] = libraryItems;
                  debugPrint('Jellyfin媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
                }
              } catch (e) {
                debugPrint('获取Jellyfin媒体库 ${library.name} 最近内容失败: $e');
              }
            }());
          }
        }
        if (jfFutures.isNotEmpty) {
          await Future.wait(jfFutures, eagerError: false);
        }
      } else {
        // 未连接时确保清空
        _recentJellyfinItemsByLibrary.clear();
      }

      // 从Emby按媒体库获取最近添加（按库并行）
  final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
  if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        _recentEmbyItemsByLibrary.clear();
        final emFutures = <Future<void>>[];
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            emFutures.add(() async {
              try {
                final libraryItems = await embyService.getLatestMediaItemsByLibrary(library.id, limit: 25);
                if (libraryItems.isNotEmpty) {
                  _recentEmbyItemsByLibrary[library.name] = libraryItems;
                  debugPrint('Emby媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
                }
              } catch (e) {
                debugPrint('获取Emby媒体库 ${library.name} 最近内容失败: $e');
              }
            }());
          }
        }
        if (emFutures.isNotEmpty) {
          await Future.wait(emFutures, eagerError: false);
        }
      } else {
        // 未连接时确保清空
        _recentEmbyItemsByLibrary.clear();
      }

      // 从本地媒体库获取最近添加（优化：不做逐文件stat，按历史记录时间排序，图片懒加载+持久化）
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();

          // 按animeId分组，选取"添加时间"代表：
          // 优先使用 isFromScan 为 true 的记录的 lastWatchTime（扫描入库时间），否则用最近一次 lastWatchTime
          final Map<int, WatchHistoryItem> representativeItems = {};
          final Map<int, DateTime> addedTimeMap = {};

          for (final item in localHistory) {
            final animeId = item.animeId;
            if (animeId == null) continue;

            final candidateTime = item.isFromScan ? item.lastWatchTime : item.lastWatchTime;
            if (!representativeItems.containsKey(animeId)) {
              representativeItems[animeId] = item;
              addedTimeMap[animeId] = candidateTime;
            } else {
              // 对于同一番组，取时间更新的那条作为代表
              if (candidateTime.isAfter(addedTimeMap[animeId]!)) {
                representativeItems[animeId] = item;
                addedTimeMap[animeId] = candidateTime;
              }
            }
          }

          // 提前从本地持久化中加载图片URL缓存，避免首屏大量网络请求
          await _loadPersistedLocalImageUrls(addedTimeMap.keys.toSet());

          // 构建 LocalAnimeItem 列表（先用缓存命中图片，未命中先留空，稍后后台补齐）
          List<LocalAnimeItem> localAnimeItems = representativeItems.entries.map((entry) {
            final animeId = entry.key;
            final latestEpisode = entry.value;
            final addedTime = addedTimeMap[animeId]!;
            final cachedImg = _localImageCache[animeId];
            return LocalAnimeItem(
              animeId: animeId,
              animeName: latestEpisode.animeName.isNotEmpty ? latestEpisode.animeName : '未知动画',
              imageUrl: cachedImg,
              backdropImageUrl: cachedImg,
              addedTime: addedTime,
              latestEpisode: latestEpisode,
            );
          }).toList();

          // 排序（最新在前）并限制数量
          localAnimeItems.sort((a, b) => b.addedTime.compareTo(a.addedTime));
          if (localAnimeItems.length > 25) {
            localAnimeItems = localAnimeItems.take(25).toList();
          }

          _localAnimeItems = localAnimeItems;
          debugPrint('本地媒体库获取到 ${_localAnimeItems.length} 个项目（首屏使用缓存图片，后台补齐高清图）');
        } catch (e) {
          debugPrint('获取本地媒体库最近内容失败: $e');
        }
      } else {
        debugPrint('WatchHistoryProvider未加载完成，跳过本地媒体库最近内容加载');
        _localAnimeItems = []; // 清空本地项目列表
      }

      if (mounted) {
        setState(() {
          // 触发UI更新
        });

        // 首屏渲染后，后台限流补齐缺失图片与番组详情（避免阻塞UI）
        _fetchLocalAnimeImagesInBackground();
      }
    } catch (e) {
      debugPrint('加载最近内容失败: $e');
    }
  }

  // 加载持久化的本地番组图片URL（与媒体库页复用同一Key前缀）
  Future<void> _loadPersistedLocalImageUrls(Set<int> animeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in animeIds) {
        if (_localImageCache.containsKey(id)) continue;
        final url = prefs.getString('$_localPrefsKeyPrefix$id');
        if (url != null && url.isNotEmpty) {
          _localImageCache[id] = url;
        }
      }
    } catch (e) {
      debugPrint('加载本地图片持久化缓存失败: $e');
    }
  }

  // 后台抓取缺失的番组图片，限流并写入持久化缓存（优化版本）
  Future<void> _fetchLocalAnimeImagesInBackground() async {
    if (_isLoadingLocalImages) return;
    _isLoadingLocalImages = true;
    
    debugPrint('开始后台获取本地番剧缺失图片，待处理项目: ${_localAnimeItems.length}');
    
    const int maxConcurrent = 3;
    final inflight = <Future<void>>[];
    int processedCount = 0;
    int updatedCount = 0;

    for (final item in _localAnimeItems) {
      final id = item.animeId;
      if (_localImageCache.containsKey(id) && 
          _localImageCache[id]?.isNotEmpty == true) {
        continue; // 已有缓存且不为空，跳过
      }

      Future<void> task() async {
        try {
          // 先尝试从BangumiService缓存获取
          String? imageUrl;
          // String? summary; // 暂时不需要summary变量
          
          // 尝试从SharedPreferences获取已缓存的详情
          try {
            final prefs = await SharedPreferences.getInstance();
            final cacheKey = 'bangumi_detail_$id';
            final String? cachedString = prefs.getString(cacheKey);
            if (cachedString != null) {
              final data = json.decode(cachedString);
              final animeData = data['animeDetail'] as Map<String, dynamic>?;
              if (animeData != null) {
                imageUrl = animeData['imageUrl'] as String?;
                // summary = animeData['summary'] as String?; // 不需要summary
              }
            }
          } catch (e) {
            // 忽略缓存读取错误
          }
          
          // 如果缓存中没有，再从网络获取
          if (imageUrl?.isEmpty != false) {
            final detail = await BangumiService.instance.getAnimeDetails(id);
            imageUrl = detail.imageUrl;
            // summary = detail.summary; // 不需要summary
          }
          
          if (imageUrl?.isNotEmpty == true) {
            _localImageCache[id] = imageUrl!;
            
            // 异步保存到持久化缓存
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('$_localPrefsKeyPrefix$id', imageUrl);
            } catch (_) {}
            
            if (mounted) {
              // 批量更新，减少UI重绘次数
              final idx = _localAnimeItems.indexWhere((e) => e.animeId == id);
              if (idx != -1) {
                _localAnimeItems[idx] = LocalAnimeItem(
                  animeId: _localAnimeItems[idx].animeId,
                  animeName: _localAnimeItems[idx].animeName,
                  imageUrl: imageUrl,
                  backdropImageUrl: imageUrl,
                  addedTime: _localAnimeItems[idx].addedTime,
                  latestEpisode: _localAnimeItems[idx].latestEpisode,
                );
                updatedCount++;
              }
            }
          }
          processedCount++;
        } catch (e) {
          // 静默失败，避免刷屏
          processedCount++;
        }
      }

      final fut = task();
      inflight.add(fut);
      fut.whenComplete(() {
        inflight.remove(fut);
      });
      
      if (inflight.length >= maxConcurrent) {
        try { 
          await Future.any(inflight); 
          // 每处理几个项目就更新一次UI，而不是等全部完成
          if (updatedCount > 0 && processedCount % 5 == 0 && mounted) {
            setState(() {});
          }
        } catch (_) {}
      }
    }

    try { 
      await Future.wait(inflight); 
    } catch (_) {}
    
    // 最终更新UI
    if (mounted && updatedCount > 0) {
      setState(() {});
    }
    
    debugPrint('本地番剧图片后台获取完成，处理: $processedCount，更新: $updatedCount');
    _isLoadingLocalImages = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // 当播放器处于活跃状态时，关闭 Dashboard 上的所有 Ticker（动画/过渡），避免后台动画占用栅格时间。
    final bool tickerEnabled = !_isVideoPlayerActive();
  final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;

    return TickerMode(
      enabled: tickerEnabled,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer2<JellyfinProvider, EmbyProvider>(
        builder: (context, jellyfinProvider, embyProvider, child) {
          final primaryColor = ThemeColorUtils.primaryForeground(context);
          final secondaryColor = ThemeColorUtils.secondaryForeground(context);
          final overlayColor =
              ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);
          return SingleChildScrollView(
            controller: _mainScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // 大海报推荐区域
                  _buildHeroBanner(isPhone: isPhone),
                  
                  SizedBox(height: isPhone ? 16 : 32), // 手机端减少间距
                  
                  // 继续播放区域
                  _buildContinueWatching(isPhone: isPhone),
                  
                  SizedBox(height: isPhone ? 12 : 32), // 手机端进一步减少间距
                  
                  // Jellyfin按媒体库显示最近添加
                  ..._recentJellyfinItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Jellyfin - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getJellyfinLibraryScrollController(entry.key),
                      onItemTap: (item) => _onJellyfinItemTap(item as JellyfinMediaItem),
                    ),
                    SizedBox(height: isPhone ? 16 : 32), // 手机端减少间距
                  ]).expand((x) => x),
                  
                  // Emby按媒体库显示最近添加
                  ..._recentEmbyItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Emby - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getEmbyLibraryScrollController(entry.key),
                      onItemTap: (item) => _onEmbyItemTap(item as EmbyMediaItem),
                    ),
                    SizedBox(height: isPhone ? 16 : 32), // 手机端减少间距
                  ]).expand((x) => x),
                  
                  // 本地媒体库显示最近添加
                  if (_localAnimeItems.isNotEmpty) ...[
                    _buildRecentSection(
                      title: '本地媒体库 - 最近添加',
                      items: _localAnimeItems,
                      scrollController: _getLocalLibraryScrollController(),
                      onItemTap: (item) => _onLocalAnimeItemTap(item as LocalAnimeItem),
                    ),
                    SizedBox(height: isPhone ? 16 : 32), // 手机端减少间距
                  ],
                  
                  // 空状态提示（当没有任何内容时）
                  if (_recentJellyfinItemsByLibrary.isEmpty && 
                      _recentEmbyItemsByLibrary.isEmpty && 
                      _localAnimeItems.isEmpty && 
                      !_isLoadingRecommended) ...[
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: overlayColor,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.video_library_outlined,
                              color: secondaryColor,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              jellyfinProvider.isConnected || embyProvider.isConnected
                                  ? '正在加载内容...'
                                  : '连接媒体服务器或观看本地视频以查看内容',
                              style: TextStyle(color: secondaryColor, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isPhone ? 16 : 32), // 手机端减少间距
                  ],
                  
                  // 底部间距
                  SizedBox(height: isPhone ? 30 : 50),
                ],
              ),
            );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 挂载本地媒体库按钮
          FloatingActionGlassButton(
            iconData: Icons.folder_open_rounded,
            onPressed: _navigateToMediaLibraryManagement,
            description: '挂载本地媒体库',
          ),
          const SizedBox(height: 16),
          // 刷新按钮
          _isLoadingRecommended 
              ? FloatingActionGlassButton(
                  iconData: Icons.refresh_rounded,
                  onPressed: () {}, // 加载中时禁用
                  description: '正在刷新...',
                )
              : FloatingActionGlassButton(
                  iconData: Icons.refresh_rounded,
                  onPressed: _loadData,
                  description: ' 刷新主页',
                ),
        ],
      ),
        ),
      );
  }

  Widget _buildHeroBanner({required bool isPhone}) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final overlayColor =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);
    if (_isLoadingRecommended) {
      return Container(
        height: isPhone ? 220 : 400, // 保持一致的高度
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: overlayColor,
        ),
        child: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    if (_recommendedItems.isEmpty) {
      return Container(
        height: isPhone ? 220 : 400, // 保持一致的高度
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: overlayColor,
        ),
        child: Center(
          child: Text(
            '暂无推荐内容',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(color: secondaryColor, fontSize: 16),
          ),
        ),
      );
    }

    // 确保至少有7个项目用于布局
    final items = _recommendedItems.length >= 7 ? _recommendedItems.take(7).toList() : _recommendedItems;
    if (items.length < 7) {
      // 如果不足7个，填充占位符
      while (items.length < 7) {
        items.add(RecommendedItem(
          id: 'placeholder_${items.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }
    }

    final int pageCount = math.min(5, items.length);

    // 手机：改为全宽轮播；桌面：左大图 + 右两张小卡
    return Container(
      height: isPhone ? 220 : 400, // 手机端更矩形，降低高度
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          if (isPhone)
            // 全宽轮播
            PageView.builder(
              controller: _heroBannerPageController,
              itemCount: pageCount,
              onPageChanged: (index) {
                _currentHeroBannerIndex = index;
                _heroBannerIndexNotifier.value = index;
                _stopAutoSwitch();
                Timer(const Duration(seconds: 3), () {
                  _resumeAutoSwitch();
                });
              },
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildMainHeroBannerItem(item, compact: true);
              },
            )
          else
            Row(
              children: [
                // 左侧主推荐横幅 - 占据大部分宽度，支持滑动（前5个）
                Expanded(
                  flex: 2,
                  child: PageView.builder(
                    controller: _heroBannerPageController,
                    itemCount: pageCount, // 固定显示前5个
                    onPageChanged: (index) {
                      _currentHeroBannerIndex = index;
                      _heroBannerIndexNotifier.value = index;
                      _stopAutoSwitch();
                      Timer(const Duration(seconds: 3), () {
                        _resumeAutoSwitch();
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = items[index]; // 使用前5个
                      return _buildMainHeroBannerItem(item);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // 右侧小卡片区域 - 上下两个（第6和第7个）
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(child: _buildSmallRecommendationCard(items[5], 5)),
                      const SizedBox(height: 8),
                      Expanded(child: _buildSmallRecommendationCard(items[6], 6)),
                    ],
                  ),
                ),
              ],
            ),
          
          // 页面指示器
          _buildPageIndicator(fullWidth: isPhone, count: pageCount),
        ],
      ),
    );
  }

  Widget _buildMainHeroBannerItem(RecommendedItem item, {bool compact = false}) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final tertiaryColor = ThemeColorUtils.tertiaryForeground(context);
    final badgeBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.25, lightOpacity: 0.18);
    final badgeBorder = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.45, lightOpacity: 0.22);
    final placeholderColor =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('hero_banner_${item.id}_${item.source.name}'), // 添加唯一key
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 使用高效缓存组件
            if (item.backgroundImageUrl != null && item.backgroundImageUrl!.isNotEmpty)
              CachedNetworkImageWidget(
                key: ValueKey('hero_img_${item.id}_${item.backgroundImageUrl}'),
                imageUrl: item.backgroundImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                errorBuilder: (context, error) => Container(
                  color: placeholderColor,
                  child: Center(
                    child:
                        Icon(Icons.broken_image, color: tertiaryColor, size: 32),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 左上角服务商标识
            Positioned(
              top: 16,
              left: 16,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: badgeBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: primaryColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角Logo - 使用高效缓存组件
            if (item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 120 : 200, // 手机端更小
                      maxHeight: compact ? 50 : 80,  // 手机端更小
                    ),
                    child: CachedNetworkImageWidget(
                      key: ValueKey('hero_logo_${item.id}_${item.logoImageUrl}'),
                      imageUrl: item.logoImageUrl!,
                      delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 120 : 200, // 手机端更小
                      maxHeight: compact ? 50 : 80,  // 手机端更小
                    ),
                    child: Image.network(
                      item.logoImageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: compact ? 120 : 200,
                          height: compact ? 50 : 80,
                          color: Colors.transparent,
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: compact ? 120 : 200,
                        height: compact ? 50 : 80,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左侧中间位置的标题和简介
            Positioned(
              left: 16,
              right: compact ? 16 : MediaQuery.of(context).size.width * 0.3, // 手机上不预留右侧空间
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft, // 左对齐而不是居中
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 媒体名字（加粗显示）
                    Text(
                      item.title,
                      locale: const Locale('zh-Hans', 'zh'),
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: compact ? 22 : 24, // 手机端调整为20px，比18px稍大
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      maxLines: compact ? 3 : 2, // 手机端可以显示更多行
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // 桌面端显示间距和简介，手机端不显示
                    if (!compact) ...[
                      const SizedBox(height: 12),
                      
                      // 剧情简介（只在桌面端显示）
                      if (item.subtitle.isNotEmpty)
                        Text(
                          item.subtitle.replaceAll('<br>', ' ').replaceAll('<br/>', ' ').replaceAll('<br />', ' '),
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 14,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallRecommendationCard(RecommendedItem item, int index) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final tertiaryColor = ThemeColorUtils.tertiaryForeground(context);
    final badgeBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.25, lightOpacity: 0.18);
    final badgeBorder = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.45, lightOpacity: 0.22);
    final placeholderColor =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark ? Colors.black.withOpacity(0.25) : Colors.black.withOpacity(0.1);
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('small_card_${item.id}_${item.source.name}_$index'), // 添加唯一key包含索引
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 使用高效缓存组件
            if (item.backgroundImageUrl != null && item.backgroundImageUrl!.isNotEmpty)
              CachedNetworkImageWidget(
                key: ValueKey('small_img_${item.id}_${item.backgroundImageUrl}_$index'),
                imageUrl: item.backgroundImageUrl!,
                fit: BoxFit.cover,
                delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error) => Container(
                  color: placeholderColor,
                  child: Center(
                    child: Icon(Icons.broken_image, color: tertiaryColor, size: 16),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 左上角服务商标识
            Positioned(
              top: 8,
              left: 8,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 8,
                right: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: badgeBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: primaryColor,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角小Logo（如果有的话）
            // Logo图片 - 使用高效缓存组件
            if (item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: CachedNetworkImageWidget(
                    key: ValueKey('small_logo_${item.id}_${item.logoImageUrl}_$index'),
                    imageUrl: item.logoImageUrl!,
                    fit: BoxFit.contain,
                    delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                  ),
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: Image.network(
                    item.logoImageUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 120,
                        height: 45,
                        color: Colors.transparent,
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 120,
                      height: 45,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            
            // 右下角标题（总是显示，不论是否有Logo）
            Positioned(
              right: 8,
              bottom: 8,
              left: item.logoImageUrl != null ? 136 : 8, // 如果有Logo就避开它
              child: Text(
                item.title,
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                      offset: Offset(1, 1),
                    ),
                    Shadow(
                      color: Colors.black,
                      blurRadius: 4,
                      offset: Offset(0, 0),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon(RecommendedItemSource source) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final badgeBackground =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.25, lightOpacity: 0.18);
    final badgeBorder =
        ThemeColorUtils.borderColor(context, darkOpacity: 0.5, lightOpacity: 0.22);
    Widget iconWidget;
    
    switch (source) {
      case RecommendedItemSource.jellyfin:
        iconWidget = SvgPicture.asset(
          'assets/jellyfin.svg',
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(primaryColor, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.emby:
        iconWidget = SvgPicture.asset(
          'assets/emby.svg',
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(primaryColor, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.local:
        // 本地文件用一个文件夹图标
        iconWidget = Icon(
          Icons.folder,
          color: primaryColor,
          size: 20,
        );
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: badgeBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: badgeBorder,
              width: 1,
            ),
          ),
          child: iconWidget,
        ),
      ),
    );
  }

  Widget _buildContinueWatching({required bool isPhone}) {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final validHistory = history.where((item) => item.duration > 0).toList();

        final primaryColor = ThemeColorUtils.primaryForeground(context);
        final secondaryColor = ThemeColorUtils.secondaryForeground(context);
        final overlayColor =
            ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '继续播放',
                      locale: const Locale('zh-Hans', 'zh'),
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (!isPhone && validHistory.isNotEmpty)
                  _buildScrollButtons(_continueWatchingScrollController, 292), // 桌面保留左右按钮
              ],
            ),
            const SizedBox(height: 16),
            if (validHistory.isEmpty)
              Container(
                height: 180,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: overlayColor,
                ),
                child: Center(
                  child: Text(
                    '暂无播放记录',
                    locale: const Locale('zh-Hans', 'zh'),
                    style: TextStyle(color: secondaryColor, fontSize: 16),
                  ),
                ),
              )
            else
              SizedBox(
                height: isPhone ? 200 : 280, // 进一步减少手机端高度
                child: ListView.builder(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: math.min(validHistory.length, 10),
                  itemBuilder: (context, index) {
                    final item = validHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContinueWatchingCard(item, compact: isPhone),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingCard(WatchHistoryItem item, {bool compact = false}) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.12);
    final progressBackground =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.28, lightOpacity: 0.18);
    return GestureDetector(
      onTap: () => _onWatchHistoryItemTap(item),
      child: SizedBox(
        key: ValueKey('continue_${item.animeId ?? 0}_${item.filePath.hashCode}'), // 添加唯一key
        width: compact ? 220 : 280, // 手机更窄
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片容器
            Container(
              height: compact ? 110 : 158, // 进一步减少手机端高度
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景缩略图
                  _getVideoThumbnail(item),
                  
                  // 播放进度条（底部）
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: item.watchProgress,
                      backgroundColor: progressBackground,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.secondary,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 媒体名称
            Text(
              item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
              style: TextStyle(
                color: primaryColor,
                fontSize: 16, // 增加字体大小
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2, // 增加显示行数
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 4),
            
            // 集数信息
            if (item.episodeTitle != null)
              Text(
                item.episodeTitle!,
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 14, // 增加字体大小
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection({
    required String title,
    required List<dynamic> items,
    required ScrollController scrollController,
    required Function(dynamic) onItemTap,
  }) {
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (!isPhone && items.isNotEmpty)
              _buildScrollButtons(scrollController, 162), // 桌面保留左右按钮
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: isPhone ? 240 : 280,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildMediaCard(item, onItemTap),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCard(dynamic item, Function(dynamic) onItemTap) {
    String name = '';
    String imageUrl = '';
    String uniqueId = '';
    
    if (item is JellyfinMediaItem) {
      name = item.name;
      uniqueId = 'jellyfin_${item.id}';
      try {
        imageUrl = JellyfinService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is EmbyMediaItem) {
      name = item.name;
      uniqueId = 'emby_${item.id}';
      try {
        imageUrl = EmbyService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is WatchHistoryItem) {
      name = item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画');
      uniqueId = 'history_${item.animeId ?? 0}_${item.filePath.hashCode}';
      imageUrl = item.thumbnailPath ?? '';
    } else if (item is LocalAnimeItem) {
      name = item.animeName;
      uniqueId = 'local_${item.animeId}_${item.animeName}';
      imageUrl = item.imageUrl ?? '';
    }

    // 使用与其他页面相同的尺寸计算方式
    // 基于 maxCrossAxisExtent: 150, childAspectRatio: 7/12
    const double cardWidth = 160;
    const double cardHeight = 200;
    
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: AnimeCard(
        key: ValueKey(uniqueId), // 添加唯一key防止widget复用导致的缓存混乱
        name: name,
        imageUrl: imageUrl,
        onTap: () => onItemTap(item),
        isOnAir: false,
        delayLoad: _shouldDelayImageLoad(), // 使用与推荐卡片相同的延迟逻辑
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    final now = DateTime.now();
    final placeholderColor =
        ThemeColorUtils.overlayColor(context, darkOpacity: 0.12, lightOpacity: 0.08);
    final tertiaryColor = ThemeColorUtils.tertiaryForeground(context);
    
    // iOS平台特殊处理：检查截图文件的修改时间
    if (Platform.isIOS && item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        try {
          final fileModified = thumbnailFile.lastModifiedSync();
          final cacheKey = '${item.filePath}_${fileModified.millisecondsSinceEpoch}';
          
          // 使用包含文件修改时间的缓存key，确保文件更新后缓存失效
          if (_thumbnailCache.containsKey(cacheKey)) {
            final cachedData = _thumbnailCache[cacheKey]!;
            final lastRenderTime = cachedData['time'] as DateTime;
            
            if (now.difference(lastRenderTime).inSeconds < 60) {
              return cachedData['widget'] as Widget;
            }
          }
          
          // 清理旧的缓存条目（相同filePath但不同修改时间）
          _thumbnailCache.removeWhere((key, value) => key.startsWith('${item.filePath}_'));
          
          final thumbnailWidget = FutureBuilder<Uint8List>(
            future: thumbnailFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(color: placeholderColor);
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _buildDefaultThumbnail();
              }
              try {
                return Image.memory(
                  snapshot.data!,
                  key: ValueKey('${item.filePath}_${fileModified.millisecondsSinceEpoch}'),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              } catch (e) {
                return _buildDefaultThumbnail();
              }
            },
          );
          
          // 使用新的缓存key存储
          _thumbnailCache[cacheKey] = {
            'widget': thumbnailWidget,
            'time': now
          };
          
          return thumbnailWidget;
        } catch (e) {
          debugPrint('获取截图文件修改时间失败: $e');
        }
      }
    }
    
    // 非iOS平台或获取修改时间失败时的原有逻辑
    if (_thumbnailCache.containsKey(item.filePath)) {
      final cachedData = _thumbnailCache[item.filePath]!;
      final lastRenderTime = cachedData['time'] as DateTime;
      
      if (now.difference(lastRenderTime).inSeconds < 60) {
        return cachedData['widget'] as Widget;
      }
    }
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        final thumbnailWidget = FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(color: placeholderColor);
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              );
            } catch (e) {
              return _buildDefaultThumbnail();
            }
          },
        );
        
        // 缓存生成的缩略图和当前时间
        _thumbnailCache[item.filePath] = {
          'widget': thumbnailWidget,
          'time': now
        };
        
        return thumbnailWidget;
      }
    }

    final defaultThumbnail = _buildDefaultThumbnail();
    
    // 缓存默认缩略图和当前时间
    _thumbnailCache[item.filePath] = {
      'widget': defaultThumbnail,
      'time': now
    };
    
    return defaultThumbnail;
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: ThemeColorUtils.overlayColor(context,
          darkOpacity: 0.12, lightOpacity: 0.08),
      child: Center(
        child: Icon(Icons.video_library,
            color: ThemeColorUtils.tertiaryForeground(context), size: 32),
      ),
    );
  }

  void _onRecommendedItemTap(RecommendedItem item) {
    if (item.source == RecommendedItemSource.placeholder) return;
    
    if (item.source == RecommendedItemSource.jellyfin) {
      _navigateToJellyfinDetail(item.id);
    } else if (item.source == RecommendedItemSource.emby) {
      _navigateToEmbyDetail(item.id);
    } else if (item.source == RecommendedItemSource.local) {
      // 对于本地媒体库项目，使用animeId直接打开详情页
      if (item.id.contains(RegExp(r'^\d+$'))) {
        final animeId = int.tryParse(item.id);
        if (animeId != null) {
          AnimeDetailPage.show(context, animeId).then((result) {
            if (result != null) {
              // 刷新观看历史
              Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
              // 🔥 修复Flutter状态错误：使用addPostFrameCallback
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _loadData();
                }
              });
            }
          });
        }
      }
    }
  }

  void _onJellyfinItemTap(JellyfinMediaItem item) {
    _navigateToJellyfinDetail(item.id);
  }

  void _onEmbyItemTap(EmbyMediaItem item) {
    _navigateToEmbyDetail(item.id);
  }

  void _onLocalAnimeItemTap(LocalAnimeItem item) {
    // 打开动画详情页
    AnimeDetailPage.show(context, item.animeId).then((result) {
      if (result != null) {
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    });
  }

  // 已移除旧的创建本地动画项目的重量级方法，改为快速路径+后台补齐。

  void _navigateToJellyfinDetail(String jellyfinId) {
    MediaServerDetailPage.showJellyfin(context, jellyfinId).then((result) async {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
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
        } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
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
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _navigateToEmbyDetail(String embyId) {
    MediaServerDetailPage.showEmby(context, embyId).then((result) async {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
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
    } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
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
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
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

  // 导航到媒体库-库管理页面
  void _navigateToMediaLibraryManagement() {
    debugPrint('[DashboardHomePage] 准备导航到媒体库-库管理页面');
    
    // 先发送子标签切换请求，避免Widget销毁后无法访问
    try {
      final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      tabChangeNotifier.changeToMediaLibrarySubTab(1); // 直接切换到库管理标签
      debugPrint('[DashboardHomePage] 已发送子标签切换请求');
    } catch (e) {
      debugPrint('[DashboardHomePage] 发送子标签切换请求失败: $e');
    }
    
    // 然后切换到媒体库页面
    MainPageState? mainPageState = MainPageState.of(context);
    if (mainPageState != null && mainPageState.globalTabController != null) {
      // 切换到媒体库页面（索引2）
      if (mainPageState.globalTabController!.index != 2) {
        mainPageState.globalTabController!.animateTo(2);
        debugPrint('[DashboardHomePage] 直接调用了globalTabController.animateTo(2)');
      } else {
        debugPrint('[DashboardHomePage] globalTabController已经在媒体库页面');
        // 如果已经在媒体库页面，立即触发子标签切换
        try {
          final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
          tabChangeNotifier.changeToMediaLibrarySubTab(1);
          debugPrint('[DashboardHomePage] 已在媒体库页面，立即触发子标签切换');
        } catch (e) {
          debugPrint('[DashboardHomePage] 立即触发子标签切换失败: $e');
        }
      }
    } else {
      debugPrint('[DashboardHomePage] 无法找到MainPageState或globalTabController');
      // 如果直接访问失败，使用TabChangeNotifier作为备选方案
      try {
        final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
        tabChangeNotifier.changeToMediaLibrarySubTab(1); // 直接切换到媒体库-库管理标签
        debugPrint('[DashboardHomePage] 备选方案: 使用TabChangeNotifier请求切换到媒体库-库管理标签');
      } catch (e) {
        debugPrint('[DashboardHomePage] TabChangeNotifier也失败: $e');
      }
    }
  }
  
  // 构建页面指示器（分离出来避免不必要的重建），支持点击和悬浮效果
  Widget _buildPageIndicator({bool fullWidth = false, int count = 5}) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    return Positioned(
      bottom: 16,
      left: 0,
      // 手机全宽；桌面只在左侧PageView区域显示：总宽度的2/3减去间距
      right: fullWidth ? 0 : (MediaQuery.of(context).size.width - 32) / 3 + 12,
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: _heroBannerIndexNotifier,
          builder: (context, currentIndex, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (index) {
                final bool isHovered = _hoveredIndicatorIndex == index;
                final bool isSelected = currentIndex == index;
                double size;
                if (isSelected && isHovered) {
                  size = 16.0; // 选中且悬浮时最大
                } else if (isHovered) {
                  size = 12.0; // 仅悬浮时变大
                } else {
                  size = 8.0; // 默认大小
                }

                return MouseRegion(
                  onEnter: (event) => setState(() => _hoveredIndicatorIndex = index),
                  onExit: (event) => setState(() => _hoveredIndicatorIndex = null),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // 点击圆点时切换到对应页面
                      _stopAutoSwitch();
                      _currentHeroBannerIndex = index;
                      _heroBannerIndexNotifier.value = index;
                      _heroBannerPageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      Timer(const Duration(seconds: 3), () {
                        _resumeAutoSwitch();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: size,
                      height: size,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? primaryColor
                            : (isHovered
                                ? primaryColor.withOpacity(0.7)
                                : secondaryColor.withOpacity(0.5)),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  
  // 获取高清图片的方法
  Future<String?> _getHighQualityImage(int animeId, BangumiAnime animeDetail) async {
    try {
      // 优先尝试本地缓存中的 bangumiId/bangumiUrl，避免再请求弹弹play
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'bangumi_detail_$animeId';
        final String? cachedString = prefs.getString(cacheKey);
        if (cachedString != null) {
          final data = json.decode(cachedString);
          final animeData = data['animeDetail'] as Map<String, dynamic>?;
          final bangumi = data['bangumi'] as Map<String, dynamic>?;
          String? cachedBangumiId;
          // 1) 直接字段
          if (bangumi != null && bangumi['bangumiId'] != null && bangumi['bangumiId'].toString().isNotEmpty) {
            cachedBangumiId = bangumi['bangumiId'].toString();
          }
          // 2) 从 bangumiUrl 解析
          if (cachedBangumiId == null) {
            final String? bangumiUrl = (bangumi?['bangumiUrl'] as String?) ?? (animeData?['bangumiUrl'] as String?);
            if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
              final RegExp regex = RegExp(r'bangumi\.tv/subject/(\d+)');
              final match = regex.firstMatch(bangumiUrl);
              if (match != null) {
                cachedBangumiId = match.group(1);
              }
            }
          }
          if (cachedBangumiId != null && cachedBangumiId.isNotEmpty) {
            final bangumiImageUrl = await _getBangumiHighQualityImage(cachedBangumiId);
            if (bangumiImageUrl != null && bangumiImageUrl.isNotEmpty) {
              debugPrint('从缓存的Bangumi信息获取到高清图片: $bangumiImageUrl');
              return bangumiImageUrl;
            }
          }
        }
      } catch (_) {}

      // 首先尝试从弹弹play获取bangumi ID
      String? bangumiId = await _getBangumiIdFromDandanplay(animeId);
      
      if (bangumiId != null && bangumiId.isNotEmpty) {
        // 如果获取到bangumi ID，尝试从Bangumi API获取高清图片
        final bangumiImageUrl = await _getBangumiHighQualityImage(bangumiId);
        if (bangumiImageUrl != null && bangumiImageUrl.isNotEmpty) {
          debugPrint('从Bangumi API获取到高清图片: $bangumiImageUrl');
          return bangumiImageUrl;
        }
      }
      
      // 如果Bangumi API失败，回退到弹弹play的图片
      if (animeDetail.imageUrl.isNotEmpty) {
        debugPrint('回退到弹弹play图片: ${animeDetail.imageUrl}');
        return animeDetail.imageUrl;
      }
      
  debugPrint('未能获取到任何图片 (animeId: $animeId)');
      return null;
    } catch (e) {
      debugPrint('获取高清图片失败 (animeId: $animeId): $e');
      // 出错时回退到弹弹play的图片
      return animeDetail.imageUrl;
    }
  }
  
  // 从弹弹play API获取bangumi ID
  Future<String?> _getBangumiIdFromDandanplay(int animeId) async {
    try {
      // 使用弹弹play的番剧详情API获取bangumi ID
      final Map<String, dynamic> result = await DandanplayService.getBangumiDetails(animeId);
      
      if (result['success'] == true && result['bangumi'] != null) {
        final bangumi = result['bangumi'] as Map<String, dynamic>;
        
        // 检查是否有bangumiUrl，从中提取ID
        final String? bangumiUrl = bangumi['bangumiUrl'] as String?;
        if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
          // 从URL中提取bangumi ID: https://bangumi.tv/subject/123456
          final RegExp regex = RegExp(r'bangumi\.tv/subject/(\d+)');
          final match = regex.firstMatch(bangumiUrl);
          if (match != null) {
            final bangumiId = match.group(1);
            debugPrint('从弹弹play获取到bangumi ID: $bangumiId');
            return bangumiId;
          }
        }
        
        // 也检查是否直接有bangumiId字段
        final dynamic directBangumiId = bangumi['bangumiId'];
        if (directBangumiId != null) {
          final String bangumiIdStr = directBangumiId.toString();
          if (bangumiIdStr.isNotEmpty && bangumiIdStr != '0') {
            debugPrint('从弹弹play直接获取到bangumi ID: $bangumiIdStr');
            return bangumiIdStr;
          }
        }
      }
      
      debugPrint('弹弹play未返回有效的bangumi ID (animeId: $animeId)');
      return null;
    } catch (e) {
      debugPrint('从弹弹play获取bangumi ID失败 (animeId: $animeId): $e');
      return null;
    }
  }
  
  // 从Bangumi API获取高清图片
  Future<String?> _getBangumiHighQualityImage(String bangumiId) async {
    try {
      // 使用Bangumi API的图片接口获取large尺寸的图片
      // GET /v0/subjects/{subject_id}/image?type=large
      final String imageApiUrl = 'https://api.bgm.tv/v0/subjects/$bangumiId/image?type=large';
      
      debugPrint('请求Bangumi图片API: $imageApiUrl');
      
      final response = await http.head(
        Uri.parse(imageApiUrl),
        headers: {
          'User-Agent': 'NipaPlay/1.0',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 302) {
        // Bangumi API返回302重定向到实际图片URL
        final String? location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          debugPrint('Bangumi API重定向到: $location');
          return location;
        }
      } else if (response.statusCode == 200) {
        // 有些情况下可能直接返回200
        return imageApiUrl;
      }
      
      debugPrint('Bangumi图片API响应异常: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('从Bangumi API获取图片失败 (bangumiId: $bangumiId): $e');
      return null;
    }
  }

  // 升级为高清图片（后台异步处理）
  Future<void> _upgradeToHighQualityImages(List<dynamic> candidates, List<RecommendedItem> currentItems) async {
    debugPrint('开始后台升级为高清图片...');
    
    if (candidates.isEmpty || currentItems.isEmpty) {
      debugPrint('无候选项目或当前项目，跳过高清图片升级');
      return;
    }
    
    // 为每个候选项目升级图片
    final upgradeFutures = <Future<void>>[];
    
    for (int i = 0; i < candidates.length && i < currentItems.length; i++) {
      final candidate = candidates[i];
      final currentItem = currentItems[i];
      
      upgradeFutures.add(_upgradeItemToHighQuality(candidate, currentItem, i));
    }
    
    // 异步处理所有升级，不阻塞UI
    Future.wait(upgradeFutures, eagerError: false).then((_) {
      debugPrint('所有推荐图片升级完成');
    }).catchError((e) {
      debugPrint('升级推荐图片时发生错误: $e');
    });
  }
  
  // 升级单个项目为高清图片
  Future<void> _upgradeItemToHighQuality(dynamic candidate, RecommendedItem currentItem, int index) async {
    try {
      RecommendedItem? upgradedItem;
      
      if (candidate is JellyfinMediaItem) {
        // Jellyfin项目 - 获取高清图片和详细信息
        final jellyfinService = JellyfinService.instance;
        
        // 并行获取背景图片、Logo图片和详细信息
        final results = await Future.wait([
          _tryGetJellyfinImage(jellyfinService, candidate.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
          _tryGetJellyfinImage(jellyfinService, candidate.id, ['Logo', 'Thumb']),
          _getJellyfinItemSubtitle(jellyfinService, candidate),
        ]);
        
        final backdropUrl = results[0];
        final logoUrl = results[1];
        final subtitle = results[2];
        
        // 如果获取到了更好的图片或信息，创建升级版本
        if (backdropUrl != currentItem.backgroundImageUrl || 
            logoUrl != currentItem.logoImageUrl ||
            subtitle != currentItem.subtitle) {
          upgradedItem = RecommendedItem(
            id: currentItem.id,
            title: currentItem.title,
            subtitle: subtitle ?? currentItem.subtitle,
            backgroundImageUrl: backdropUrl ?? currentItem.backgroundImageUrl,
            logoImageUrl: logoUrl ?? currentItem.logoImageUrl,
            source: currentItem.source,
            rating: currentItem.rating,
          );
        }
        
      } else if (candidate is EmbyMediaItem) {
        // Emby项目 - 获取高清图片和详细信息
        final embyService = EmbyService.instance;
        
        // 并行获取背景图片、Logo图片和详细信息
        final results = await Future.wait([
          _tryGetEmbyImage(embyService, candidate.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
          _tryGetEmbyImage(embyService, candidate.id, ['Logo', 'Thumb']),
          _getEmbyItemSubtitle(embyService, candidate),
        ]);
        
        final backdropUrl = results[0];
        final logoUrl = results[1];
        final subtitle = results[2];
        
        // 如果获取到了更好的图片或信息，创建升级版本
        if (backdropUrl != currentItem.backgroundImageUrl || 
            logoUrl != currentItem.logoImageUrl ||
            subtitle != currentItem.subtitle) {
          upgradedItem = RecommendedItem(
            id: currentItem.id,
            title: currentItem.title,
            subtitle: subtitle ?? currentItem.subtitle,
            backgroundImageUrl: backdropUrl ?? currentItem.backgroundImageUrl,
            logoImageUrl: logoUrl ?? currentItem.logoImageUrl,
            source: currentItem.source,
            rating: currentItem.rating,
          );
        }
        
      } else if (candidate is WatchHistoryItem) {
        // 本地媒体库项目 - 获取高清图片和详细信息
        String? highQualityImageUrl;
        String? detailedSubtitle;
        
        if (candidate.animeId != null) {
          try {
            // 先尝试使用持久化缓存，避免重复请求网络
            final prefs = await SharedPreferences.getInstance();
            final persisted = prefs.getString('$_localPrefsKeyPrefix${candidate.animeId!}');

            final persistedLooksHQ = persisted != null && persisted.isNotEmpty && _looksHighQualityUrl(persisted);

            if (persistedLooksHQ) {
              highQualityImageUrl = persisted;
            } else {
              // 获取详细信息和高清图片
              final bangumiService = BangumiService.instance;
              final animeDetail = await bangumiService.getAnimeDetails(candidate.animeId!);
              detailedSubtitle = animeDetail.summary?.isNotEmpty == true
                  ? animeDetail.summary!
                      .replaceAll('<br>', ' ')
                      .replaceAll('<br/>', ' ')
                      .replaceAll('<br />', ' ')
                      .replaceAll('```', '')
                  : null;
              
              // 获取高清图片
              highQualityImageUrl = await _getHighQualityImage(candidate.animeId!, animeDetail);

              // 将获取到的高清图持久化，避免后续重复请求
              if (highQualityImageUrl != null && highQualityImageUrl.isNotEmpty) {
                _localImageCache[candidate.animeId!] = highQualityImageUrl;
                try {
                  await prefs.setString('$_localPrefsKeyPrefix${candidate.animeId!}', highQualityImageUrl);
                } catch (_) {}
              } else if (persisted != null && persisted.isNotEmpty) {
                // 如果没拿到更好的，只能继续沿用已持久化的（即使它可能是 medium），避免空图
                highQualityImageUrl = persisted;
              }
            }
          } catch (e) {
            debugPrint('获取本地媒体高清信息失败 (animeId: ${candidate.animeId}): $e');
          }
        }
        
        // 如果获取到了更好的图片或信息，创建升级版本
        if (highQualityImageUrl != currentItem.backgroundImageUrl ||
            detailedSubtitle != currentItem.subtitle) {
          upgradedItem = RecommendedItem(
            id: currentItem.id,
            title: currentItem.title,
            subtitle: detailedSubtitle ?? currentItem.subtitle,
            backgroundImageUrl: highQualityImageUrl ?? currentItem.backgroundImageUrl,
            logoImageUrl: currentItem.logoImageUrl,
            source: currentItem.source,
            rating: currentItem.rating,
          );
        }
      }
      
      // 如果有升级版本，更新UI
      if (upgradedItem != null && mounted) {
        setState(() {
          if (index < _recommendedItems.length) {
            _recommendedItems[index] = upgradedItem!;
          }
        });
        
        // CachedNetworkImageWidget 会自动处理图片预加载和缓存
        
        debugPrint('项目 ${upgradedItem.title} 已升级为高清版本');
      }
      
    } catch (e) {
      debugPrint('升级项目 $index 为高清版本失败: $e');
    }
  }

  // 经验性判断一个图片URL是否"看起来"是高清图
  bool _looksHighQualityUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('bgm.tv') || lower.contains('type=large') || lower.contains('original')) {
      return true;
    }
    if (lower.contains('medium') || lower.contains('small')) {
      return false;
    }
    // 解析 width= 参数
    final widthMatch = RegExp(r'[?&]width=(\d+)').firstMatch(lower);
    if (widthMatch != null) {
      final w = int.tryParse(widthMatch.group(1)!);
      if (w != null && w >= 1000) return true;
    }
    // 否则未知，默认当作高清，避免不必要的重复网络请求
    return true;
  }
  


  // 已移除老的图片下载缓存函数，现在使用 CachedNetworkImageWidget 的内置缓存系统

  // 辅助方法：尝试获取Jellyfin图片 - 带验证与回退，按优先级返回第一个有效URL
  Future<String?> _tryGetJellyfinImage(JellyfinService service, String itemId, List<String> imageTypes) async {
    // 先构建候选URL列表
    final List<MapEntry<String, String>> candidates = [];
    for (final imageType in imageTypes) {
      try {
        final url = imageType == 'Backdrop'
            ? service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95)
            : service.getImageUrl(itemId, type: imageType);
        if (url.isNotEmpty) {
          candidates.add(MapEntry(imageType, url));
        }
      } catch (e) {
        debugPrint('Jellyfin构建${imageType}图片URL失败: $e');
      }
    }

    if (candidates.isEmpty) {
      debugPrint('Jellyfin无法构建任何图片URL');
      return null;
    }

    // 并行验证所有候选URL
    final validations = await Future.wait(candidates.map((entry) async {
      final ok = await _validateImageUrl(entry.value);
      return ok ? entry : null;
    }));

    // 按优先级返回第一个有效的
    for (final t in imageTypes) {
      for (final res in validations) {
        if (res != null && res.key == t) {
          debugPrint('Jellyfin获取到${t}有效图片: ${res.value.substring(0, math.min(100, res.value.length))}...');
          return res.value;
        }
      }
    }

    debugPrint('Jellyfin未找到任何可用图片，尝试类型: ${imageTypes.join(", ")}');
    return null;
  }

  // 辅助方法：尝试获取Emby图片 - 带验证与回退，按优先级返回第一个有效URL
  Future<String?> _tryGetEmbyImage(EmbyService service, String itemId, List<String> imageTypes) async {
    final List<MapEntry<String, String>> candidates = [];
    for (final imageType in imageTypes) {
      try {
        final url = imageType == 'Backdrop'
            ? service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95)
            : service.getImageUrl(itemId, type: imageType);
        if (url.isNotEmpty) {
          candidates.add(MapEntry(imageType, url));
        }
      } catch (e) {
        debugPrint('Emby构建${imageType}图片URL失败: $e');
      }
    }

    if (candidates.isEmpty) {
      debugPrint('Emby无法构建任何图片URL');
      return null;
    }

    final validations = await Future.wait(candidates.map((entry) async {
      final ok = await _validateImageUrl(entry.value);
      return ok ? entry : null;
    }));

    for (final t in imageTypes) {
      for (final res in validations) {
        if (res != null && res.key == t) {
          debugPrint('Emby获取到${t}有效图片: ${res.value.substring(0, math.min(100, res.value.length))}...');
          return res.value;
        }
      }
    }

    debugPrint('Emby未找到任何可用图片，尝试类型: ${imageTypes.join(", ")}');
    return null;
  }

  // 辅助方法：验证图片URL是否有效（HEAD校验，确保非404并且为图片）
  Future<bool> _validateImageUrl(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('图片验证超时', const Duration(seconds: 2)),
      );

      if (response.statusCode != 200) return false;
      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.startsWith('image/')) return false;

      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        final len = int.tryParse(contentLength);
        if (len != null && len < 100) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // 辅助方法：获取Jellyfin项目简介
  Future<String> _getJellyfinItemSubtitle(JellyfinService service, JellyfinMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    } catch (e) {
      debugPrint('获取Jellyfin详细信息失败: $e');
      return item.overview?.isNotEmpty == true ? item.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    }
  }

  // 辅助方法：获取Emby项目简介
  Future<String> _getEmbyItemSubtitle(EmbyService service, EmbyMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    } catch (e) {
      debugPrint('获取Emby详细信息失败: $e');
      return item.overview?.isNotEmpty == true ? item.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    }
  }


  
  // 构建滚动按钮
  Widget _buildScrollButtons(ScrollController controller, double itemWidth) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollLeft = controller.hasClients && controller.offset > 0;
              return _buildScrollButton(
                icon: Icons.chevron_left,
                onTap: canScrollLeft ? () => _scrollToPrevious(controller, itemWidth) : null,
                enabled: canScrollLeft,
              );
            },
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollRight = controller.hasClients && 
                  controller.offset < controller.position.maxScrollExtent;
              return _buildScrollButton(
                icon: Icons.chevron_right,
                onTap: canScrollRight ? () => _scrollToNext(controller, itemWidth) : null,
                enabled: canScrollRight,
              );
            },
          ),
        ],
      ),
    );
  }
  
  // 构建单个滚动按钮
  Widget _buildScrollButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final enabledBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.25, lightOpacity: 0.18);
    final disabledBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.15, lightOpacity: 0.1);
    final enabledBorder = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.35, lightOpacity: 0.18);
    final disabledBorder = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.2, lightOpacity: 0.12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled ? enabledBackground : disabledBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? enabledBorder : disabledBorder,
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? onTap : null,
              child: Center(
                child: Icon(
                  icon,
                  color: enabled
                      ? primaryColor
                      : secondaryColor.withOpacity(0.6),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 滚动到上一页
  void _scrollToPrevious(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = math.max(0.0, controller.offset - scrollDistance);
    
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // 滚动到下一页
  void _scrollToNext(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = controller.offset + scrollDistance;
    final maxScrollExtent = controller.position.maxScrollExtent;
    
    // 如果目标位置超过了最大滚动范围，就滚动到最大位置
    final finalTargetOffset = targetOffset > maxScrollExtent ? maxScrollExtent : targetOffset;
    
    controller.animateTo(
      finalTargetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

// 推荐内容数据模型
class RecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? backgroundImageUrl;
  final String? logoImageUrl;
  final RecommendedItemSource source;
  final double? rating;

  RecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.backgroundImageUrl,
    this.logoImageUrl,
    required this.source,
    this.rating,
  });
}

enum RecommendedItemSource {
  jellyfin,
  emby,
  local,
  placeholder,
}

// 本地动画项目数据模型
class LocalAnimeItem {
  final int animeId;
  final String animeName;
  final String? imageUrl;
  final String? backdropImageUrl;
  final DateTime addedTime; // 改为添加时间
  final WatchHistoryItem latestEpisode;

  LocalAnimeItem({
    required this.animeId,
    required this.animeName,
    this.imageUrl,
    this.backdropImageUrl,
    required this.addedTime, // 改为添加时间
    required this.latestEpisode,
  });
}
