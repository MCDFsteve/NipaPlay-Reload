import 'package:fvp/mdk.dart' if (dart.library.html) 'package:nipaplay/utils/mock_mdk.dart' as mdk; // MDK import is isolated here
import './abstract_player.dart';
import './mdk_player_adapter.dart';
import './video_player_adapter.dart'; // 导入新的适配器
import './media_kit_player_adapter.dart'; // 导入新的MediaKit适配器
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // 用于 debugPrint
import 'package:nipaplay/utils/system_resource_monitor.dart'; // 导入系统资源监控器
import 'dart:async'; // 导入dart:async库

// Define available player types if you plan to support more than one.
// For now, it defaults to MDK or could take a parameter.
enum PlayerKernelType {
  mdk,
  videoPlayer, // 添加 video_player 内核类型
  mediaKit, // 添加 media_kit 内核类型
  // otherPlayer,
}

class PlayerFactory {
  static const String _playerKernelTypeKey = 'player_kernel_type';
  static PlayerKernelType? _cachedKernelType;
  static bool _hasLoadedSettings = false;

  // 添加一个StreamController来广播内核切换事件
  static final StreamController<PlayerKernelType> _kernelChangeController = StreamController<PlayerKernelType>.broadcast();
  static Stream<PlayerKernelType> get onKernelChanged => _kernelChangeController.stream;
  
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
      
      if (kernelTypeIndex != null && kernelTypeIndex < PlayerKernelType.values.length) {
        _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
        debugPrint('[PlayerFactory] 预加载内核设置: ${_cachedKernelType.toString()}');
      } else {
        _cachedKernelType = PlayerKernelType.mediaKit;
        debugPrint('[PlayerFactory] 无内核设置，使用默认: MDK');
      }
      
      _hasLoadedSettings = true;
    } catch (e) {
      debugPrint('[PlayerFactory] 初始化读取设置出错: $e');
      _cachedKernelType = PlayerKernelType.mediaKit;
      _hasLoadedSettings = true;
    }
  }
  
  // 同步加载设置
  static void _loadSettingsSync() {
    try {
      // 这里没有真正同步，仅使用默认值，确保后续异步加载会更新缓存值
      _cachedKernelType = PlayerKernelType.mediaKit;
      _hasLoadedSettings = true;
      
      // 异步加载正确设置并更新缓存
      SharedPreferences.getInstance().then((prefs) {
        final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
        if (kernelTypeIndex != null && kernelTypeIndex < PlayerKernelType.values.length) {
          _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
          debugPrint('[PlayerFactory] 异步更新内核设置: ${_cachedKernelType.toString()}');
        }
      });
      
      debugPrint('[PlayerFactory] 同步设置临时默认值: MDK');
    } catch (e) {
      debugPrint('[PlayerFactory] 同步加载设置出错: $e');
      _cachedKernelType = PlayerKernelType.mediaKit;
    }
  }
  
  // 获取当前内核设置
  static PlayerKernelType getKernelType() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedKernelType ?? PlayerKernelType.mediaKit;
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
      // case PlayerKernelType.otherPlayer:
      //   // return OtherPlayerAdapter(ThirdPartyPlayerApi());
      //   throw UnimplementedError('Other player types not yet supported.');
      default:
        // Fallback or throw error
        debugPrint('[PlayerFactory] 未知播放器内核类型，默认使用 MediaKit');
        return MediaKitPlayerAdapter();
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
      String kernelTypeName;
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
        default:
          kernelTypeName = "未知";
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