import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_media_library_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/widgets/nipaplay_theme/blur_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

import 'package:nipaplay/widgets/nipaplay_theme/media_server_selection_sheet.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback
  final bool jellyfinMode; // 是否为Jellyfin媒体库模式

  const MediaLibraryPage({
    super.key, 
    this.onPlayEpisode,
    this.jellyfinMode = false,
  }); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  // 🔥 临时禁用页面保活，测试是否解决CPU泄漏问题
  // with AutomaticKeepAliveClientMixin {
  List<WatchHistoryItem> _uniqueLibraryItems = []; 
  Map<int, String> _persistedImageUrls = {}; 
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {}; 
  bool _isLoadingInitial = true; 
  String? _error;
  
  // 🔥 CPU优化：防止重复处理相同的历史数据
  int _lastProcessedHistoryHashCode = 0;
  bool _isBackgroundFetching = false;
  bool _hasWebDataLoaded = false; // 添加Web数据加载标记
  
  // 🔥 CPU优化：缓存已构建的卡片Widget
  final Map<String, Widget> _cardWidgetCache = {};
  
  final ScrollController _gridScrollController = ScrollController();

  static const String _prefsKeyPrefix = 'media_library_image_url_';
  
  bool _isJellyfinConnected = false;

  // 🔥 临时禁用页面保活
  // @override
  // bool get wantKeepAlive => true;

  @override
  void initState() {
    //debugPrint('[媒体库CPU] MediaLibraryPage initState 开始');
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        //debugPrint('[媒体库CPU] 开始加载初始数据');
        _loadInitialMediaLibraryData();
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        _isJellyfinConnected = jellyfinProvider.isConnected; // Initialize
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    //debugPrint('[CPU-泄漏排查] MediaLibraryPage dispose 被调用！！！');
    try {
      if (mounted) { 
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("移除Provider监听器时出错: $e");
    }

    _gridScrollController.dispose();
    super.dispose();
  }

  void _onJellyfinProviderChanged() {
    if (mounted) {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (_isJellyfinConnected != jellyfinProvider.isConnected) {
        setState(() {
          _isJellyfinConnected = jellyfinProvider.isConnected;
        });
      }
    }
  }

  Future<void> _processAndSortHistory(List<WatchHistoryItem> watchHistory) async {
    if (!mounted) return;
    
    // 🔥 CPU优化：检查数据是否已经处理过，避免重复处理
    final currentHashCode = watchHistory.hashCode;
    if (currentHashCode == _lastProcessedHistoryHashCode) {
      //debugPrint('[媒体库CPU] 跳过重复处理历史数据 - 哈希码: $currentHashCode');
      return;
    }
    //debugPrint('[媒体库CPU] 开始处理历史数据 - 哈希码: $currentHashCode (上次: $_lastProcessedHistoryHashCode)');
    _lastProcessedHistoryHashCode = currentHashCode;

    if (watchHistory.isEmpty) {
      setState(() {
        _uniqueLibraryItems = [];
        _isLoadingInitial = false; 
      });
      return;
    }

    final filteredHistory = watchHistory.where((item) =>
        !item.filePath.startsWith('jellyfin://') &&
        !item.filePath.startsWith('emby://') &&
        !item.filePath.contains('/api/media/local/share/')).toList();

    final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
    for (var item in filteredHistory) {
      if (item.animeId != null) {
        if (latestHistoryItemMap.containsKey(item.animeId!)) {
          if (item.lastWatchTime.isAfter(latestHistoryItemMap[item.animeId!]!.lastWatchTime)) {
            latestHistoryItemMap[item.animeId!] = item;
          }
        } else {
          latestHistoryItemMap[item.animeId!] = item;
        }
      }
    }
    final uniqueAnimeItemsFromHistory = latestHistoryItemMap.values.toList();
    uniqueAnimeItemsFromHistory.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

    Map<int, String> loadedPersistedUrls = {};
    final prefs = await SharedPreferences.getInstance();
    for (var item in uniqueAnimeItemsFromHistory) {
      if (item.animeId != null) {
        String? persistedUrl = prefs.getString('$_prefsKeyPrefix${item.animeId}');
        if (persistedUrl != null && persistedUrl.isNotEmpty) {
          loadedPersistedUrls[item.animeId!] = persistedUrl;
        }
      }
    }

    setState(() {
      _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
      _persistedImageUrls = loadedPersistedUrls;
      _isLoadingInitial = false; 
      // 🔥 CPU优化：清空卡片缓存，因为数据已更新
      _cardWidgetCache.clear();
    });
    _fetchAndPersistFullDetailsInBackground(); 
  }

  Future<void> _loadInitialMediaLibraryData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        // Web environment: 完全模仿新番更新页面的逻辑
        List<BangumiAnime> animes;
        
        try {
          final response = await http.get(Uri.parse('/api/media/local/items'));
          if (response.statusCode == 200) {
            final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
            animes = data.map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>)).toList();
          } else {
            throw Exception('Failed to load from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local API: $e');
        }
        
        // 转换为WatchHistoryItem（保持兼容性）
        final webHistoryItems = animes.map((anime) {
          final animeJson = anime.toJson();
          return WatchHistoryItem(
            animeId: anime.id,
            animeName: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
            episodeTitle: '',
            filePath: 'web_${anime.id}',
            lastWatchTime: animeJson['_localLastWatchTime'] != null 
                ? DateTime.parse(animeJson['_localLastWatchTime']) 
                : DateTime.now(),
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            thumbnailPath: anime.imageUrl,
          );
        }).toList();
        
        // 缓存BangumiAnime数据
        for (var anime in animes) {
          _fetchedFullAnimeData[anime.id] = anime;
        }
        
        if (mounted) {
          setState(() {
            _uniqueLibraryItems = webHistoryItems;
            _isLoadingInitial = false;
            _hasWebDataLoaded = true;
            _cardWidgetCache.clear();
          });
        }
      } else {
        // Mobile/Desktop environment: use local providers
        final historyProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
        if (!historyProvider.isLoaded && !historyProvider.isLoading) {
          await historyProvider.loadHistory(); 
        }
        
        if (historyProvider.isLoaded) {
            await _processAndSortHistory(historyProvider.history);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingInitial = false;
        });
      }
    }
  }

  Future<void> _fetchAndPersistFullDetailsInBackgroundForWeb() async {
    if (_isBackgroundFetching) return;
    _isBackgroundFetching = true;
    
    final prefs = await SharedPreferences.getInstance();
    const int maxConcurrentRequests = 8; // 增加并发数
    int processed = 0;
    final total = _uniqueLibraryItems.where((item) => item.animeId != null).length;
    
    // 批量处理请求
    final futures = <Future<void>>[];
    
    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null && !_fetchedFullAnimeData.containsKey(historyItem.animeId!)) {
        final future = _fetchSingleAnimeDetail(historyItem.animeId!, prefs).then((_) {
          processed++;
          // 每处理5个项目批量更新一次UI，避免频繁更新
          if (processed % 5 == 0 && mounted) {
            setState(() {});
          }
        });
        futures.add(future);
        
        // 控制并发数量
        if (futures.length >= maxConcurrentRequests) {
          await Future.any(futures);
          // 移除已完成的Future (简化处理)
          futures.clear();
        }
      }
    }
    
    // 等待所有剩余请求完成
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    // 最后一次UI更新
    if (mounted) {
      setState(() {});
    }
    
    _isBackgroundFetching = false;
  }
  
  Future<void> _fetchSingleAnimeDetail(int animeId, SharedPreferences prefs) async {
    try {
      final response = await http.get(Uri.parse('/api/bangumi/detail/$animeId'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> animeDetailData = json.decode(utf8.decode(response.bodyBytes));
        final animeDetail = BangumiAnime.fromJson(animeDetailData);
        
        if (mounted) {
          _fetchedFullAnimeData[animeId] = animeDetail;
          if (animeDetail.imageUrl.isNotEmpty) {
            await prefs.setString('$_prefsKeyPrefix$animeId', animeDetail.imageUrl);
            if (mounted) {
              _persistedImageUrls[animeId] = animeDetail.imageUrl;
            }
          } else {
            await prefs.remove('$_prefsKeyPrefix$animeId');
            if (mounted && _persistedImageUrls.containsKey(animeId)) {
              _persistedImageUrls.remove(animeId);
            }
          }
        }
      }
    } catch (e) {
      // Silent fail for background requests
      debugPrint('获取动画详情失败: $animeId - $e');
    }
  }
  
  Future<void> _showJellyfinServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.jellyfin);
  }

  Future<void> _showServerSelectionDialog() async {
    final result = await MediaServerSelectionSheet.show(context);

    if (result != null && mounted) {
      if (result == 'jellyfin') {
        await _showJellyfinServerDialog();
      } else if (result == 'emby') {
        await _showEmbyServerDialog();
      } else if (result == 'nipaplay') {
        await _showNipaplayServerDialog();
      }
    }
  }

  Future<void> _showNipaplayServerDialog() async {
    final sharedRemoteProvider = Provider.of<SharedRemoteLibraryProvider>(context, listen: false);

    // 如果已有主机，显示选择界面；否则显示添加主机的登录对话框
    if (sharedRemoteProvider.hosts.isNotEmpty) {
      await SharedRemoteHostSelectionSheet.show(context);
    } else {
      // 显示添加主机的登录对话框
      await BlurLoginDialog.show(
        context,
        title: '添加NipaPlay共享客户端',
        fields: [
          LoginField(
            key: 'displayName',
            label: '备注名称',
            hint: '例如：家里的电脑',
            required: false,
          ),
          LoginField(
            key: 'baseUrl',
            label: '访问地址',
            hint: '例如：http://192.168.1.100:8080',
          ),
        ],
        loginButtonText: '添加',
        onLogin: (values) async {
          try {
            final displayName = values['displayName']?.trim().isEmpty ?? true
                ? values['baseUrl']!.trim()
                : values['displayName']!.trim();

            await sharedRemoteProvider.addHost(
              displayName: displayName,
              baseUrl: values['baseUrl']!.trim(),
            );

            return LoginResult(
              success: true,
              message: '已添加共享客户端',
            );
          } catch (e) {
            return LoginResult(
              success: false,
              message: '添加失败：$e',
            );
          }
        },
      );
    }
  }

  Future<void> _showEmbyServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.emby);
  }

  Future<void> _fetchAndPersistFullDetailsInBackground() async {
    // 🔥 CPU优化：防止重复启动后台任务
    if (_isBackgroundFetching) {
      //debugPrint('[媒体库CPU] 后台获取任务已在进行中，跳过');
      return;
    }
    _isBackgroundFetching = true;
    
    //debugPrint('[媒体库CPU] 开始后台获取详细信息 - 项目数量: ${_uniqueLibraryItems.length}');
    final stopwatch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    List<Future> pendingRequests = [];
    const int maxConcurrentRequests = 2; // 🔥 CPU优化：减少并发请求数量
    
    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null) { 
        // 🔥 修改条件：只要动画ID不为空，就尝试获取详情
        // 不再跳过已有图片或已缓存的项目
        
        Future<void> fetchDetailForItem() async {
          try {
            // 如果已经有详细数据，则跳过获取
            if (_fetchedFullAnimeData.containsKey(historyItem.animeId!)) {
              return;
            }
            
            final animeDetail = await BangumiService.instance.getAnimeDetails(historyItem.animeId!);
            //debugPrint('[媒体库CPU] 获取到动画详情: ${historyItem.animeId} - ${animeDetail.name}');
            if (mounted) {
              // 🔥 CPU优化：批量更新而不是单个setState
              _fetchedFullAnimeData[historyItem.animeId!] = animeDetail;
              if (animeDetail.imageUrl.isNotEmpty) {
                await prefs.setString('$_prefsKeyPrefix${historyItem.animeId!}', animeDetail.imageUrl);
                if (mounted) {
                  // 🔥 CPU优化：只更新数据，不立即setState
                  _persistedImageUrls[historyItem.animeId!] = animeDetail.imageUrl;
                }
              } else {
                await prefs.remove('$_prefsKeyPrefix${historyItem.animeId!}');
                if(mounted && _persistedImageUrls.containsKey(historyItem.animeId!)){
                  // 🔥 CPU优化：只更新数据，不立即setState
                  _persistedImageUrls.remove(historyItem.animeId!);
                }
              }
            }
          } catch (e) {
            //debugPrint('[媒体库CPU] 获取动画详情失败: ${historyItem.animeId} - $e');
          }
        }
        
        if (pendingRequests.length >= maxConcurrentRequests) {
          await Future.any(pendingRequests);
          pendingRequests.removeWhere((f) => f.toString().contains('Completed'));
        }
        
        pendingRequests.add(fetchDetailForItem());
      }
    }
    
    await Future.wait(pendingRequests);
    
    // 🔥 CPU优化：最后一次性刷新UI，而不是每个项目都setState
    if (mounted) {
      setState(() {
        // 触发UI重建，显示所有更新的数据
      });
    }
    
    //debugPrint('[媒体库CPU] 后台获取完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms');
    _isBackgroundFetching = false;
  }

  Future<void> _preloadAnimeDetail(int animeId) async {
    if (_fetchedFullAnimeData.containsKey(animeId)) {
      return;
    }
    
    try {
      final animeDetail = await BangumiService.instance.getAnimeDetails(animeId);
      if (mounted) {
        setState(() {
          _fetchedFullAnimeData[animeId] = animeDetail;
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  void _navigateToAnimeDetail(int animeId) {
    ThemedAnimeDetail.show(context, animeId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        widget.onPlayEpisode?.call(result);
      }
    });
    
    if (!_fetchedFullAnimeData.containsKey(animeId)) {
      _preloadAnimeDetail(animeId);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 🔥 移除super.build(context)调用，因为已禁用AutomaticKeepAliveClientMixin
    // super.build(context);
    //debugPrint('[媒体库CPU] MediaLibraryPage build 被调用 - mounted: $mounted');
    final uiThemeProvider = Provider.of<UIThemeProvider>(context);

    // This Consumer ensures that we rebuild when the watch history changes.
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        // Trigger processing of history data whenever the provider updates.
        if (historyProvider.isLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _processAndSortHistory(historyProvider.history);
            }
          });
        }

        // Decide which UI to render based on the theme.
        if (uiThemeProvider.isFluentUITheme) {
          return FluentMediaLibraryView(
            isLoading: _isLoadingInitial,
            error: _error,
            items: _uniqueLibraryItems,
            fullAnimeData: _fetchedFullAnimeData,
            persistedImageUrls: _persistedImageUrls,
            isJellyfinConnected: _isJellyfinConnected,
            scrollController: _gridScrollController,
            onRefresh: _loadInitialMediaLibraryData,
            onConnectServer: _showServerSelectionDialog,
            onAnimeTap: _navigateToAnimeDetail,
          );
        } else {
          return _buildLocalMediaLibrary();
        }
      },
    );
  }
  
  Widget _buildLocalMediaLibrary() {
    if (_isLoadingInitial) {
      return const SizedBox(
        height: 200, 
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '加载媒体库失败: $_error',
                style: TextStyle(color: context.nipaplayColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInitialMediaLibraryData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_uniqueLibraryItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '媒体库为空。\n观看过的动画将显示在这里。',
                textAlign: TextAlign.center,
                locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (!_isJellyfinConnected)
                BlurButton(
                  icon: Icons.cloud,
                  text: '添加媒体服务器',
                  onTap: _showServerSelectionDialog,
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RepaintBoundary(
          child: Scrollbar(
            controller: _gridScrollController,
            thickness: kIsWeb ? 4 : (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ? 0 : 4,
            radius: const Radius.circular(2),
            child: GridView.builder(
              controller: _gridScrollController,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 7/12,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              cacheExtent: 800,
              clipBehavior: Clip.hardEdge,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: _uniqueLibraryItems.length,
              itemBuilder: (context, index) {
                // 🔥 CPU优化：添加itemBuilder监控
                if (index % 20 == 0) {
                  //debugPrint('[媒体库CPU] GridView itemBuilder - 索引: $index/${_uniqueLibraryItems.length}');
                }
                final historyItem = _uniqueLibraryItems[index];
                final animeId = historyItem.animeId;
                
                // 🔥 CPU优化：使用文件路径作为缓存键，检查是否已缓存
                final cacheKey = historyItem.filePath;
                if (_cardWidgetCache.containsKey(cacheKey)) {
                  return _cardWidgetCache[cacheKey]!;
                }

                String imageUrlToDisplay = historyItem.thumbnailPath ?? '';
                String nameToDisplay = historyItem.animeName.isNotEmpty 
                    ? historyItem.animeName 
                    : (historyItem.episodeTitle ?? '未知动画');

                if (animeId != null) {
                    if (_fetchedFullAnimeData.containsKey(animeId)) {
                        final fetchedData = _fetchedFullAnimeData[animeId]!;
                        if (fetchedData.imageUrl.isNotEmpty) {
                            imageUrlToDisplay = fetchedData.imageUrl;
                        }
                        if (fetchedData.nameCn.isNotEmpty) {
                            nameToDisplay = fetchedData.nameCn;
                        } else if (fetchedData.name.isNotEmpty) {
                            nameToDisplay = fetchedData.name;
                        }
                    } else if (_persistedImageUrls.containsKey(animeId)) {
                        imageUrlToDisplay = _persistedImageUrls[animeId]!;
                    }
                }

                // 🔥 CPU优化：构建卡片并缓存
                final card = _buildAnimeCard(
                  key: ValueKey(animeId ?? historyItem.filePath), 
                  name: nameToDisplay, 
                  imageUrl: imageUrlToDisplay,
                  source: AnimeCard.getSourceFromFilePath(historyItem.filePath),
                  rating: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                      ? _fetchedFullAnimeData[animeId]!.rating 
                      : null,
                  ratingDetails: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                      ? _fetchedFullAnimeData[animeId]!.ratingDetails 
                      : null,
                  onTap: () {
                    if (animeId != null) {
                      _navigateToAnimeDetail(animeId);
                    } else {
                      BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                    }
                  },
                );
                
                // 调试：打印详细的评分信息
                if (animeId != null) {
                  //debugPrint('动画 $animeId 详细信息：');
                  //debugPrint('  名称: $nameToDisplay');
                  //debugPrint('  是否存在于_fetchedFullAnimeData: ${_fetchedFullAnimeData.containsKey(animeId)}');
                  
                  if (_fetchedFullAnimeData.containsKey(animeId)) {
                    final animeData = _fetchedFullAnimeData[animeId]!;
                    //debugPrint('  通用评分: ${animeData.rating}');
                    //debugPrint('  评分详情: ${animeData.ratingDetails}');
                  }
                }
                
                // 🔥 CPU优化：缓存卡片Widget，限制缓存大小避免内存泄漏
                if (_cardWidgetCache.length < 100) { // 限制最多缓存100个卡片
                  _cardWidgetCache[cacheKey] = card;
                }
                
                return card;
              },
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionGlassButton(
            iconData: Ionicons.cloud_outline,
            onPressed: _showServerSelectionDialog,
            description: '添加媒体服务器\n连接到Jellyfin或Emby服务器\n享受云端媒体库内容',
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard({
    required Key key,
    required String name,
    required String imageUrl,
    required String? source,
    required double? rating,
    required Map<String, dynamic>? ratingDetails,
    required VoidCallback onTap,
  }) {
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      return FluentAnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    } else {
      return AnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    }
  }


}
