import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'dart:ui';

/// 手动弹幕匹配器
/// 
/// 提供手动搜索和匹配弹幕的功能，参考jellyfin_dandanplay_matcher的实现方式
class ManualDanmakuMatcher {
  static final ManualDanmakuMatcher instance = ManualDanmakuMatcher._internal();
  
  ManualDanmakuMatcher._internal();

  /// 搜索动画
  /// 
  /// 根据关键词搜索动画列表
  Future<List<Map<String, dynamic>>> searchAnime(String keyword) async {
    if (keyword.trim().isEmpty) {
      return [];
    }

    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(keyword)}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId, 
            timestamp, 
            apiPath, 
            appSecret
          ),
          'X-Timestamp': '$timestamp',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['animes'] != null && data['animes'] is List) {
          final List<dynamic> animesList = data['animes'];
          final List<Map<String, dynamic>> results = [];
          
          for (var anime in animesList) {
            if (anime is Map<String, dynamic>) {
              results.add(anime);
            }
          }
          
          return results;
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// 获取动画的剧集列表
  Future<List<Map<String, dynamic>>> getAnimeEpisodes(int animeId, String animeTitle) async {
    try {
      if (animeTitle.isEmpty) {
        throw Exception('动画标题为空');
      }

      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      
      final url = 'https://api.dandanplay.net/api/v2/bangumi/$animeId';
      
      final signature = DandanplayService.generateSignature(DandanplayService.appId, timestamp, apiPath, appSecret);
      
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'X-AppId': DandanplayService.appId,
        'X-Signature': signature,
        'X-Timestamp': '$timestamp',
        'Accept': 'application/json',
      };
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      
      if (response.statusCode != 200) {
        throw Exception('获取剧集列表失败，状态码: ${response.statusCode}');
      }
      
      final data = json.decode(response.body);
      
      final List<Map<String, dynamic>> episodes = [];
      
      if (data.containsKey('bangumi') && data['bangumi'] is Map<String, dynamic>) {
        final bangumi = data['bangumi'] as Map<String, dynamic>;
        if (bangumi.containsKey('episodes') && bangumi['episodes'] is List) {
          final List<dynamic> episodesData = bangumi['episodes'];
          
          for (var episode in episodesData) {
            if (episode is Map<String, dynamic>) {
              episodes.add({
                'episodeId': episode['episodeId'],
                'episodeTitle': episode['episodeTitle'],
                'episodeNumber': episode['episodeNumber'],
              });
            }
          }
        }
      } else if (data.containsKey('episodes') && data['episodes'] is List) {
        final List<dynamic> episodesData = data['episodes'];
        
        for (var episode in episodesData) {
          if (episode is Map<String, dynamic>) {
            episodes.add({
              'episodeId': episode['episodeId'],
              'episodeTitle': episode['episodeTitle'],
              'episodeNumber': episode['episodeNumber'],
            });
          }
        }
      } else if (data.containsKey('animes') && data['animes'] is List) {
        final List<dynamic> animesData = data['animes'];
        
        for (var anime in animesData) {
          if (anime is Map<String, dynamic> && 
              anime.containsKey('episodes') && 
              anime['episodes'] is List) {
            final List<dynamic> episodesData = anime['episodes'];
            
            for (var episode in episodesData) {
              if (episode is Map<String, dynamic>) {
                episodes.add({
                  'episodeId': episode['episodeId'],
                  'episodeTitle': episode['episodeTitle'],
                  'episodeNumber': episode['episodeNumber'],
                });
              }
            }
          }
        }
      }
      
      if (episodes.isNotEmpty) {
        return episodes;
      } else {
        throw Exception('未找到剧集信息');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 显示手动匹配对话框
  /// 
  /// 显示手动搜索和选择动画/剧集的对话框
  Future<Map<String, dynamic>?> showManualMatchDialog(
    BuildContext context, {
    String? initialSearchText,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManualDanmakuMatchDialog(
        initialSearchText: initialSearchText ?? '',
      ),
    );
    
    return result;
  }

  /// 预加载弹幕数据（异步执行，不等待结果）
  Future<void> _preloadDanmaku(String episodeId, int animeId) async {
    try {
      debugPrint('开始预加载弹幕: episodeId=$episodeId, animeId=$animeId');
      
      // 检查是否已经缓存了弹幕数据
      final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        debugPrint('弹幕已存在于缓存中，无需预加载: episodeId=$episodeId');
        return;
      }
      
      // 异步预加载弹幕，不等待结果
      DandanplayService.getDanmaku(episodeId, animeId).then((danmakuData) {
        final count = danmakuData['count'];
        if (count != null) {
          debugPrint('弹幕预加载成功: 加载了$count条弹幕');
        } else {
          debugPrint('弹幕预加载成功，但无法确定数量');
        }
      }).catchError((e) {
        debugPrint('弹幕预加载失败: $e');
      });
    } catch (e) {
      debugPrint('预加载弹幕时出错: $e');
    }
  }
}

/// 手动弹幕匹配对话框
/// 
/// 显示搜索动画和选择剧集的界面
class ManualDanmakuMatchDialog extends StatefulWidget {
  final String initialSearchText;
  
  const ManualDanmakuMatchDialog({
    super.key,
    required this.initialSearchText,
  });
  
  @override
  State<ManualDanmakuMatchDialog> createState() => _ManualDanmakuMatchDialogState();
}

class _ManualDanmakuMatchDialogState extends State<ManualDanmakuMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _currentMatches = [];
  List<Map<String, dynamic>> _currentEpisodes = [];
  bool _isSearching = false;
  bool _isLoadingEpisodes = false;
  String _searchMessage = '';
  String _episodesMessage = '';
  
  // 匹配的动画和剧集状态
  Map<String, dynamic>? _selectedAnime;
  Map<String, dynamic>? _selectedEpisode;
  
  // 视图状态
  bool _showEpisodesView = false;
  
  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearchText;
    
    // 如果有初始搜索文本，自动执行搜索
    if (widget.initialSearchText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    } else {
      _searchMessage = '请输入动画名称进行搜索';
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 执行搜索动画
  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) return;
    
    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _showEpisodesView = false;
      _selectedAnime = null;
      _selectedEpisode = null;
      _currentEpisodes = [];
    });
    
    try {
      final results = await ManualDanmakuMatcher.instance.searchAnime(searchText);
      
      setState(() {
        _isSearching = false;
        _currentMatches = results;
        
        if (results.isEmpty) {
          _searchMessage = '没有找到匹配"$searchText"的结果';
        } else {
          _searchMessage = '';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
      });
    }
  }
  
  // 加载动画的剧集列表
  Future<void> _loadAnimeEpisodes(Map<String, dynamic> anime) async {
    if (anime['animeId'] == null) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画ID为空。';
        _currentEpisodes = [];
      });
      return;
    }
    if (anime['animeTitle'] == null || (anime['animeTitle'] as String).isEmpty) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画标题为空。';
        _currentEpisodes = [];
      });
      return;
    }
    
    final int animeId = anime['animeId'];
    final String animeTitle = anime['animeTitle'] as String;
    debugPrint('开始加载动画ID $animeId (标题: "$animeTitle") 的剧集列表');
    
    setState(() {
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _currentEpisodes = [];
      _selectedAnime = anime;
      _showEpisodesView = true;
    });
    
    try {
      final episodes = await ManualDanmakuMatcher.instance.getAnimeEpisodes(animeId, animeTitle);
      
      if (!mounted) return;
      
      debugPrint('加载到 ${episodes.length} 个剧集');
      
      setState(() {
        _isLoadingEpisodes = false;
        _currentEpisodes = episodes;
        
        if (episodes.isEmpty) {
          _episodesMessage = '没有找到该动画的剧集信息';
          debugPrint('动画 $animeId 没有剧集信息');
        } else {
          _episodesMessage = '';
          debugPrint('成功加载剧集: ${episodes.length} 集');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '加载剧集时出错: $e';
        _currentEpisodes = [];
      });
      debugPrint('加载剧集时出错: $e');
    }
  }
  
  // 返回动画选择列表
  void _backToAnimeSelection() {
    setState(() {
      _showEpisodesView = false;
      _selectedEpisode = null;
    });
  }
  
  // 完成选择并返回结果
  void _completeSelection() {
    if (_selectedAnime == null) return;
    
    // 创建最终结果对象
    final result = Map<String, dynamic>.from(_selectedAnime!);
    
    // 如果用户选择了剧集，添加剧集信息
    if (_selectedEpisode != null && _selectedEpisode!.isNotEmpty) {
      result['episodeId'] = _selectedEpisode!['episodeId'];
      result['episodeTitle'] = _selectedEpisode!['episodeTitle'];
      debugPrint('用户选择了剧集: ${_selectedEpisode!['episodeTitle']}, episodeId=${_selectedEpisode!['episodeId']}');
    } else {
      // 如果在剧集选择界面用户没有选择具体剧集，但有可用剧集，默认使用第一个
      if (_showEpisodesView && _currentEpisodes.isNotEmpty) {
        final firstEpisode = _currentEpisodes.first;
        result['episodeId'] = firstEpisode['episodeId'];
        result['episodeTitle'] = firstEpisode['episodeTitle'];
        debugPrint('用户没有选择具体剧集，默认使用第一个: ${firstEpisode['episodeTitle']}, episodeId=${firstEpisode['episodeId']}');
      } else {
        debugPrint('警告: 没有匹配到任何剧集信息，episodeId可能为空');
      }
    }
    
    Navigator.of(context).pop(result);
  }
  
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 5,
                spreadRadius: 1,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _showEpisodesView ? '选择匹配的剧集' : '手动匹配弹幕',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              
              // 内容区域
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 显示当前选择的动画（在剧集选择视图中）
                    if (_showEpisodesView && _selectedAnime != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('已选动画:',
                                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(_selectedAnime!['animeTitle'] ?? '未知动画',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      )),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white70),
                              label: const Text('返回', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              onPressed: _backToAnimeSelection,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // 手动搜索区域（只在动画选择视图中显示）
                    if (!_showEpisodesView)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: '输入动画名称搜索',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
                                  ),
                                ),
                                onSubmitted: (_) => _performSearch(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _isSearching ? null : _performSearch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.2),
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                              ),
                              child: const Text('搜索'),
                            ),
                          ],
                        ),
                      ),
                    
                    // 动画选择视图
                    if (!_showEpisodesView) ...[
                      const Text('搜索结果:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      
                      if (_searchMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _searchMessage.contains('出错') 
                                ? Colors.red.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_searchMessage, 
                            style: TextStyle(
                              color: _searchMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                            ),
                          ),
                        ),
                      
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                          child: _isSearching 
                            ? const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                )
                              )
                            : _currentMatches.isEmpty
                              ? const Center(
                                  child: Text('没有搜索结果', style: TextStyle(color: Colors.white54))
                                )
                              : ListView.builder(
                                  itemCount: _currentMatches.length,
                                  itemBuilder: (context, index) {
                                    final match = _currentMatches[index];
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: ListTile(
                                        title: Text(
                                          match['animeTitle'] ?? '未知动画',
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                        subtitle: match['typeDescription'] != null
                                            ? Text(
                                                match['typeDescription'],
                                                style: const TextStyle(color: Colors.white70),
                                              )
                                            : null,
                                        onTap: () => _loadAnimeEpisodes(match),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                    
                    // 剧集选择视图
                    if (_showEpisodesView) ...[
                      const Text('请选择匹配的剧集:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      
                      if (_episodesMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _episodesMessage.contains('出错') 
                                ? Colors.red.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_episodesMessage, 
                            style: TextStyle(
                              color: _episodesMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                          child: _isLoadingEpisodes 
                            ? const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                )
                              )
                            : _currentEpisodes.isEmpty
                              ? const Center(
                                  child: Text('没有找到剧集', style: TextStyle(color: Colors.white54))
                                )
                              : ListView.builder(
                                  itemCount: _currentEpisodes.length,
                                  itemBuilder: (context, index) {
                                    final episode = _currentEpisodes[index];
                                    final bool isSelected = _selectedEpisode != null &&
                                        _selectedEpisode!['episodeId'] == episode['episodeId'];
                                    
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isSelected 
                                            ? Colors.green.withOpacity(0.3)
                                            : Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(6),
                                        border: isSelected 
                                            ? Border.all(color: Colors.green.withOpacity(0.5))
                                            : null,
                                      ),
                                      child: ListTile(
                                        title: Text(
                                          '${episode['episodeTitle'] ?? '未知剧集'}',
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                        trailing: isSelected 
                                          ? const Icon(Icons.check_circle, color: Colors.green)
                                          : null,
                                        onTap: () {
                                          setState(() {
                                            _selectedEpisode = episode;
                                          });
                                        },
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      
                      if (_currentEpisodes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            _selectedEpisode == null 
                              ? '请选择一个剧集来获取正确的弹幕'
                              : '已选择剧集，点击"确认选择"继续',
                            style: TextStyle(
                              color: _selectedEpisode == null ? Colors.white70 : Colors.green
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              
              // 操作按钮区域
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
                              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_showEpisodesView) ...[
                    TextButton(
                      onPressed: _backToAnimeSelection,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('返回动画选择'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_showEpisodesView && _currentEpisodes.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 0.5,
                            ),
                          ),
                          child: TextButton(
                            onPressed: _completeSelection,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            child: Text(_selectedEpisode != null 
                              ? '确认选择剧集' 
                              : '使用第一集'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
