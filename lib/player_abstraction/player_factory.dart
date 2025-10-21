import './abstract_player.dart';
import './mdk_player_adapter.dart';
import './video_player_adapter.dart'; // 导入新的适配器
import './media_kit_player_adapter.dart'; // 导入新的MediaKit适配器
import './ohos_player_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // 用于 debugPrint
import 'package:nipaplay/utils/platform_utils.dart' show Platform;
import 'package:nipaplay/utils/system_resource_monitor.dart'; // 导入系统资源监控器
import 'dart:async'; // 导入dart:async库

// Define available player types if you plan to support more than one.
// For now, it defaults to MDK or could take a parameter.
enum PlayerKernelType {
  mdk,
  videoPlayer, // 添加 video_player 内核类型
  mediaKit, // 添加 media_kit 内核类型
  ohosNative, // 添加 Harmony 原生内核
  // otherPlayer,
}

class PlayerFactory {
  static const String _playerKernelTypeKey = 'player_kernel_type';
  static PlayerKernelType? _cachedKernelType;
  static bool _hasLoadedSettings = false;

  // 添加一个StreamController来广播内核切换事件
  static final StreamController<PlayerKernelType> _kernelChangeController =
      StreamController<PlayerKernelType>.broadcast();
  static Stream<PlayerKernelType> get onKernelChanged =>
      _kernelChangeController.stream;

  static bool get _isHarmonyPlatform {
    if (kIsWeb) {
      return false;
    }
    final os = Platform.operatingSystem.toLowerCase();
    return os == 'ohos' || os == 'openharmony';
  }

  static PlayerKernelType _defaultKernel() {
    return _isHarmonyPlatform
        ? PlayerKernelType.ohosNative
        : PlayerKernelType.mediaKit;
  }

  // 初始化方法，在应用启动时调用
  static Future<void> initialize() async {
    if (kIsWeb) {
      _cachedKernelType = PlayerKernelType.videoPlayer;
      _hasLoadedSettings = true;
      debugPrint('[PlayerFactory] Web平台，强制使用 Video Player 内核');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);

      if (kernelTypeIndex != null &&
          kernelTypeIndex < PlayerKernelType.values.length) {
        _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
        debugPrint('[PlayerFactory] 预加载内核设置: ${_cachedKernelType.toString()}');
      } else {
        _cachedKernelType = _defaultKernel();
        debugPrint(
            '[PlayerFactory] 无内核设置，使用默认: ${_cachedKernelType.toString()}');
      }

      if (_isHarmonyPlatform &&
          _cachedKernelType != PlayerKernelType.ohosNative) {
        debugPrint('[PlayerFactory] Harmony 平台强制切换为原生播放器内核');
        _cachedKernelType = PlayerKernelType.ohosNative;
      }

      _hasLoadedSettings = true;
    } catch (e) {
      debugPrint('[PlayerFactory] 初始化读取设置出错: $e');
      _cachedKernelType = _defaultKernel();
      _hasLoadedSettings = true;
    }
  }

  // 同步加载设置
  static void _loadSettingsSync() {
    try {
      // 这里没有真正同步，仅使用默认值，确保后续异步加载会更新缓存值
      _cachedKernelType = _defaultKernel();
      _hasLoadedSettings = true;

      // 异步加载正确设置并更新缓存
      SharedPreferences.getInstance().then((prefs) {
        final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
        if (kernelTypeIndex != null &&
            kernelTypeIndex < PlayerKernelType.values.length) {
          _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
          debugPrint(
              '[PlayerFactory] 异步更新内核设置: ${_cachedKernelType.toString()}');
        }
        if (_isHarmonyPlatform &&
            _cachedKernelType != PlayerKernelType.ohosNative) {
          debugPrint('[PlayerFactory] Harmony 平台异步强制应用原生播放器内核');
          _cachedKernelType = PlayerKernelType.ohosNative;
        }
      });

      debugPrint('[PlayerFactory] 同步设置临时默认值: ${_cachedKernelType.toString()}');
    } catch (e) {
      debugPrint('[PlayerFactory] 同步加载设置出错: $e');
      _cachedKernelType = _defaultKernel();
    }
  }

  // 获取当前内核设置
  static PlayerKernelType getKernelType() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    final kernel = _cachedKernelType ?? _defaultKernel();
    if (_isHarmonyPlatform && kernel != PlayerKernelType.ohosNative) {
      return PlayerKernelType.ohosNative;
    }
    return kernel;
  }

  // 创建播放器实例
  AbstractPlayer createPlayer({PlayerKernelType? kernelType}) {
    // 如果是Web平台，强制使用VideoPlayer
    if (kIsWeb) {
      debugPrint('[PlayerFactory] Web平台，强制创建 Video Player 播放器');
      return VideoPlayerAdapter();
    }

    // 如果没有指定内核类型，从缓存或设置中读取
    kernelType ??= getKernelType();

    if (_isHarmonyPlatform) {
      debugPrint('[PlayerFactory] Harmony 平台创建原生播放器实例');
      return OhosPlayerAdapter();
    }

    switch (kernelType) {
      case PlayerKernelType.mdk:
        debugPrint('[PlayerFactory] 创建 MDK 播放器');
        return MdkPlayerAdapter();
      case PlayerKernelType.videoPlayer:
        debugPrint('[PlayerFactory] 创建 Video Player 播放器');
        return VideoPlayerAdapter();
      case PlayerKernelType.mediaKit:
        debugPrint('[PlayerFactory] 创建 Media Kit 播放器');
        return MediaKitPlayerAdapter();
      case PlayerKernelType.ohosNative:
        debugPrint('[PlayerFactory] 创建 Harmony 原生播放器');
        return OhosPlayerAdapter();
      // case PlayerKernelType.otherPlayer:
      //   // return OtherPlayerAdapter(ThirdPartyPlayerApi());
      //   throw UnimplementedError('Other player types not yet supported.');
    }
  }

  // 保存内核设置
  static Future<void> saveKernelType(PlayerKernelType type) async {
    if (kIsWeb) {
      debugPrint('[PlayerFactory] Web平台不支持更改播放器内核');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_playerKernelTypeKey, type.index);
      _cachedKernelType = type;
      debugPrint('[PlayerFactory] 保存内核设置: ${type.toString()}');

      // 更新系统资源监视器的播放器内核类型
      String kernelTypeName = "未知";
      switch (type) {
        case PlayerKernelType.mdk:
          kernelTypeName = "MDK";
          break;
        case PlayerKernelType.videoPlayer:
          kernelTypeName = "Video Player";
          break;
        case PlayerKernelType.mediaKit:
          kernelTypeName = "Libmpv";
          break;
        case PlayerKernelType.ohosNative:
          kernelTypeName = "Harmony Native";
          break;
      }

      // 设置显示名称
      SystemResourceMonitor().setPlayerKernelType(kernelTypeName);

      // 确保完整更新监视器显示 - 调用更新方法
      SystemResourceMonitor().updatePlayerKernelType();

      // 广播内核切换事件
      _kernelChangeController.add(type);
    } catch (e) {
      debugPrint('[PlayerFactory] 保存内核设置出错: $e');
    }
  }
}
