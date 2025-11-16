library video_player_state;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:fvp/mdk.dart';  // Commented out
import '../player_abstraction/player_abstraction.dart'; // <-- NEW IMPORT
import '../player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
// Added import for subtitle parser
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

import 'globals.dart' as globals;
import 'dart:convert';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/auto_sync_service.dart'; // 导入自动云同步服务
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/emby_playback_sync_service.dart';
import 'package:nipaplay/services/timeline_danmaku_service.dart'; // 导入时间轴弹幕服务
import 'media_info_helper.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/watch_history_database.dart'; // 导入观看记录数据库
import 'package:image/image.dart' as img;
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

import 'package:path/path.dart' as p; // Added import for path package
import 'package:nipaplay/utils/ios_container_path_fixer.dart';
// Added for getTemporaryDirectory
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import '../providers/watch_history_provider.dart';
import 'danmaku_parser.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart'; // Added screen_brightness
import 'package:nipaplay/widgets/nipaplay_theme/brightness_indicator.dart'; // Added import for BrightnessIndicator widget
import 'package:nipaplay/widgets/nipaplay_theme/volume_indicator.dart'; // Added import for VolumeIndicator widget
import 'package:nipaplay/widgets/nipaplay_theme/seek_indicator.dart'; // Added import for SeekIndicator widget
import 'package:volume_controller/volume_controller.dart';

import 'subtitle_manager.dart'; // 导入字幕管理器
import 'package:nipaplay/services/file_picker_service.dart'; // Added import for FilePickerService
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/cupertino/player/cupertino_brightness_indicator.dart';
import 'package:nipaplay/widgets/cupertino/player/cupertino_volume_indicator.dart';
import 'package:nipaplay/widgets/cupertino/player/cupertino_seek_indicator.dart';
import 'decoder_manager.dart'; // 导入解码器管理器
import 'package:nipaplay/services/episode_navigation_service.dart'; // 导入剧集导航服务
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'storage_service.dart'; // Added import for StorageService
import 'screen_orientation_manager.dart';
import 'anime4k_shader_manager.dart';
// 导入MediaKitPlayerAdapter
import '../player_abstraction/player_factory.dart'; // 播放器工厂
import '../danmaku_abstraction/danmaku_kernel_factory.dart'; // 弹幕内核工厂
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_overlay.dart'; // 导入GPU弹幕覆盖层
import 'package:flutter/scheduler.dart'; // 添加Ticker导入
import 'danmaku_dialog_manager.dart'; // 导入弹幕对话框管理器
import 'hotkey_service.dart'; // Added import for HotkeyService
import 'player_kernel_manager.dart'; // 导入播放器内核管理器
import 'shared_remote_history_helper.dart';

part 'video_player_state/video_player_state_metadata.dart';
part 'video_player_state/video_player_state_initialization.dart';
part 'video_player_state/video_player_state_player_setup.dart';
part 'video_player_state/video_player_state_playback_controls.dart';
part 'video_player_state/video_player_state_capture.dart';
part 'video_player_state/video_player_state_preferences.dart';
part 'video_player_state/video_player_state_danmaku.dart';
part 'video_player_state/video_player_state_subtitles.dart';
part 'video_player_state/video_player_state_streaming.dart';
part 'video_player_state/video_player_state_navigation.dart';

enum PlayerStatus {
  idle, // 空闲状态
  loading, // 加载中
  recognizing, // 识别中
  ready, // 准备就绪
  playing, // 播放中
  paused, // 暂停
  error, // 错误
  disposed // 已释放
}

enum PlaybackEndAction {
  autoNext,
  pause,
  exitPlayer,
}

extension PlaybackEndActionDisplay on PlaybackEndAction {
  static PlaybackEndAction fromPrefs(String? value) {
    switch (value) {
      case 'pause':
        return PlaybackEndAction.pause;
      case 'exitPlayer':
        return PlaybackEndAction.exitPlayer;
      case 'autoNext':
      default:
        return PlaybackEndAction.autoNext;
    }
  }

  String get prefsValue {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return 'autoNext';
      case PlaybackEndAction.pause:
        return 'pause';
      case PlaybackEndAction.exitPlayer:
        return 'exitPlayer';
    }
  }

  String get label {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return '自动播放下一话';
      case PlaybackEndAction.pause:
        return '播放完停留在本集';
      case PlaybackEndAction.exitPlayer:
        return '播放结束返回上一页';
    }
  }

  String get description {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return '播放结束后自动倒计时并播放下一话';
      case PlaybackEndAction.pause:
        return '播放结束后保持在当前页面，不再自动跳转';
      case PlaybackEndAction.exitPlayer:
        return '播放结束后自动返回到视频列表或上一页';
    }
  }
}

class _VideoDimensionSnapshot {
  final int? srcWidth;
  final int? srcHeight;
  final int? displayWidth;
  final int? displayHeight;

  const _VideoDimensionSnapshot({
    required this.srcWidth,
    required this.srcHeight,
    required this.displayWidth,
    required this.displayHeight,
  });

  bool get hasSource =>
      srcWidth != null && srcWidth! > 0 && srcHeight != null && srcHeight! > 0;

  bool get hasDisplay =>
      displayWidth != null &&
      displayWidth! > 0 &&
      displayHeight != null &&
      displayHeight! > 0;
}

class VideoPlayerState extends ChangeNotifier implements WindowListener {
  late Player player; // 改为 late 修饰，使用 Player.create() 方法创建
  BuildContext? _context;
  StreamSubscription? _playerKernelChangeSubscription; // 播放器内核切换事件订阅
  StreamSubscription? _danmakuKernelChangeSubscription; // 弹幕内核切换事件订阅
  PlayerStatus _status = PlayerStatus.idle;
  List<String> _statusMessages = []; // 修改为列表存储多个状态消息
  bool _showControls = true;
  bool _showRightMenu = false; // 控制右侧菜单显示状态
  bool _isFullscreen = false;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  final bool _isErrorStopping = false; // <<< ADDED THIS FIELD
  double _aspectRatio = 16 / 9; // 默认16:9，但会根据视频实际比例更新
  String? _currentVideoPath;
  String? _currentActualPlayUrl; // 存储实际播放URL，用于判断转码状态
  String _danmakuOverlayKey = 'idle'; // 弹幕覆盖层的稳定key
  Timer? _uiUpdateTimer; // UI更新定时器（包含位置保存和数据持久化功能）
  // 观看记录节流：记录上一次更新所处的10秒分桶，避免同一时间窗内重复写DB与通知Provider
  int _lastHistoryUpdateBucket = -1;
  // （保留占位，若未来要做更细粒度同步节流可再启用）
  // 🔥 新增：Ticker相关字段
  Ticker? _uiUpdateTicker;
  int _lastTickTime = 0;
  // 节流：UI刷新与位置保存
  int _lastUiNotifyMs = 0; // 上次UI刷新时间
  int _lastSaveTimeMs = 0; // 上次保存时间
  int _lastSavedPositionMs = -1; // 上次已持久化的位置
  final int _uiUpdateIntervalMs = 120; // UI刷新最小间隔（约8.3fps）
  final int _positionSaveIntervalMs = 3000; // 位置保存最小间隔
  final int _positionSaveDeltaThresholdMs = 2000; // 位置保存位移阈值
  // 高频时间轴：提供给弹幕的独立时间源（毫秒）
  final ValueNotifier<double> _playbackTimeMs = ValueNotifier<double>(0);
  Timer? _hideControlsTimer;
  Timer? _hideMouseTimer;
  Timer? _autoHideTimer;
  Timer? _screenshotTimer; // 添加截图定时器
  bool _isControlsHovered = false;
  bool _isSeeking = false;
  final FocusNode _focusNode = FocusNode();

  // 添加重置标志，防止在重置过程中更新历史记录
  bool _isResetting = false;
  final String _lastVideoKey = 'last_video_path';
  final String _lastPositionKey = 'last_video_position';
  final String _videoPositionsKey = 'video_positions';
  final String _playbackEndActionKey = 'playback_end_action';

  Duration? _lastSeekPosition; // 添加这个字段来记录最后一次seek的位置
  PlaybackEndAction _playbackEndAction = PlaybackEndAction.autoNext;
  List<Map<String, dynamic>> _danmakuList = [];

  // 多轨道弹幕系统
  final Map<String, Map<String, dynamic>> _danmakuTracks = {};
  final Map<String, bool> _danmakuTrackEnabled = {};
  final String _controlBarHeightKey = 'control_bar_height';
  double _controlBarHeight = 20.0; // 默认高度
  final String _minimalProgressBarEnabledKey =
      'minimal_progress_bar_enabled';
  bool _minimalProgressBarEnabled = false; // 默认关闭
  final String _minimalProgressBarColorKey =
      'minimal_progress_bar_color';
  int _minimalProgressBarColor = 0xFFFF7274; // 默认颜色 #ff7274
  final String _showDanmakuDensityChartKey =
      'show_danmaku_density_chart';
  bool _showDanmakuDensityChart = false; // 默认关闭弹幕密度曲线图
  final String _danmakuOpacityKey = 'danmaku_opacity';
  double _danmakuOpacity = 1.0; // 默认透明度
  final String _danmakuVisibleKey = 'danmaku_visible';
  bool _danmakuVisible = true; // 默认显示弹幕
  final String _mergeDanmakuKey = 'merge_danmaku';
  bool _mergeDanmaku = false; // 默认不合并弹幕
  final String _danmakuStackingKey = 'danmaku_stacking';
  bool _danmakuStacking = false; // 默认不启用弹幕堆叠

  final String _anime4kProfileKey = 'anime4k_profile';
  Anime4KProfile _anime4kProfile = Anime4KProfile.off;
  List<String> _anime4kShaderPaths = const <String>[];
  final Map<String, String> _anime4kRecommendedMpvOptions = const {
    'scale': 'ewa_lanczossharp',
    'cscale': 'ewa_lanczossoft',
    'dscale': 'mitchell',
    'sigmoid-upscaling': 'yes',
    'deband': 'yes',
    'scale-antiring': '0.7',
  };
  final Map<String, String> _anime4kDefaultMpvOptions = const {
    'scale': 'bilinear',
    'cscale': 'bilinear',
    'dscale': 'mitchell',
    'sigmoid-upscaling': 'no',
    'deband': 'no',
    'scale-antiring': '0.0',
  };

  // 弹幕类型屏蔽
  final String _blockTopDanmakuKey = 'block_top_danmaku';
  final String _blockBottomDanmakuKey = 'block_bottom_danmaku';
  final String _blockScrollDanmakuKey = 'block_scroll_danmaku';
  bool _blockTopDanmaku = false; // 默认不屏蔽顶部弹幕
  bool _blockBottomDanmaku = false; // 默认不屏蔽底部弹幕
  bool _blockScrollDanmaku = false; // 默认不屏蔽滚动弹幕

  // 时间轴告知弹幕轨道状态
  bool _isTimelineDanmakuEnabled = true;

  // 弹幕屏蔽词
  final String _danmakuBlockWordsKey = 'danmaku_block_words';
  List<String> _danmakuBlockWords = []; // 弹幕屏蔽词列表
  int _totalDanmakuCount = 0; // 添加一个字段来存储总弹幕数

  // 弹幕字体大小设置
  final String _danmakuFontSizeKey = 'danmaku_font_size';
  double _danmakuFontSize = 0.0; // 默认为0表示使用系统默认值

  // 弹幕轨道显示区域设置
  final String _danmakuDisplayAreaKey = 'danmaku_display_area';
  double _danmakuDisplayArea = 1.0; // 默认全屏显示（1.0=全部，0.67=2/3，0.33=1/3）

  // 弹幕速度设置
  final String _danmakuSpeedMultiplierKey = 'danmaku_speed_multiplier';
  final double _minDanmakuSpeedMultiplier = 0.5;
  final double _maxDanmakuSpeedMultiplier = 2.0;
  final double _baseDanmakuScrollDurationSeconds = 10.0;
  double _danmakuSpeedMultiplier = 1.0; // 默认标准速度

  // 添加播放速度相关状态
  final String _playbackRateKey = 'playback_rate';
  double _playbackRate = 1.0; // 默认1倍速
  bool _isSpeedBoostActive = false; // 是否正在倍速播放（长按状态）
  double _normalPlaybackRate = 1.0; // 正常播放速度
  final String _speedBoostRateKey = 'speed_boost_rate';
  double _speedBoostRate = 2.0; // 长按倍速播放的倍率，默认2倍速

  // 快进快退时间设置
  final String _seekStepSecondsKey = 'seek_step_seconds';
  int _seekStepSeconds = 10; // 默认10秒

  // 跳过时间设置
  final String _skipSecondsKey = 'skip_seconds';
  int _skipSeconds = 90; // 默认90秒

  dynamic danmakuController; // 添加弹幕控制器属性
  Duration _videoDuration = Duration.zero; // 添加视频时长状态
  bool _isFullscreenTransitioning = false;
  String? _currentThumbnailPath; // 添加当前缩略图路径
  String? _currentVideoHash; // 缓存当前视频的哈希值，避免重复计算
  bool _isCapturingFrame = false; // 是否正在截图，避免并发截图
  final List<VoidCallback> _thumbnailUpdateListeners = []; // 缩略图更新监听器列表
  String? _animeTitle; // 添加动画标题属性
  String? _episodeTitle; // 添加集数标题属性

  // 从 historyItem 传入的弹幕 ID（用于保持弹幕关联）
  int? _episodeId; // 存储从 historyItem 传入的 episodeId
  int? _animeId; // 存储从 historyItem 传入的 animeId
  WatchHistoryItem? _initialHistoryItem; // 记录首次传入的历史记录，便于初始化时复用元数据

  // 字幕管理器
  late SubtitleManager _subtitleManager;

  // Screen Brightness Control
  double _currentBrightness =
      0.5; // Default, will be updated by _loadInitialBrightness
  double _initialDragBrightness = 0.5; // To store brightness when drag starts
  bool _isBrightnessIndicatorVisible = false;
  Timer? _brightnessIndicatorTimer;
  OverlayEntry? _brightnessOverlayEntry; // <<< ADDED THIS LINE

  // Volume Control State
  static const Duration _volumeSaveDebounceDuration =
      Duration(milliseconds: 400);
  final String _playerVolumeKey = 'player_volume';
  double _currentVolume = 0.5; // Default volume
  double _initialDragVolume = 0.5;
  bool _isVolumeIndicatorVisible = false;
  Timer? _volumeIndicatorTimer;
  OverlayEntry? _volumeOverlayEntry;
  Timer? _volumePersistenceTimer;
  VolumeController? _systemVolumeController;
  StreamSubscription<double>? _systemVolumeSubscription;
  bool _isSystemVolumeUpdating = false;

  // Horizontal Seek Drag State
  bool _isSeekingViaDrag = false;
  Duration _dragSeekStartPosition = Duration.zero;
  double _accumulatedDragDx = 0.0;
  Timer?
      _seekIndicatorTimer; // For showing a temporary seek UI (not implemented yet)
  OverlayEntry?
      _seekOverlayEntry; // For a temporary seek UI (not implemented yet)
  Duration _dragSeekTargetPosition =
      Duration.zero; // To show target position during drag
  bool _isSeekIndicatorVisible = false; // <<< ADDED THIS LINE

  // 右边缘悬浮菜单状态
  bool _isRightEdgeHovered = false;
  Timer? _rightEdgeHoverTimer;
  OverlayEntry? _hoverSettingsMenuOverlay;

  // 加载状态相关
  bool _isInFinalLoadingPhase = false; // 是否处于最终加载阶段，用于优化动画性能

  // 解码器管理器
  late DecoderManager _decoderManager;

  bool _hasInitialScreenshot = false; // 添加标记跟踪是否已进行第一次播放截图

  // 平板设备菜单栏隐藏状态
  bool _isAppBarHidden = false;

  // 新增回调：当发生严重播放错误且应弹出时调用
  Function()? onSeriousPlaybackErrorAndShouldPop;

  // 获取菜单栏隐藏状态
  bool get isAppBarHidden => _isAppBarHidden;

  // 检查是否为平板设备（使用globals中的判定逻辑）
  bool get isTablet => globals.isTablet;


  VideoPlayerState() {
    // 创建临时播放器实例，后续会被 _initialize 中的异步创建替换
    player = Player();
    _subtitleManager = SubtitleManager(player: player);
    _decoderManager = DecoderManager(player: player);
    onExternalSubtitleAutoLoaded = _onExternalSubtitleAutoLoaded;
    _initialize();
  }

  void _scheduleVolumePersistence({bool immediate = false}) {
    if (!globals.isPhone) return;
    _volumePersistenceTimer?.cancel();
    if (immediate) {
      _volumePersistenceTimer = null;
      unawaited(_savePlayerVolumePreference(_currentVolume));
      return;
    }
    _volumePersistenceTimer =
        Timer(_volumeSaveDebounceDuration, () {
      _volumePersistenceTimer = null;
      unawaited(_savePlayerVolumePreference(_currentVolume));
    });
  }

  Future<void> _savePlayerVolumePreference(double volume) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
          _playerVolumeKey, volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('保存播放器音量失败: $e');
    }
  }

  Future<void> _initializeSystemVolumeController() async {
    if (!globals.isPhone) return;
    try {
      _systemVolumeController ??= VolumeController.instance;
      _systemVolumeController!.showSystemUI = false;
      _systemVolumeSubscription?.cancel();
      _systemVolumeSubscription = _systemVolumeController!.addListener(
        _handleExternalSystemVolumeChange,
        fetchInitialVolume: true,
      );
    } catch (e) {
      debugPrint('初始化系统音量控制失败: $e');
    }
  }

  void _handleExternalSystemVolumeChange(double volume) {
    if (!globals.isPhone) return;
    if (_isSystemVolumeUpdating) return;
    final double normalized = volume.clamp(0.0, 1.0);
    if ((_currentVolume - normalized).abs() < 0.001) {
      return;
    }
    _currentVolume = normalized;
    _initialDragVolume = normalized;
    try {
      player.volume = normalized;
    } catch (e) {
      debugPrint('同步系统音量到播放器失败: $e');
    }
    _showVolumeIndicator();
    _scheduleVolumePersistence();
    notifyListeners();
  }

  Future<void> _setSystemVolume(double volume) async {
    if (!globals.isPhone) return;
    if (_systemVolumeController == null) return;
    _isSystemVolumeUpdating = true;
    try {
      await _systemVolumeController!
          .setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('设置系统音量失败: $e');
    } finally {
      Future.microtask(() {
        _isSystemVolumeUpdating = false;
      });
    }
  }

  // Getters
  PlayerStatus get status => _status;
  List<String> get statusMessages => _statusMessages;
  bool get showControls => _showControls;
  bool get showRightMenu => _showRightMenu;
  bool get isFullscreen => _isFullscreen;
  double get progress => _progress;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get error => _error;
  double get aspectRatio => _aspectRatio;
  bool get hasVideo =>
      _status == PlayerStatus.ready ||
      _status == PlayerStatus.playing ||
      _status == PlayerStatus.paused;
  bool get isPaused => _status == PlayerStatus.paused;
  FocusNode get focusNode => _focusNode;
  PlaybackEndAction get playbackEndAction => _playbackEndAction;
  List<Map<String, dynamic>> get danmakuList => _danmakuList;
  Map<String, Map<String, dynamic>> get danmakuTracks => _danmakuTracks;
  Map<String, bool> get danmakuTrackEnabled => _danmakuTrackEnabled;
  double get controlBarHeight => _controlBarHeight;
  bool get minimalProgressBarEnabled => _minimalProgressBarEnabled;
  Color get minimalProgressBarColor => Color(_minimalProgressBarColor);
  bool get showDanmakuDensityChart => _showDanmakuDensityChart;
  double get danmakuOpacity => _danmakuOpacity;
  bool get danmakuVisible => _danmakuVisible;
  bool get mergeDanmaku => _mergeDanmaku;
  double get danmakuFontSize => _danmakuFontSize;
  double get danmakuDisplayArea => _danmakuDisplayArea;
  double get danmakuSpeedMultiplier => _danmakuSpeedMultiplier;
  double get danmakuScrollDurationSeconds =>
      _baseDanmakuScrollDurationSeconds / _danmakuSpeedMultiplier;
  bool get danmakuStacking => _danmakuStacking;
  Anime4KProfile get anime4kProfile => _anime4kProfile;
  bool get isAnime4KEnabled => _anime4kProfile != Anime4KProfile.off;
  bool get isAnime4KSupported => _supportsAnime4KForCurrentPlayer();
  List<String> get anime4kShaderPaths => List.unmodifiable(_anime4kShaderPaths);
  Duration get videoDuration => _videoDuration;
  String? get currentVideoPath => _currentVideoPath;
  String? get currentActualPlayUrl => _currentActualPlayUrl; // 当前实际播放URL
  String get danmakuOverlayKey => _danmakuOverlayKey; // 弹幕覆盖层的稳定key
  String? get animeTitle => _animeTitle; // 添加动画标题getter
  String? get episodeTitle => _episodeTitle; // 添加集数标题getter
  int? get animeId => _animeId; // 添加动画ID getter
  int? get episodeId => _episodeId; // 添加剧集ID getter

  // 获取时间轴告知弹幕轨道状态
  bool get isTimelineDanmakuEnabled => _isTimelineDanmakuEnabled;


  // 字幕管理器相关的getter
  SubtitleManager get subtitleManager => _subtitleManager;
  String? get currentExternalSubtitlePath =>
      _subtitleManager.currentExternalSubtitlePath;
  Map<String, Map<String, dynamic>> get subtitleTrackInfo =>
      _subtitleManager.subtitleTrackInfo;

  // Brightness Getters
  double get currentScreenBrightness => _currentBrightness;
  bool get isBrightnessIndicatorVisible => _isBrightnessIndicatorVisible;

  // Volume Getters
  double get currentSystemVolume => _currentVolume;
  bool get isVolumeUIVisible =>
      _isVolumeIndicatorVisible; // Renamed for clarity

  // Seek Indicator Getter
  bool get isSeekIndicatorVisible =>
      _isSeekIndicatorVisible; // <<< ADDED THIS GETTER
  Duration get dragSeekTargetPosition =>
      _dragSeekTargetPosition; // <<< ADDED THIS GETTER

  // 弹幕类型屏蔽Getters
  bool get blockTopDanmaku => _blockTopDanmaku;
  bool get blockBottomDanmaku => _blockBottomDanmaku;
  bool get blockScrollDanmaku => _blockScrollDanmaku;
  List<String> get danmakuBlockWords => _danmakuBlockWords;
  int get totalDanmakuCount => _totalDanmakuCount;

  // 获取是否处于最终加载阶段
  bool get isInFinalLoadingPhase => _isInFinalLoadingPhase;

  // 解码器管理器相关的getter
  DecoderManager get decoderManager => _decoderManager;

  // 获取播放器内核名称（通过静态方法）
  String get playerCoreName => player.getPlayerKernelName();

  bool get isNipaKernel => playerCoreName == 'NipaPlay';
  ValueListenable<ui.Image?>? get nipaImageStream => player.nipaImageStream;

  // 播放速度相关的getter
  double get playbackRate => _playbackRate;
  bool get isSpeedBoostActive => _isSpeedBoostActive;
  double get speedBoostRate => _speedBoostRate;

  // 快进快退时间的getter
  int get seekStepSeconds => _seekStepSeconds;
  // 跳过时间的getter
  int get skipSeconds => _skipSeconds;

  // 右边缘悬浮菜单的getter
  bool get isRightEdgeHovered => _isRightEdgeHovered;
  // 对外暴露的高频播放时间
  ValueListenable<double> get playbackTimeMs => _playbackTimeMs;





  @override
  void dispose() {
    // 在销毁前进行一次截图
    if (hasVideo) {
      _captureConditionalScreenshot("销毁前");
    }

    // Jellyfin同步：如果是Jellyfin流媒体，停止同步
    if (_currentVideoPath != null &&
        _currentVideoPath!.startsWith('jellyfin://')) {
      try {
        final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
        final syncService = JellyfinPlaybackSyncService();
        // 注意：dispose方法不能是async，所以这里使用同步方式处理
        // 在dispose中我们只清理同步服务状态，不发送网络请求
        syncService.dispose();
      } catch (e) {
        debugPrint('Jellyfin播放销毁同步失败: $e');
      }
    }

    // Emby同步：如果是Emby流媒体，停止同步
    if (_currentVideoPath != null && _currentVideoPath!.startsWith('emby://')) {
      try {
        final itemId = _currentVideoPath!.replaceFirst('emby://', '');
        final syncService = EmbyPlaybackSyncService();
        // 注意：dispose方法不能是async，所以这里使用同步方式处理
        // 在dispose中我们只清理同步服务状态，不发送网络请求
        syncService.dispose();
      } catch (e) {
        debugPrint('Emby播放销毁同步失败: $e');
      }
    }

    // 退出视频播放时触发自动云同步
    if (_currentVideoPath != null) {
      try {
        // 使用Future.microtask在下一个事件循环中异步执行，避免dispose中的异步问题
        Future.microtask(() async {
          await AutoSyncService.instance.syncOnPlaybackEnd();
          debugPrint('退出视频时云同步成功');
        });
      } catch (e) {
        debugPrint('退出视频时云同步失败: $e');
      }
    }

    _scheduleVolumePersistence(immediate: true);
    _volumePersistenceTimer?.cancel();
    _systemVolumeSubscription?.cancel();
    _systemVolumeSubscription = null;
    _systemVolumeController?.removeListener();
    _systemVolumeController = null;
    player.dispose();
    _focusNode.dispose();
    _uiUpdateTimer?.cancel(); // 清理UI更新定时器

    // 🔥 新增：清理Ticker资源
    if (_uiUpdateTicker != null) {
      _uiUpdateTicker!.stop();
      _uiUpdateTicker!.dispose();
      _uiUpdateTicker = null;
    }

    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
    _autoHideTimer?.cancel();
    _screenshotTimer?.cancel();
    _brightnessIndicatorTimer
        ?.cancel(); // Already cancelled here or in _hideBrightnessIndicator
    if (_brightnessOverlayEntry != null) {
      // ADDED THIS BLOCK
      _brightnessOverlayEntry!.remove();
      _brightnessOverlayEntry = null;
    }
    _volumeIndicatorTimer?.cancel(); // <<< ADDED
    if (_volumeOverlayEntry != null) {
      // <<< ADDED
      _volumeOverlayEntry!.remove();
      _volumeOverlayEntry = null;
    }
    _seekIndicatorTimer?.cancel(); // <<< ADDED
    if (_seekOverlayEntry != null) {
      // <<< ADDED
      _seekOverlayEntry!.remove();
      _seekOverlayEntry = null;
    }
    _rightEdgeHoverTimer?.cancel(); // 清理右边缘悬浮定时器
    if (_hoverSettingsMenuOverlay != null) {
      // 清理悬浮设置菜单
      _hoverSettingsMenuOverlay!.remove();
      _hoverSettingsMenuOverlay = null;
    }
    WakelockPlus.disable();
    //debugPrint("Wakelock disabled on dispose.");
    if (!kIsWeb) {
      windowManager.removeListener(this);
    }
    _playerKernelChangeSubscription?.cancel(); // 取消播放器内核切换事件订阅
    _danmakuKernelChangeSubscription?.cancel(); // 取消弹幕内核切换事件订阅
    super.dispose();
  }

  // 设置窗口管理器监听器
  void _setupWindowManagerListener() {
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'enter-full-screen' || eventName == 'leave-full-screen') {
      windowManager.isFullScreen().then((isFullscreen) {
        if (isFullscreen != _isFullscreen) {
          _isFullscreen = isFullscreen;
          notifyListeners();
        }
      });
    }
  }

  @override
  void onWindowEnterFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (isFullscreen != _isFullscreen) {
        _isFullscreen = isFullscreen;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (!isFullscreen && _isFullscreen) {
        _isFullscreen = false;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowClose() async {
    // Changed from onWindowClose() async
    //debugPrint("VideoPlayerState: onWindowClose called. Saving position.");
    _saveCurrentPositionToHistory(); // Removed await as the method likely returns void
  }

  @override
  void onWindowDocked() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowUnDocked() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowUnmaximize() {}







  /// 获取当前时间窗口内的弹幕（分批加载/懒加载）
  List<Map<String, dynamic>> getActiveDanmakuList(double currentTime,
      {double window = 15.0}) {
    // 先过滤掉被屏蔽的弹幕
    final filteredDanmakuList = getFilteredDanmakuList();

    // 然后在过滤后的列表中查找时间窗口内的弹幕
    return filteredDanmakuList.where((d) {
      final t = d['time'] as double? ?? 0.0;
      return t >= currentTime - window && t <= currentTime + window;
    }).toList();
  }



  // 获取过滤后的弹幕列表
  List<Map<String, dynamic>> getFilteredDanmakuList() {
    return _danmakuList
        .where((danmaku) => !shouldBlockDanmaku(danmaku))
        .toList();
  }

  // 添加setter用于设置外部字幕自动加载回调
  set onExternalSubtitleAutoLoaded(Function(String, String)? callback) {
    _subtitleManager.onExternalSubtitleAutoLoaded = callback;
  }




  // 检查是否可以播放上一话
  bool get canPlayPreviousEpisode {
    if (_currentVideoPath == null) return false;

    final navigationService = EpisodeNavigationService.instance;

    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }

    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }

    // 如果是流媒体，可以使用简单导航（Jellyfin/Emby的adjacentTo API）
    if (navigationService.canUseStreamingNavigation(_currentVideoPath!)) {
      return true;
    }

    return false;
  }

  // 检查是否可以播放下一话
  bool get canPlayNextEpisode {
    if (_currentVideoPath == null) return false;

    final navigationService = EpisodeNavigationService.instance;

    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }

    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }

    // 如果是流媒体，可以使用简单导航（Jellyfin/Emby的adjacentTo API）
    if (navigationService.canUseStreamingNavigation(_currentVideoPath!)) {
      return true;
    }

    return false;
  }



}
