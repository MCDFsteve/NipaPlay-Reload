import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'debug_log_service.dart';

import 'package:nipaplay/utils/url_name_generator.dart';
import '../models/jellyfin_transcode_settings.dart';
import 'jellyfin_transcode_manager.dart';

class JellyfinService {
  static final JellyfinService instance = JellyfinService._internal();
  
  JellyfinService._internal();
  
  String? _serverUrl;
  String? _username;
  String? _password;
  String? _accessToken;
  String? _userId;
  bool _isConnected = false;
  List<JellyfinLibrary> _availableLibraries = [];
  List<String> _selectedLibraryIds = [];
  
  // 后端就绪标志与回调（当完成令牌验证与媒体库加载后触发）
  bool _isReady = false;
  bool get isReady => _isReady;
  final List<VoidCallback> _readyCallbacks = [];
  
  void addReadyListener(VoidCallback callback) {
    _readyCallbacks.add(callback);
  }
  
  void removeReadyListener(VoidCallback callback) {
    _readyCallbacks.remove(callback);
  }
  
  void _notifyReady() {
    for (final cb in _readyCallbacks) {
      try {
        cb();
      } catch (e) {
        DebugLogService().addLog('Jellyfin: ready 回调执行失败: $e');
      }
    }
  }
  
  // 多地址支持
  ServerProfile? _currentProfile;
  String? _currentAddressId;
  final MultiAddressServerService _multiAddressService = MultiAddressServerService.instance;

  // Client information cache
  String? _cachedClientInfo;

  // Transcode preferences cache (loaded once and updated by provider)
  bool _transcodeEnabledCache = false;
  JellyfinVideoQuality _defaultQualityCache = JellyfinVideoQuality.bandwidth5m;
  JellyfinTranscodeSettings _settingsCache = const JellyfinTranscodeSettings();

  // Get dynamic client information
  Future<String> _getClientInfo() async {
    if (_cachedClientInfo != null) {
      return _cachedClientInfo!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appName = packageInfo.appName.isNotEmpty ? packageInfo.appName : 'NipaPlay';
      final version = packageInfo.version.isNotEmpty ? packageInfo.version : '1.4.9';
      
      String platform = 'Flutter';
      if (!kIsWeb && !kDebugMode) {
        try {
          platform = Platform.operatingSystem;
          // Capitalize first letter
          platform = platform[0].toUpperCase() + platform.substring(1);
        } catch (e) {
          platform = 'Flutter';
        }
      }

      _cachedClientInfo = 'MediaBrowser Client="$appName", Device="$platform", DeviceId="$appName-$platform", Version="$version"';
      return _cachedClientInfo!;
    } catch (e) {
      // Fallback to static values
      _cachedClientInfo = 'MediaBrowser Client="NipaPlay", Device="Flutter", DeviceId="NipaPlay-Flutter", Version="1.4.9"';
      return _cachedClientInfo!;
    }
  }

  /// 获取服务器端的媒体技术元数据（容器/编解码器/Profile/Level/HDR/声道/码率等）
  /// 返回统一结构：
  /// {
  ///   'container': String?,
  ///   'video': {
  ///      'codec': String?, 'profile': String?, 'level': String?, 'bitDepth': int?,
  ///      'width': int?, 'height': int?, 'frameRate': num?, 'bitRate': int?,
  ///      'pixelFormat': String?, 'colorSpace': String?, 'colorTransfer': String?, 'colorPrimaries': String?,
  ///      'dynamicRange': String?
  ///   },
  ///   'audio': {
  ///      'codec': String?, 'channels': int?, 'channelLayout': String?,
  ///      'sampleRate': int?, 'bitRate': int?, 'language': String?
  ///   }
  /// }
  Future<Map<String, dynamic>> getServerMediaTechnicalInfo(String itemId) async {
    if (!_isConnected) {
      return {};
    }

    final Map<String, dynamic> result = {
      'container': null,
      'video': <String, dynamic>{},
      'audio': <String, dynamic>{},
    };

    try {
      // 1) 优先获取 PlaybackInfo，包含 MediaSources 与 MediaStreams（技术细节更全）
      final playbackResp = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId',
      );
      Map<String, dynamic>? firstSource;
      Map<String, dynamic>? videoStream;
      Map<String, dynamic>? audioStream;

      if (playbackResp.statusCode == 200) {
        final pbData = json.decode(playbackResp.body);
        final mediaSources = pbData['MediaSources'];
        if (mediaSources is List && mediaSources.isNotEmpty) {
          firstSource = Map<String, dynamic>.from(mediaSources.first);
          result['container'] = firstSource['Container'];
          final streams = firstSource['MediaStreams'];
          if (streams is List) {
            for (final s in streams) {
              if (s is Map && s['Type'] == 'Video' && videoStream == null) {
                videoStream = Map<String, dynamic>.from(s);
              } else if (s is Map && s['Type'] == 'Audio' && audioStream == null) {
                audioStream = Map<String, dynamic>.from(s);
              }
            }
          }
        }
      }

      // 2) 补充 Items 详情（可能带有 VideoRange 等目录级字段）
      Map<String, dynamic>? itemDetail;
      try {
        final itemResp = await _makeAuthenticatedRequest('/Users/$_userId/Items/$itemId');
        if (itemResp.statusCode == 200) {
          itemDetail = Map<String, dynamic>.from(json.decode(itemResp.body));
        }
      } catch (_) {}

      // 组装 video 信息
      final video = <String, dynamic>{
        'codec': videoStream?['Codec'] ?? firstSource?['VideoCodec'],
        'profile': videoStream?['Profile'],
        'level': videoStream?['Level']?.toString(),
        'bitDepth': videoStream?['BitDepth'],
        'width': videoStream?['Width'] ?? firstSource?['Width'],
        'height': videoStream?['Height'] ?? firstSource?['Height'],
        'frameRate': videoStream?['RealFrameRate'] ?? videoStream?['AverageFrameRate'],
        'bitRate': videoStream?['BitRate'] ?? firstSource?['Bitrate'],
        'pixelFormat': videoStream?['PixelFormat'],
        'colorSpace': videoStream?['ColorSpace'],
        'colorTransfer': videoStream?['ColorTransfer'],
        'colorPrimaries': videoStream?['ColorPrimaries'],
        'dynamicRange': videoStream?['VideoRange'] ?? itemDetail?['VideoRange'],
      };

      // 组装 audio 信息
      final audio = <String, dynamic>{
        'codec': audioStream?['Codec'] ?? firstSource?['AudioCodec'],
        'channels': audioStream?['Channels'],
        'channelLayout': audioStream?['ChannelLayout'],
        'sampleRate': audioStream?['SampleRate'],
        'bitRate': audioStream?['BitRate'] ?? firstSource?['AudioBitrate'],
        'language': audioStream?['Language'],
      };

      result['video'] = video;
      result['audio'] = audio;
      return result;
    } catch (e) {
      DebugLogService().addLog('JellyfinService: 获取媒体技术元数据失败: $e');
      return {};
    }
  }

  // Getters
  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  List<JellyfinLibrary> get availableLibraries => _availableLibraries;
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  
  Future<void> loadSavedSettings() async {
    if (kIsWeb) {
      _isConnected = false;
  _isReady = false;
      return;
    }
    
    // 初始化多地址服务
    await _multiAddressService.initialize();
    
    final prefs = await SharedPreferences.getInstance();
    
    // 尝试加载当前配置
    final profileId = prefs.getString('jellyfin_current_profile_id');
    if (profileId != null) {
      try {
        _currentProfile = _multiAddressService.getProfileById(profileId);
        if (_currentProfile != null) {
          _username = _currentProfile!.username;
          _accessToken = _currentProfile!.accessToken;
          _userId = _currentProfile!.userId;
          
          // 使用当前地址
          final currentAddress = _currentProfile!.currentAddress;
          if (currentAddress != null) {
            _serverUrl = currentAddress.normalizedUrl;
            _currentAddressId = currentAddress.id;
          }
        }
      } catch (e) {
        DebugLogService().addLog('Jellyfin: 加载配置失败: $e');
      }
    }
    
    // 兼容旧版本存储
    if (_currentProfile == null) {
      _serverUrl = prefs.getString('jellyfin_server_url');
      _username = prefs.getString('jellyfin_username');
      _accessToken = prefs.getString('jellyfin_access_token');
      _userId = prefs.getString('jellyfin_user_id');
    }
    
    _selectedLibraryIds = prefs.getStringList('jellyfin_selected_libraries') ?? [];
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      // 异步验证连接，不阻塞初始化流程
      _validateConnectionAsync();
    } else {
      _isConnected = false;
  _isReady = false;
    }

    // 预加载转码设置到本地缓存，避免在 getStreamUrl 中做异步操作
    try {
      final transMgr = JellyfinTranscodeManager.instance;
      await transMgr.initialize();
      _transcodeEnabledCache = await transMgr.isTranscodingEnabled();
      _defaultQualityCache = await transMgr.getDefaultVideoQuality();
  _settingsCache = await transMgr.getSettings();
      DebugLogService().addLog('Jellyfin: 已加载转码偏好 缓存 enabled=$_transcodeEnabledCache, quality=$_defaultQualityCache');
    } catch (e) {
      DebugLogService().addLog('Jellyfin: 加载转码偏好失败，使用默认值: $e');
      _transcodeEnabledCache = false;
      _defaultQualityCache = JellyfinVideoQuality.bandwidth5m;
  _settingsCache = const JellyfinTranscodeSettings();
    }
  }
  
  /// 异步验证连接状态，不阻塞主流程
  Future<void> _validateConnectionAsync() async {
    try {
      print('Jellyfin: 开始异步验证保存的连接信息...');
      // 尝试验证保存的令牌是否仍然有效，设置5秒超时
      final response = await _makeAuthenticatedRequest('/System/Info')
          .timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      
      print('Jellyfin: 令牌验证结果 - HTTP ${response.statusCode}, 连接状态: $_isConnected');
      
      if (_isConnected) {
        print('Jellyfin: 连接验证成功，正在加载媒体库...');
        // 加载可用媒体库
        await loadAvailableLibraries();
        print('Jellyfin: 媒体库加载完成，可用库数量: ${_availableLibraries.length}');
        // 通知连接状态变化
        _notifyConnectionStateChanged();
        // 设置后端就绪并发出就绪信号（使用 microtask，确保在前面的通知处理完成后触发）
        scheduleMicrotask(() {
          _isReady = true;
          _notifyReady();
        });
      } else {
        print('Jellyfin: 连接验证失败 - HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Jellyfin: 连接验证过程中发生异常: $e');
      _isConnected = false;
      _isReady = false;
    }
  }
  
  // 连接状态变化回调列表
  final List<Function(bool)> _connectionStateCallbacks = [];
  
  /// 添加连接状态变化监听器
  void addConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.add(callback);
  }
  
  /// 移除连接状态变化监听器
  void removeConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.remove(callback);
  }
  
  /// 通知连接状态变化
  void _notifyConnectionStateChanged() {
    for (final callback in _connectionStateCallbacks) {
      try {
        callback(_isConnected);
      } catch (e) {
        print('Jellyfin: 连接状态回调执行失败: $e');
      }
    }
  }
  
  Future<bool> connect(String serverUrl, String username, String password, {String? addressName}) async {
    // 初始化多地址服务
    await _multiAddressService.initialize();
    
    // 规范化URL
    final normalizedUrl = _normalizeUrl(serverUrl);
    
    try {
      // 先识别服务器
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: 'jellyfin',
        getServerId: _getJellyfinServerId,
      );
      
      ServerProfile? profile;
      
      if (identifyResult.success && identifyResult.existingProfile != null) {
        // 服务器已存在，添加新地址或使用现有地址
        profile = identifyResult.existingProfile!;
        
        // 检查是否需要添加新地址
        final hasAddress = profile.addresses.any(
          (addr) => addr.normalizedUrl == normalizedUrl,
        );
        
        if (!hasAddress) {
          profile = await _multiAddressService.addAddressToProfile(
            profileId: profile.id,
            url: normalizedUrl,
            name: UrlNameGenerator.generateAddressName(normalizedUrl, customName: addressName),
          );
        } else {
          print('JellyfinService: 地址已存在，使用现有配置');
        }
      } else if (identifyResult.isConflict) {
        // 检测到冲突：URL相同但serverId不同
        print('JellyfinService: 检测到冲突，抛出异常: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      } else if (identifyResult.success) {
        // 服务器识别成功但没有现有配置，创建新配置
        print('JellyfinService: 创建新的服务器配置');
        profile = await _multiAddressService.addProfile(
          serverName: await _getServerName(normalizedUrl) ?? 'Jellyfin服务器',
          serverType: 'jellyfin',
          url: normalizedUrl,
          username: username,
          serverId: identifyResult.serverId,
          addressName: UrlNameGenerator.generateAddressName(normalizedUrl, customName: addressName),
        );
      } else {
        // 服务器识别失败
        print('JellyfinService: 服务器识别失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法识别Jellyfin服务器');
      }
      
      if (profile == null) {
        throw Exception('无法创建服务器配置');
      }
      
      // 使用多地址尝试连接
      final connectionResult = await _multiAddressService.tryConnect(
        profile: profile,
        testConnection: (url) => _testJellyfinConnection(url, username, password),
      );
      
      if (connectionResult.success && connectionResult.profile != null) {
        _currentProfile = connectionResult.profile;
        _serverUrl = connectionResult.successfulUrl;
        _currentAddressId = connectionResult.successfulAddressId;
        _username = username;
        _password = password;
        
        // 执行完整的认证流程
        await _performAuthentication(_serverUrl!, username, password);
        
        // 只有在认证成功后才设置连接状态为true
        _isConnected = true;
        
        // 更新配置中的认证信息
        _currentProfile = _currentProfile!.copyWith(
          accessToken: _accessToken,
          userId: _userId,
        );
        await _multiAddressService.updateProfile(_currentProfile!);
        
        // 保存连接信息
        await _saveConnectionInfo();
        
        // 获取可用的媒体库列表
        if (!kIsWeb) {
          await loadAvailableLibraries();
        }
        // 连接流程结束，先通知连接状态变化，再通过 microtask 触发 ready，保证 ready 最后到达
        _notifyConnectionStateChanged();
        scheduleMicrotask(() {
          _isReady = true;
          _notifyReady();
        });
        
        return true;
      } else {
        throw Exception(connectionResult.error ?? '连接失败');
      }
    } catch (e) {
      print('JellyfinService: 连接过程中发生异常: $e');
      _isConnected = false;
      
      // 如果是服务器冲突错误，直接传递原始错误信息
      if (e.toString().contains('已被另一个') || e.toString().contains('已被占用')) {
        throw Exception(e.toString());
      }
      
      throw Exception('连接Jellyfin服务器失败: $e');
    }
  }
  
  /// 测试Jellyfin连接
  Future<bool> _testJellyfinConnection(String url, String username, String password) async {
    try {
      // 获取服务器信息
      final configResponse = await http.get(
        Uri.parse('$url/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      return configResponse.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// 执行完整的认证流程
  Future<void> _performAuthentication(String serverUrl, String username, String password) async {
    final clientInfo = await _getClientInfo();
    final authResponse = await http.post(
      Uri.parse('$serverUrl/Users/AuthenticateByName'),
      headers: {
        'Content-Type': 'application/json',
        'X-Emby-Authorization': clientInfo,
      },
      body: json.encode({
        'Username': username,
        'Pw': password,
      }),
    );
    
    if (authResponse.statusCode != 200) {
      throw Exception('认证失败: ${authResponse.statusCode}');
    }
    
    final authData = json.decode(authResponse.body);
    _accessToken = authData['AccessToken'];
    _userId = authData['User']['Id'];
  }
  
  /// 获取Jellyfin服务器ID，如果无法获取将抛出异常
  Future<String> _getJellyfinServerId(String url) async {
    try {
      final response = await http.get(
        Uri.parse('$url/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Id'] ?? data['ServerId'];
      }
      // 在HTTP状态码不为200时抛出详细错误
      throw Exception('获取Jellyfin服务器ID失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    } catch (e) {
      DebugLogService().addLog('获取Jellyfin服务器ID失败: $e');
      // 重新抛出异常，以便 identifyServer 捕获并返回详细错误
      rethrow;
    }
  }
  
  /// 获取服务器名称
  Future<String?> _getServerName(String url) async {
    try {
      final response = await http.get(
        Uri.parse('$url/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ServerName'];
      }
    } catch (e) {
      DebugLogService().addLog('获取Jellyfin服务器名称失败: $e');
    }
    return null;
  }
  

  
  /// 规范化URL
  String _normalizeUrl(String url) {
    String normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
  
  /// 保存连接信息
  Future<void> _saveConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存当前配置ID
    if (_currentProfile != null) {
      await prefs.setString('jellyfin_current_profile_id', _currentProfile!.id);
    }
    
    // 兼容旧版本，同时保存单地址信息
    await prefs.setString('jellyfin_server_url', _serverUrl!);
    await prefs.setString('jellyfin_username', _username!);
    await prefs.setString('jellyfin_access_token', _accessToken!);
    await prefs.setString('jellyfin_user_id', _userId!);
  }
  
  Future<void> disconnect() async {
    // 保存当前配置文件ID，用于删除
    final currentProfileId = _currentProfile?.id;
    
    _isConnected = false;
    _currentProfile = null;
    _currentAddressId = null;
    _serverUrl = null;
    _username = null;
    _password = null;
    _accessToken = null;
    _userId = null;
    _availableLibraries = [];
    _selectedLibraryIds = [];
  _isReady = false;
    
    // 清除保存的设置
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jellyfin_current_profile_id');
    await prefs.remove('jellyfin_server_url');
    await prefs.remove('jellyfin_username');
    await prefs.remove('jellyfin_access_token');
    await prefs.remove('jellyfin_user_id');
    await prefs.remove('jellyfin_selected_libraries');
    
    // 删除多地址配置文件
    if (currentProfileId != null) {
      try {
        await _multiAddressService.deleteProfile(currentProfileId);
        DebugLogService().addLog('JellyfinService: 已删除服务器配置文件 $currentProfileId');
      } catch (e) {
        DebugLogService().addLog('JellyfinService: 删除服务器配置文件失败: $e');
      }
    }
    

    
    // TODO: 清除播放同步服务中的数据（待实现）
    // 当前 JellyfinPlaybackSyncService 没有清除所有数据的方法
    // 可能需要在后续版本中添加相关方法
  }
  
  Future<void> loadAvailableLibraries() async {
    if (kIsWeb || !_isConnected || _userId == null) return;

    try {
      final response = await _makeAuthenticatedRequest('/UserViews?userId=$_userId');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        List<JellyfinLibrary> tempLibraries = [];
        for (var item in items) {
          if (item['CollectionType'] == 'tvshows' || item['CollectionType'] == 'movies') {
            final String libraryId = item['Id'];
            final String collectionType = item['CollectionType'];
            
            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
            
            final countResponse = await _makeAuthenticatedRequest(
                '/Items?parentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&Limit=0&Fields=ParentId');
            
            int itemCount = 0;
            if (countResponse.statusCode == 200) {
              final countData = json.decode(countResponse.body);
              itemCount = countData['TotalRecordCount'] ?? 0;
            }
            
            tempLibraries.add(JellyfinLibrary(
              id: item['Id'],
              name: item['Name'],
              type: item['CollectionType'], // Assuming 'CollectionType' maps to 'type'
              imageTagsPrimary: item['ImageTags']?['Primary'], // Safely access ImageTags
              totalItems: itemCount, 
            ));
          }
        }
        _availableLibraries = tempLibraries;
      }
    } catch (e) {
      print('Error loading available libraries: $e');
    }
  }
  
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    _selectedLibraryIds = libraryIds;
    
    // 保存选择的媒体库到SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('jellyfin_selected_libraries', _selectedLibraryIds);
  }
  
  // 按特定媒体库获取最新内容
  Future<List<JellyfinMediaItem>> getLatestMediaItemsByLibrary(
    String libraryId, {
    int limit = 20,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected) {
      return [];
    }
    
    try {
      // 默认排序参数
      final defaultSortBy = sortBy ?? 'DateCreated,SortName';
      final defaultSortOrder = sortOrder ?? 'Descending';
      
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
      
      final response = await _makeAuthenticatedRequest(
        '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&userId=$_userId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];
        
        return items
            .map((item) => JellyfinMediaItem.fromJson(item))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching media items for library $libraryId: $e');
    }
    
    return [];
  }
  
  // 按特定媒体库获取随机内容
  Future<List<JellyfinMediaItem>> getRandomMediaItemsByLibrary(
    String libraryId, {
    int limit = 20,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected) {
      return [];
    }
    
    try {
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
      
      // 使用Jellyfin的随机排序获取随机内容
      final response = await _makeAuthenticatedRequest(
        '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=Random&Limit=$limit&userId=$_userId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];
        
        return items
            .map((item) => JellyfinMediaItem.fromJson(item))
            .toList();
      }
    } catch (e) {
      print('Error fetching random media items for library $libraryId: $e');
    }
    
    return [];
  }
  
  Future<List<JellyfinMediaItem>> getLatestMediaItems({
    int limit = 99999,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty) {
      return [];
    }
    
    // 默认排序参数
    final defaultSortBy = sortBy ?? 'DateCreated,SortName';
    final defaultSortOrder = sortOrder ?? 'Descending';
    
    print('JellyfinService: 获取媒体项 - sortBy: $defaultSortBy, sortOrder: $defaultSortOrder');
    
    List<JellyfinMediaItem> allItems = [];
    
    // 从每个选中的媒体库获取最新内容
    for (String libraryId in _selectedLibraryIds) {
      try {
        // 首先获取媒体库信息以确定类型
        final libraryResponse = await _makeAuthenticatedRequest(
          '/Users/$_userId/Items/$libraryId'
        );
        
        if (libraryResponse.statusCode == 200) {
          final libraryData = json.decode(libraryResponse.body);
          final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
          
          // 根据媒体库类型选择不同的IncludeItemTypes
          String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
          
          final response = await _makeAuthenticatedRequest(
            '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&userId=$_userId'
          );
          
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final List<dynamic> items = data['Items'];
            
            List<JellyfinMediaItem> libraryItems = items
                .map((item) => JellyfinMediaItem.fromJson(item))
                .toList();
            
            allItems.addAll(libraryItems);
          }
        }
      } catch (e, stackTrace) {
        // Log the error and stack trace for debugging purposes
        print('Error processing library $libraryId: $e');
        print('Stack trace: $stackTrace');
      }
    }
    
    // 如果服务器端排序失败或需要客户端排序，则进行本地排序
    // 注意：当使用自定义排序时，我们依赖服务器端的排序结果
    if (sortBy == null && sortOrder == null) {
      // 默认情况下按最近添加日期排序
      allItems.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
    
    // 限制总数
    if (allItems.length > limit) {
      allItems = allItems.sublist(0, limit);
    }
    
    return allItems;
  }
  
  // 获取最新电影列表
  Future<List<JellyfinMovieInfo>> getLatestMovies({int limit = 99999}) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty) {
      return [];
    }
    
    List<JellyfinMovieInfo> allMovies = [];
    
    // 从每个选中的媒体库获取最新电影
    for (String libraryId in _selectedLibraryIds) {
      try {
        final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit&userId=$_userId'
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];
          
          List<JellyfinMovieInfo> libraryMovies = items
              .map((item) => JellyfinMovieInfo.fromJson(item))
              .toList();
          
          allMovies.addAll(libraryMovies);
        }
      } catch (e) {
        // Log the error for debugging purposes
        print('Error fetching movies for library $libraryId: $e');
      }
    }
    
    // 按最近添加日期排序
    allMovies.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    
    // 限制总数
    if (allMovies.length > limit) {
      allMovies = allMovies.sublist(0, limit);
    }
    
    return allMovies;
  }
  
  // 获取电影详情
  Future<JellyfinMovieInfo?> getMovieDetails(String movieId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$movieId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return JellyfinMovieInfo.fromJson(data);
      }
    } catch (e) {
      throw Exception('无法获取电影详情: $e');
    }
    
    return null;
  }
  
  Future<JellyfinMediaItemDetail> getMediaItemDetails(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Users/$_userId/Items/$itemId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return JellyfinMediaItemDetail.fromJson(data);
    } else {
      throw Exception('无法获取媒体详情');
    }
  }
  
  Future<List<JellyfinSeasonInfo>> getSeriesSeasons(String seriesId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Shows/$seriesId/Seasons?userId=$_userId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];
      
      List<JellyfinSeasonInfo> seasons = items
          .map((item) => JellyfinSeasonInfo.fromJson(item))
          .toList();
      
      // 按季节编号排序
      seasons.sort((a, b) => a.indexNumber?.compareTo(b.indexNumber ?? 0) ?? 0);
      
      return seasons;
    } else {
      throw Exception('无法获取剧集季信息');
    }
  }
  
  Future<List<JellyfinEpisodeInfo>> getSeasonEpisodes(String seriesId, String seasonId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Shows/$seriesId/Episodes?userId=$_userId&seasonId=$seasonId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];
      
      List<JellyfinEpisodeInfo> episodes = items
          .map((item) => JellyfinEpisodeInfo.fromJson(item))
          .toList();
      
      // 按剧集编号排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });
      
      return episodes;
    } else {
      throw Exception('无法获取季节剧集信息');
    }
  }
  
  // 获取单个剧集的详细信息
  Future<JellyfinEpisodeInfo?> getEpisodeDetails(String episodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$episodeId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return JellyfinEpisodeInfo.fromJson(data);
      }
    } catch (e) {
      throw Exception('无法获取剧集详情: $e');
    }
    
    return null;
  }
  
  // 获取媒体源信息（包含文件名、大小等信息）
  Future<Map<String, dynamic>> getMediaInfo(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      // 首先尝试使用File接口获取详细信息
      final response = await _makeAuthenticatedRequest(
        '/Items/$itemId/File'
      );
      
      final contentType = response.headers['content-type'];
      bool isJsonResponse = contentType != null && (contentType.contains('application/json') || contentType.contains('text/json'));
      
      if (response.statusCode == 200 && isJsonResponse) {
        final data = json.decode(response.body);
        debugPrint('媒体文件信息API响应 (JSON): $data');
        
        final fileName = data['Name'] ?? '';
        final fileSize = data['Size'] ?? 0;
        
        // 确保获取到有效数据
        if (fileName.isNotEmpty || fileSize > 0) {
          debugPrint('成功获取到媒体文件信息: 文件名=$fileName, 大小=$fileSize');
          return {
            'fileName': fileName,
            'path': data['Path'] ?? '',
            'size': fileSize,
            'dateCreated': data['DateCreated'] ?? '',
            'dateModified': data['DateModified'] ?? ''
          };
        }
      } else if (response.statusCode == 200 && !isJsonResponse) {
        debugPrint('媒体文件信息API响应 (non-JSON, status 200): Content-Type: $contentType. 将回退。');
        // 表明端点返回了文件本身，而不是元数据。
        // 无法从此获取文件名/文件大小，因此我们将继续回退。
      } else if (response.statusCode != 200) {
        debugPrint('媒体文件信息API请求失败: HTTP ${response.statusCode}. 将回退。');
      }
      // 如果File接口无法获取有效信息，尝试使用普通的Items接口
      final itemResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$itemId'
      );
      
      if (itemResponse.statusCode == 200) {
        final itemData = json.decode(itemResponse.body);
        debugPrint('媒体项目API响应获取到部分信息');
        
        String fileName = '';
        if (itemData['Name'] != null) {
          fileName = itemData['Name'];
          // 添加合适的文件扩展名
          if (!fileName.toLowerCase().endsWith('.mp4') && 
              !fileName.toLowerCase().endsWith('.mkv') &&
              !fileName.toLowerCase().endsWith('.avi')) {
            fileName += '.mp4';
          }
        }
        
        // 尝试从MediaSource获取文件大小
        int fileSize = 0;
        if (itemData['MediaSources'] != null && 
            itemData['MediaSources'] is List && 
            itemData['MediaSources'].isNotEmpty) {
          final mediaSource = itemData['MediaSources'][0];
          fileSize = mediaSource['Size'] ?? 0;
        }
        
        debugPrint('通过备选方法获取到媒体信息: 文件名=$fileName, 大小=$fileSize');
        return {
          'fileName': fileName,
          'path': itemData['Path'] ?? '',
          'size': fileSize,
          'dateCreated': itemData['DateCreated'] ?? '',
          'dateModified': itemData['DateModified'] ?? ''
        };
      }
      
      debugPrint('获取媒体信息失败: HTTP ${response.statusCode}');
      return {};
    } catch (e) {
      debugPrint('获取媒体信息错误: $e');
      return {};
    }
  }
  
  /// 获取相邻剧集（使用Jellyfin的adjacentTo参数作为简单的上下集导航）
  /// 返回当前剧集前后各一集的剧集列表，不依赖弹幕映射
  Future<List<JellyfinEpisodeInfo>> getAdjacentEpisodes(String currentEpisodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      // 使用adjacentTo参数获取相邻剧集，限制3个结果（上一集、当前集、下一集）
      final response = await _makeAuthenticatedRequest(
        '/Items?adjacentTo=$currentEpisodeId&limit=3&fields=Overview,MediaSources'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];
        
        final episodes = items
            .map((item) => JellyfinEpisodeInfo.fromJson(item))
            .toList();
        
        // 按集数排序确保顺序正确
        episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
        
        debugPrint('[JellyfinService] 获取到${episodes.length}个相邻剧集');
        return episodes;
      } else {
        debugPrint('[JellyfinService] 获取相邻剧集失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[JellyfinService] 获取相邻剧集出错: $e');
      return [];
    }
  }
  
  /// 简单获取下一集（不依赖弹幕映射）
  Future<JellyfinEpisodeInfo?> getNextEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex != -1 && currentIndex < adjacentEpisodes.length - 1) {
      final nextEpisode = adjacentEpisodes[currentIndex + 1];
      debugPrint('[JellyfinService] 找到下一集: ${nextEpisode.name}');
      return nextEpisode;
    }
    
    debugPrint('[JellyfinService] 没有找到下一集');
    return null;
  }
  
  /// 简单获取上一集（不依赖弹幕映射）
  Future<JellyfinEpisodeInfo?> getPreviousEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex > 0) {
      final previousEpisode = adjacentEpisodes[currentIndex - 1];
      debugPrint('[JellyfinService] 找到上一集: ${previousEpisode.name}');
      return previousEpisode;
    }
    
    debugPrint('[JellyfinService] 没有找到上一集');
    return null;
  }

  // 获取流媒体URL（向后兼容的方法）
  String getStreamUrl(String itemId) {
  // 使用缓存的转码设置决定默认质量
  final effectiveQuality = _transcodeEnabledCache
    ? _defaultQualityCache
    : JellyfinVideoQuality.original;
  return getStreamUrlWithOptions(itemId, quality: effectiveQuality);
  }
  
  /// 获取流媒体URL，支持转码选项
  /// [itemId] 媒体项目ID
  /// [quality] 指定的视频质量，为null时使用用户默认设置
  /// [forceDirectPlay] 是否强制直播（不转码）
  String getStreamUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    bool forceDirectPlay = false,
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
  }) {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
  // 如果强制直播，返回直播URL
    if (forceDirectPlay) {
      return _buildDirectPlayUrl(itemId);
    }

  // 若未显式传入quality，则使用缓存设置
  final effective = quality ?? (_transcodeEnabledCache
    ? _defaultQualityCache
    : JellyfinVideoQuality.original);

  // 构建转码/直连URL
  return _buildTranscodeUrl(itemId, effective, subtitleStreamIndex: subtitleStreamIndex, burnInSubtitle: burnInSubtitle);
  }
  
  /// 构建直播URL（不转码）
  String _buildDirectPlayUrl(String itemId) {
    return '$_serverUrl/Videos/$itemId/stream?static=true&MediaSourceId=$itemId&api_key=$_accessToken';
  }
  
  /// 构建转码URL（HLS 使用 master.m3u8）
  String _buildTranscodeUrl(String itemId, JellyfinVideoQuality? quality, {int? subtitleStreamIndex, bool? burnInSubtitle}) {
    // 如果质量为 original 或未指定，使用直连
    if (quality == null || quality == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      // HLS master.m3u8 需要 MediaSourceId（大多数情况下与 itemId 相同）
      'MediaSourceId': itemId,
      // 指定分片容器，Jellyfin 默认 HLS TS 更通用
      'segmentContainer': 'ts',
    };

    // 添加转码参数（码率/分辨率/编解码器等）
    _addTranscodeParameters(params, quality, subtitleStreamIndex: subtitleStreamIndex, burnInSubtitle: burnInSubtitle);

    // 使用 HLS master.m3u8 入口
    final uri = Uri.parse('$_serverUrl/Videos/$itemId/master.m3u8').replace(queryParameters: params);
    debugPrint('Jellyfin HLS 转码URL: $uri');
    return uri.toString();
  }

  /// 构建 HLS URL（带可选的服务器端字幕选择与烧录开关）
  /// 注意：不影响外挂字幕下载/加载逻辑，仅在服务端转码时让服务器选定字幕轨道或进行烧录。
  Future<String> buildHlsUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    int? subtitleStreamIndex,
    bool alwaysBurnInSubtitleWhenTranscoding = false,
  }) async {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    // original => 直连
    if ((quality ?? _defaultQualityCache) == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      'mediaSourceId': itemId,  // 修正参数名
      'segmentContainer': 'ts',
    };

    // 画质/编解码参数
    _addTranscodeParameters(params, quality ?? _defaultQualityCache);

    // 字幕参数：如果用户明确选择了服务器字幕，则强制添加字幕参数
    if (subtitleStreamIndex != null) {
      params['subtitleStreamIndex'] = subtitleStreamIndex.toString();
      // 根据用户选择决定字幕处理方式
      if (alwaysBurnInSubtitleWhenTranscoding) {
        params['subtitleMethod'] = 'Encode'; // 烧录字幕到视频中
        params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
        // 强制转码以确保字幕烧录
        params['allowVideoStreamCopy'] = 'false'; // 禁止视频流直传
      } else {
        params['subtitleMethod'] = 'Embed'; // 嵌入字幕作为独立轨道
      }
      // 不设置subtitleCodec，让服务器自动处理
      // PGSSUB等图形字幕需要服务器自动选择合适的输出格式
    } else {
      // 用户未选择特定字幕，使用默认设置
      final delivery = _settingsCache.subtitle.deliveryMethod;
      if (_settingsCache.subtitle.enableTranscoding &&
          delivery != JellyfinSubtitleDeliveryMethod.external &&
          delivery != JellyfinSubtitleDeliveryMethod.drop) {
        params['subtitleMethod'] = delivery.apiValue;
        if (alwaysBurnInSubtitleWhenTranscoding) {
          params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
        }
      }
    }

    final uri = Uri.parse('$_serverUrl/Videos/$itemId/master.m3u8')
        .replace(queryParameters: params);
    
    debugPrint('[Jellyfin HLS] 构建URL: ${uri.toString()}');
    debugPrint('[Jellyfin HLS] 字幕参数 - streamIndex: $subtitleStreamIndex, burnIn: $alwaysBurnInSubtitleWhenTranscoding');
    
    return uri.toString();
  }
  
  /// 添加转码参数到URL参数中
  void _addTranscodeParameters(Map<String, String> params, JellyfinVideoQuality quality, {int? subtitleStreamIndex, bool? burnInSubtitle}) {
    // 基础转码参数
    final bitrate = quality.bitrate;
    final resolution = quality.maxResolution;
    
    if (bitrate != null) {
      params['maxStreamingBitrate'] = (bitrate * 1000).toString(); // 修正参数名
      params['videoBitRate'] = (bitrate * 1000).toString(); // 修正参数名
    }
    
    if (resolution != null) {
      params['maxWidth'] = resolution.width.toString(); // 修正参数名
      params['maxHeight'] = resolution.height.toString(); // 修正参数名
    }
    
    // 默认/偏好转码设置
    final videoCodecs = _settingsCache.video.preferredCodecs.isNotEmpty
        ? _settingsCache.video.preferredCodecs.join(',')
        : 'h264,hevc,av1';
    final audioCodecs = _settingsCache.audio.preferredCodecs.isNotEmpty
        ? _settingsCache.audio.preferredCodecs.join(',')
        : 'aac,mp3,opus';
    params['videoCodec'] = videoCodecs; // 修正参数名
    params['audioCodec'] = audioCodecs; // 修正参数名

    // 音频相关限制（可选）
    if (_settingsCache.audio.maxAudioChannels > 0) {
      params['maxAudioChannels'] = _settingsCache.audio.maxAudioChannels.toString();
    }
    if (_settingsCache.audio.audioBitRate != null && _settingsCache.audio.audioBitRate! > 0) {
      params['audioBitRate'] = (_settingsCache.audio.audioBitRate! * 1000).toString();
    }
    if (_settingsCache.audio.audioSampleRate != null && _settingsCache.audio.audioSampleRate! > 0) {
      params['audioSampleRate'] = _settingsCache.audio.audioSampleRate!.toString();
    }

    // 字幕交付方式（仅当需要由服务器处理时）
    if (_settingsCache.subtitle.enableTranscoding &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.external &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.drop) {
      params['subtitleMethod'] = _settingsCache.subtitle.deliveryMethod.apiValue;
      // 指定字幕流索引（如果提供）
      if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
        params['subtitleStreamIndex'] = subtitleStreamIndex.toString();
      }
      // 烧录字幕标志（如果选择烧录或显式传入）
      final shouldBurn = burnInSubtitle ?? (_settingsCache.subtitle.deliveryMethod == JellyfinSubtitleDeliveryMethod.encode);
      if (shouldBurn) {
        params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
      }
    }
    // HLS 使用 master.m3u8，不需要设置 Container/TranscodingContainer/TranscodingProtocol
    
    // 边界情况：确保参数有效
    try {
      // 验证参数有效性
      if (params['MaxStreamingBitrate']?.isEmpty == true) {
        params.remove('MaxStreamingBitrate');
      }
      if (params['MaxWidth'] == '0' || params['MaxHeight'] == '0') {
        params.remove('MaxWidth');
        params.remove('MaxHeight');
      }
    } catch (e) {
      debugPrint('添加转码参数时出错: $e');
      // 发生错误时移除可能有问题的参数
      params.removeWhere((key, value) => 
        key.startsWith('Max') || key.contains('BitRate'));
    }
  }

  /// 构建支持自动选择字幕的 HLS URL（异步）。
  /// 当未提供 [subtitleStreamIndex] 且字幕交付方式为 Encode/Embed/Hls 时：
  /// - 优先选择简体/繁体中文或标记为默认的字幕轨道
  Future<String> buildHlsUrlWithAutoSubtitle(
    String itemId, {
    JellyfinVideoQuality? quality,
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
    String? preferredLanguage, // e.g. 'chi','zho','zh'
  }) async {
    final effective = quality ?? (_transcodeEnabledCache ? _defaultQualityCache : JellyfinVideoQuality.original);

    // 若 direct play，直接返回直链
    if (effective == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    int? resolvedIndex = subtitleStreamIndex;
    final needsServerSubtitle = _settingsCache.subtitle.enableTranscoding &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.external &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.drop;

    if (resolvedIndex == null && needsServerSubtitle) {
      try {
        final tracks = await getSubtitleTracks(itemId);
        if (tracks.isNotEmpty) {
          // 先中文（简/繁/语言码）
          final zh = tracks.firstWhere(
            (t) {
              final title = (t['title'] ?? '').toString().toLowerCase();
              final language = (t['language'] ?? '').toString().toLowerCase();
              return language.contains('chi') || language.contains('zho') || language == 'zh' ||
                     title.contains('简体') || title.contains('繁体') || title.contains('中文') ||
                     title.contains('chs') || title.contains('cht') || title.startsWith('scjp') || title.startsWith('tcjp');
            },
            orElse: () => tracks.firstWhere(
              (t) => (t['isDefault'] ?? false) == true,
              orElse: () => tracks.first,
            ),
          );
          resolvedIndex = (zh['index'] as int?);
        }
      } catch (e) {
        debugPrint('JellyfinService: 自动选择字幕轨道失败，忽略: $e');
      }
    }

    return _buildTranscodeUrl(itemId, effective, subtitleStreamIndex: resolvedIndex, burnInSubtitle: burnInSubtitle);
  }

  /// 获取Jellyfin视频的字幕轨道信息
  /// 包括内嵌字幕和外挂字幕
  Future<List<Map<String, dynamic>>> getSubtitleTracks(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 获取播放信息，包含媒体源和字幕轨道
      final response = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId'
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mediaSources = data['MediaSources'] as List?;
        
        if (mediaSources == null || mediaSources.isEmpty) {
          debugPrint('JellyfinService: 未找到媒体源信息');
          return [];
        }

        final mediaSource = mediaSources[0];
        final mediaStreams = mediaSource['MediaStreams'] as List?;
        
        if (mediaStreams == null) {
          debugPrint('JellyfinService: 未找到媒体流信息');
          return [];
        }

        List<Map<String, dynamic>> subtitleTracks = [];
        
        for (int i = 0; i < mediaStreams.length; i++) {
          final stream = mediaStreams[i];
          final streamType = stream['Type'];
          
          if (streamType == 'Subtitle') {
            final isExternal = stream['IsExternal'] ?? false;
            final deliveryMethod = stream['DeliveryMethod'];
            final language = stream['Language'] ?? '';
            final title = stream['Title'] ?? '';
            final codec = stream['Codec'] ?? '';
            final isDefault = stream['IsDefault'] ?? false;
            final isForced = stream['IsForced'] ?? false;
            final isHearingImpaired = stream['IsHearingImpaired'] ?? false;
            // 使用流的真实索引，而不是循环索引
            final realIndex = stream['Index'] ?? i;
            
            debugPrint('JellyfinService: 找到字幕轨道 $realIndex: $language ($codec, ${isExternal ? 'external' : 'embedded'})');
            
            // 构建字幕轨道信息
            Map<String, dynamic> trackInfo = {
              'index': realIndex,  // 使用真实索引
              'type': isExternal ? 'external' : 'embedded',
              'language': language,
              'title': title.isNotEmpty ? title : (language.isNotEmpty ? language : 'Unknown'),
              'codec': codec,
              'isDefault': isDefault,
              'isForced': isForced,
              'isHearingImpaired': isHearingImpaired,
              'deliveryMethod': deliveryMethod,
      // 供 UI 快速显示
      'display': _buildSubtitleDisplay(language, title, codec, isExternal, isForced, isDefault),
            };

            // 如果是外挂字幕，添加下载URL
            if (isExternal) {
              final mediaSourceId = mediaSource['Id'];
              final subtitleUrl = '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$realIndex/Stream.$codec?api_key=$_accessToken';
              trackInfo['downloadUrl'] = subtitleUrl;
            }

            subtitleTracks.add(trackInfo);
            // 注意：这里使用realIndex而不是循环的i
          }
        }

        debugPrint('JellyfinService: 总共找到 ${subtitleTracks.length} 个字幕轨道');
        return subtitleTracks;
      } else {
        debugPrint('JellyfinService: 获取播放信息失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('JellyfinService: 获取字幕轨道信息失败: $e');
      return [];
    }
  }

  /// 下载外挂字幕文件
  Future<String?> downloadSubtitleFile(String itemId, int subtitleIndex, String format) async {
    if (kIsWeb) return null;
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 获取媒体源ID
      final playbackInfoResponse = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId'
      );

      if (playbackInfoResponse.statusCode != 200) {
        debugPrint('JellyfinService: 获取播放信息失败，无法下载字幕');
        return null;
      }

      final playbackData = json.decode(playbackInfoResponse.body);
      final mediaSources = playbackData['MediaSources'] as List?;
      
      if (mediaSources == null || mediaSources.isEmpty) {
        debugPrint('JellyfinService: 未找到媒体源信息');
        return null;
      }

      final mediaSourceId = mediaSources[0]['Id'];
      
      // 构建字幕下载URL
      final subtitleUrl = '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format?api_key=$_accessToken';
      
      debugPrint('JellyfinService: 下载字幕文件: $subtitleUrl');
      
      // 下载字幕文件
      final subtitleResponse = await http.get(Uri.parse(subtitleUrl));
      
      if (subtitleResponse.statusCode == 200) {
        // 保存到临时文件
        final tempDir = await getTemporaryDirectory();
        final fileName = 'jellyfin_subtitle_${itemId}_$subtitleIndex.$format';
        final filePath = '${tempDir.path}/$fileName';
        
        final file = File(filePath);
        await file.writeAsBytes(subtitleResponse.bodyBytes);
        
        debugPrint('JellyfinService: 字幕文件已保存到: $filePath');
        return filePath;
      } else {
        debugPrint('JellyfinService: 下载字幕文件失败: HTTP ${subtitleResponse.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('JellyfinService: 下载字幕文件时出错: $e');
      return null;
    }
  }

  /// 构造字幕显示名称（供设置面板展示）
  String _buildSubtitleDisplay(
    String language,
    String title,
    String codec,
    bool isExternal,
    bool isForced,
    bool isDefault,
  ) {
    final List<String> parts = [];
    if (title.isNotEmpty) {
      parts.add(title);
    } else if (language.isNotEmpty) {
      parts.add(language);
    } else {
      parts.add('字幕');
    }
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    if (isExternal) parts.add('外挂');
    if (isForced) parts.add('强制');
    if (isDefault) parts.add('默认');
    return parts.join(' · ');
  }

  /// 搜索媒体库中的内容
  /// [searchTerm] 搜索关键词
  /// [includeItemTypes] 包含的项目类型 (Series, Movie, Episode等)
  /// [limit] 结果数量限制
  /// [parentId] 父级媒体库ID (可选，用于限制在特定媒体库中搜索)
  Future<List<JellyfinMediaItem>> searchMediaItems(
    String searchTerm, {
    List<String>? includeItemTypes,
    int limit = 50,
    String? parentId,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty) {
      return [];
    }

    try {
      // 构建查询参数
      final queryParams = <String, String>{
        'searchTerm': searchTerm.trim(),
        'IncludeItemTypes': (includeItemTypes ?? ['Series', 'Movie']).join(','),
        'Recursive': 'true',
        'Limit': limit.toString(),
        'Fields': 'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear',
      };

      // 如果指定了父级媒体库，则只在该媒体库中搜索
      if (parentId != null) {
        queryParams['ParentId'] = parentId;
      } else {
        // 如果没有指定，则在所有选中的媒体库中搜索
        if (_selectedLibraryIds.isNotEmpty) {
          queryParams['ParentId'] = _selectedLibraryIds.join(',');
        }
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _makeAuthenticatedRequest('/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];
        
        final results = items
            .map((item) => JellyfinMediaItem.fromJson(item))
            .toList();

        debugPrint('[JellyfinService] 搜索 "$searchTerm" 找到 ${results.length} 个结果');
        return results;
      } else {
        debugPrint('[JellyfinService] 搜索失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[JellyfinService] 搜索出错: $e');
      return [];
    }
  }

  /// 在特定媒体库中搜索
  Future<List<JellyfinMediaItem>> searchInLibrary(
    String libraryId,
    String searchTerm, {
    int limit = 50,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty) {
      return [];
    }

    try {
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';

      return await searchMediaItems(
        searchTerm,
        includeItemTypes: [includeItemTypes],
        limit: limit,
        parentId: libraryId,
      );
    } catch (e) {
      debugPrint('[JellyfinService] 在媒体库 $libraryId 中搜索出错: $e');
      return [];
    }
  }
  
  // 获取图片URL
  String getImageUrl(String itemId, {String type = 'Primary', int? width, int? height, int? quality}) {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    String url = '$_serverUrl/Items/$itemId/Images/$type';
    List<String> params = [];
    
    if (width != null) params.add('width=$width');
    if (height != null) params.add('height=$height');
    if (quality != null) params.add('quality=$quality');
    
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    
    return url;
  }
  
  // 辅助方法：发送经过身份验证的HTTP请求
  Future<http.Response> _makeAuthenticatedRequest(String endpoint, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    // 如果有多地址配置，尝试使用多地址重试机制
    if (_currentProfile != null) {
      return await _makeAuthenticatedRequestWithRetry(endpoint, method: method, body: body, timeout: timeout);
    }
    
    // 单地址模式（兼容旧版本）
    if (_serverUrl == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final Uri uri = Uri.parse('$_serverUrl$endpoint');
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final Map<String, String> headers = {
      'X-Emby-Authorization': authHeader,
    };
    
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    
    // 设置默认超时时间为30秒（弱网/公网/隧道场景更稳妥）
    final requestTimeout = timeout ?? const Duration(seconds: 30);
    
    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(requestTimeout);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(requestTimeout);
          break;
        default:
          throw Exception('不支持的HTTP方法: $method');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('请求Jellyfin服务器超时: ${e.message}');
      }
      throw Exception('请求Jellyfin服务器失败: $e');
    }
    if (response.statusCode >= 400) {
      // 详细抛出服务器错误，包括403/401/500等
      throw Exception('服务器返回错误: ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    }
    return response;
  }
  
  /// 带重试的认证请求（多地址支持）
  Future<http.Response> _makeAuthenticatedRequestWithRetry(String endpoint, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_currentProfile == null || _accessToken == null) {
      throw Exception('未连接到 Jellyfin 服务器');
    }
    
    final addresses = _currentProfile!.enabledAddresses;
    if (addresses.isEmpty) {
      throw Exception('没有可用的服务器地址');
    }
    
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final Map<String, String> headers = {
      'X-Emby-Authorization': authHeader,
    };
    
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    
  final requestTimeout = timeout ?? const Duration(seconds: 30);
    
    Exception? lastError;
    
    // 尝试每个地址
    for (final address in addresses) {
      if (!address.shouldRetry()) continue;
      
      final Uri uri = Uri.parse('${address.normalizedUrl}$endpoint');
      
      try {
        http.Response response;
        switch (method.toUpperCase()) {
          case 'GET':
            response = await http.get(uri, headers: headers).timeout(requestTimeout);
            break;
          case 'POST':
            response = await http.post(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
            break;
          case 'PUT':
            response = await http.put(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
            break;
          case 'DELETE':
            response = await http.delete(uri, headers: headers).timeout(requestTimeout);
            break;
          default:
            throw Exception('不支持的 HTTP 方法: $method');
        }
        
        if (response.statusCode < 400) {
          // 成功，更新当前使用的地址
          if (_currentAddressId != address.id) {
            _serverUrl = address.normalizedUrl;
            _currentAddressId = address.id;
            _currentProfile = _currentProfile!.markAddressSuccess(address.id);
            await _multiAddressService.updateProfile(_currentProfile!);
          }
          return response;
        } else {
          // 提供更详细的错误信息
          String errorMessage;
          if (response.statusCode == 401) {
            errorMessage = '认证失败: 访问令牌无效或已过期 (HTTP 401)';
          } else if (response.statusCode == 403) {
            errorMessage = '访问被拒绝: 用户权限不足 (HTTP 403)';
          } else if (response.statusCode == 404) {
            errorMessage = '请求的资源未找到 (HTTP 404)';
          } else if (response.statusCode >= 500) {
            errorMessage = 'Jellyfin服务器内部错误 (HTTP ${response.statusCode})';
          } else {
            errorMessage = '服务器返回错误: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}';
          }
          lastError = Exception(errorMessage);
          DebugLogService().addLog('JellyfinService: 请求失败 ${address.normalizedUrl}: $errorMessage');
        }
      } on TimeoutException catch (e) {
        lastError = Exception('请求超时: ${e.message}');
        _currentProfile = _currentProfile!.markAddressFailed(address.id);
      } catch (e) {
        lastError = Exception('请求失败: $e');
        _currentProfile = _currentProfile!.markAddressFailed(address.id);
      }
    }
    
    // 更新失败信息
    await _multiAddressService.updateProfile(_currentProfile!);
    
    throw lastError ?? Exception('所有地址连接失败');
  }
  
  /// 获取当前服务器的所有地址
  List<ServerAddress> getServerAddresses() {
    if (_currentProfile != null) {
      return _currentProfile!.addresses;
    }
    return [];
  }
  
  /// 添加新地址到当前服务器
  Future<bool> addServerAddress(String url, String name) async {
    if (_currentProfile == null) return false;
    
    final normalizedUrl = _normalizeUrl(url);
    
    try {
      // 先验证这是否为同一台服务器
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: 'jellyfin',
        getServerId: _getJellyfinServerId,
      );
      
      if (!identifyResult.success) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法验证服务器身份');
      }
      
      if (identifyResult.isConflict) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      }
      
      // 验证serverId是否匹配
      if (identifyResult.serverId != _currentProfile!.serverId) {
        throw Exception('该地址属于不同的Jellyfin服务器（服务器ID: ${identifyResult.serverId}），无法添加到当前配置');
      }
      
      final updatedProfile = await _multiAddressService.addAddressToProfile(
        profileId: _currentProfile!.id,
        url: normalizedUrl,
        name: UrlNameGenerator.generateAddressName(normalizedUrl, customName: name),
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        DebugLogService().addLog('成功添加新地址: $normalizedUrl');
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('添加服务器地址失败: $e');
      rethrow; // 重新抛出异常以便UI处理
    }
    return false;
  }
  
  /// 删除服务器地址
  Future<bool> removeServerAddress(String addressId) async {
    if (_currentProfile == null) return false;
    
    try {
      final updatedProfile = await _multiAddressService.deleteAddressFromProfile(
        profileId: _currentProfile!.id,
        addressId: addressId,
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('删除服务器地址失败: $e');
    }
    return false;
  }
  
  /// 切换服务器地址
  Future<bool> switchToAddress(String addressId) async {
    if (_currentProfile == null) return false;
    
    final address = _currentProfile!.addresses.firstWhere(
      (addr) => addr.id == addressId,
      orElse: () => throw Exception('地址不存在'),
    );
    
    // 测试连接
    final success = await _testJellyfinConnection(
      address.normalizedUrl,
      _username ?? '',
      _password ?? '',
    );
    
    if (success) {
      // 验证当前用户token在新地址上的有效性
      try {
        final originalUrl = _serverUrl;
        _serverUrl = address.normalizedUrl;
        
        // 进行轻量级认证验证
        final authResponse = await _makeAuthenticatedRequest('/System/Info')
            .timeout(const Duration(seconds: 5));
        
        if (authResponse.statusCode == 200) {
          _currentAddressId = address.id;
          _currentProfile = _currentProfile!.markAddressSuccess(address.id);
          await _multiAddressService.updateProfile(_currentProfile!);
          DebugLogService().addLog('JellyfinService: 成功切换到地址: ${address.normalizedUrl}');
          return true;
        } else {
          // 认证失败，恢复原地址
          _serverUrl = originalUrl;
          DebugLogService().addLog('JellyfinService: 地址切换失败，token在新地址上无效: HTTP ${authResponse.statusCode}');
          return false;
        }
      } catch (e) {
        // 认证失败，恢复原地址
        _serverUrl = _currentProfile!.currentAddress?.normalizedUrl;
        DebugLogService().addLog('JellyfinService: 地址切换失败，认证验证异常: $e');
        return false;
      }
    }
    
    return false;
  }

  /// 更新服务器地址优先级
  Future<bool> updateServerPriority(String addressId, int priority) async {
    if (_currentProfile == null) return false;
    
    try {
      final updatedProfile = await _multiAddressService.updateAddressPriority(
        profileId: _currentProfile!.id,
        addressId: addressId,
        priority: priority,
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('JellyfinService: 更新地址优先级失败: $e');
    }
    
    return false;
  }

  /// 由 Provider 调用：在运行时更新本地转码缓存（避免在 getStreamUrl 中做异步 IO）
  void setTranscodePreferences({bool? enabled, JellyfinVideoQuality? defaultQuality}) {
    if (enabled != null) _transcodeEnabledCache = enabled;
    if (defaultQuality != null) _defaultQualityCache = defaultQuality;
    DebugLogService().addLog('Jellyfin: 更新转码偏好 缓存 enabled=${enabled ?? _transcodeEnabledCache}, quality=${defaultQuality ?? _defaultQualityCache}');
  }

  /// 由 Provider 调用：更新完整转码设置缓存（用于音频/字幕等参数）
  void setFullTranscodeSettings(JellyfinTranscodeSettings settings) {
    _settingsCache = settings;
    DebugLogService().addLog('Jellyfin: 更新完整转码设置缓存 (video/audio/subtitle/adaptive)');
  }
}
