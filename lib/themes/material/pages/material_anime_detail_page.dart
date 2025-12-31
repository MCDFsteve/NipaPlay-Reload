import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class MaterialAnimeDetailPage extends StatefulWidget {
  final int animeId;
  final SharedRemoteAnimeSummary? sharedSummary;
  final Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader;
  final PlayableItem Function(SharedRemoteEpisode episode)? sharedEpisodeBuilder;
  final String? sharedSourceLabel;

  const MaterialAnimeDetailPage({
    super.key,
    required this.animeId,
    this.sharedSummary,
    this.sharedEpisodeLoader,
    this.sharedEpisodeBuilder,
    this.sharedSourceLabel,
  });

  static Future<WatchHistoryItem?> show(
    BuildContext context,
    int animeId, {
    SharedRemoteAnimeSummary? sharedSummary,
    Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader,
    PlayableItem Function(SharedRemoteEpisode episode)? sharedEpisodeBuilder,
    String? sharedSourceLabel,
  }) {
    final size = MediaQuery.of(context).size;
    final bool isCompact = size.width < 600;

    return showDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final content = MaterialAnimeDetailPage(
          animeId: animeId,
          sharedSummary: sharedSummary,
          sharedEpisodeLoader: sharedEpisodeLoader,
          sharedEpisodeBuilder: sharedEpisodeBuilder,
          sharedSourceLabel: sharedSourceLabel,
        );

        if (isCompact) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: content,
            ),
          );
        }

        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
            child: SizedBox(width: 1000, height: 820, child: content),
          ),
        );
      },
    );
  }

  @override
  State<MaterialAnimeDetailPage> createState() => _MaterialAnimeDetailPageState();
}

class _MaterialAnimeDetailPageState extends State<MaterialAnimeDetailPage> {
  final BangumiService _bangumiService = BangumiService.instance;

  BangumiAnime? _anime;
  bool _loading = true;
  String? _error;

  bool _isEpisodeListReversed = false;

  bool _isLoadingSharedEpisodes = false;
  String? _sharedEpisodesError;
  final Map<int, SharedRemoteEpisode> _sharedEpisodeMap = {};
  final Map<int, PlayableItem> _sharedPlayableMap = {};

  @override
  void initState() {
    super.initState();
    _fetchAnimeDetails();

    if (widget.sharedEpisodeLoader != null && widget.sharedEpisodeBuilder != null) {
      _loadSharedEpisodes();
    }
  }

  Future<void> _fetchAnimeDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      BangumiAnime anime;
      if (kIsWeb) {
        final response =
            await http.get(Uri.parse('/api/bangumi/detail/${widget.animeId}'));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final data = json.decode(utf8.decode(response.bodyBytes));
        anime = BangumiAnime.fromJson(data as Map<String, dynamic>);
      } else {
        anime = await _bangumiService.getAnimeDetails(widget.animeId);
      }

      if (!mounted) return;
      setState(() {
        _anime = anime;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSharedEpisodes() async {
    if (widget.sharedEpisodeLoader == null || widget.sharedEpisodeBuilder == null) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingSharedEpisodes = true;
      _sharedEpisodesError = null;
      _sharedEpisodeMap.clear();
      _sharedPlayableMap.clear();
    });

    try {
      final episodes = await widget.sharedEpisodeLoader!.call();
      if (!mounted) return;
      setState(() {
        for (final episode in episodes) {
          final episodeId = episode.episodeId;
          if (episodeId == null) continue;
          _sharedEpisodeMap[episodeId] = episode;
          _sharedPlayableMap[episodeId] = widget.sharedEpisodeBuilder!.call(episode);
        }
        _isLoadingSharedEpisodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sharedEpisodesError = e.toString();
        _isLoadingSharedEpisodes = false;
        _sharedEpisodeMap.clear();
        _sharedPlayableMap.clear();
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis)),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '${twoDigits(hours)}:$minutes:$seconds' : '$minutes:$seconds';
  }

  String? _displayTitle(BangumiAnime anime) {
    final sharedNameCn = widget.sharedSummary?.nameCn;
    if (sharedNameCn != null && sharedNameCn.trim().isNotEmpty) {
      return sharedNameCn.trim();
    }
    final nameCn = anime.nameCn.trim();
    return nameCn.isEmpty ? anime.name.trim() : nameCn;
  }

  String? _displaySubtitle(BangumiAnime anime) {
    final sharedName = widget.sharedSummary?.name;
    if (sharedName != null && sharedName.trim().isNotEmpty) {
      return sharedName.trim();
    }
    final name = anime.name.trim();
    if (name.isEmpty) return null;
    if (name == anime.nameCn.trim()) return null;
    return name;
  }

  String _coverUrl(BangumiAnime anime) {
    final sharedCover = widget.sharedSummary?.imageUrl;
    if (sharedCover != null && sharedCover.trim().isNotEmpty) {
      return sharedCover.trim();
    }
    return anime.imageUrl;
  }

  String? _primaryRatingLabel(BangumiAnime anime) {
    final bangumi = anime.ratingDetails?['Bangumi评分'];
    if (bangumi is num && bangumi > 0) {
      return bangumi.toStringAsFixed(1);
    }
    if (anime.rating != null && anime.rating! > 0) {
      return anime.rating!.toStringAsFixed(1);
    }
    return null;
  }

  Future<void> _playFromHistory(
    BangumiAnime anime,
    EpisodeData episode,
    WatchHistoryItem historyItem,
  ) async {
    final path = historyItem.filePath;
    if (path.trim().isEmpty) {
      _showMessage('媒体库中找不到此剧集的视频文件');
      return;
    }

    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme.toLowerCase();
    final bool shouldCheckFile =
        !kIsWeb && scheme != 'http' && scheme != 'https' && scheme != 'jellyfin' && scheme != 'emby';

    if (shouldCheckFile) {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('文件已不存在于: $path');
        return;
      }
    }

    await PlaybackService().play(
      PlayableItem(
        videoPath: path,
        title: anime.nameCn,
        subtitle: episode.title,
        animeId: anime.id,
        episodeId: episode.id,
        historyItem: historyItem,
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _playShared(PlayableItem playableItem) async {
    await PlaybackService().play(playableItem);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildCover(BuildContext context, String url) {
    if (url.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.image_outlined, size: 48)),
      );
    }
    final displayUrl = (kIsWeb && url.startsWith('http'))
        ? '/api/image_proxy?url=${Uri.encodeComponent(url)}'
        : url;

    return CachedNetworkImageWidget(
      imageUrl: displayUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
        );
      },
    );
  }

  Widget _buildInfoTab(BuildContext context, BangumiAnime anime) {
    final title = _displayTitle(anime);
    final subtitle = _displaySubtitle(anime);
    final ratingLabel = _primaryRatingLabel(anime);
    final tags = (anime.tags ?? const <String>[])
        .where((t) => t.trim().isNotEmpty)
        .toList();

    final summaryText = (widget.sharedSummary?.summary?.trim().isNotEmpty == true)
        ? widget.sharedSummary!.summary!.trim()
        : (anime.summary?.trim() ?? '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 130,
                height: 180,
                child: _buildCover(context, _coverUrl(anime)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.sharedSourceLabel != null &&
                          widget.sharedSourceLabel!.trim().isNotEmpty)
                        Chip(label: Text(widget.sharedSourceLabel!.trim())),
                      if (ratingLabel != null)
                        Chip(
                          avatar: const Icon(Icons.star_rounded, size: 18),
                          label: Text(ratingLabel),
                        ),
                      if ((anime.airDate ?? '').trim().isNotEmpty)
                        Chip(label: Text('开播：${anime.airDate!.trim()}')),
                      if (anime.totalEpisodes != null && anime.totalEpisodes! > 0)
                        Chip(label: Text('话数：${anime.totalEpisodes}')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (summaryText.trim().isNotEmpty) ...[
          Text('简介', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            summaryText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
        if (tags.isNotEmpty) ...[
          Text('标签', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.take(24).map((t) => InputChip(label: Text(t))).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEpisodesTab(BuildContext context, BangumiAnime anime) {
    final episodes = (anime.episodeList ?? const <EpisodeData>[])
        .where((e) => e.title.trim().isNotEmpty)
        .toList();

    final list = _isEpisodeListReversed ? episodes.reversed.toList() : episodes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('剧集', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: _isEpisodeListReversed ? '切换为正序' : '切换为倒序',
                onPressed: () =>
                    setState(() => _isEpisodeListReversed = !_isEpisodeListReversed),
                icon: Icon(
                  _isEpisodeListReversed
                      ? Icons.south_rounded
                      : Icons.north_rounded,
                ),
              ),
            ],
          ),
        ),
        if (_isLoadingSharedEpisodes)
          const LinearProgressIndicator(minHeight: 2),
        if (_sharedEpisodesError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '共享剧集加载失败：$_sharedEpisodesError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final episode = list[index];
              final sharedEpisode = _sharedEpisodeMap[episode.id];
              final sharedPlayable = sharedEpisode != null
                  ? _sharedPlayableMap[episode.id]
                  : null;
              final bool sharedPlayableAvailable =
                  sharedEpisode != null && sharedPlayable != null && sharedEpisode.fileExists;

              return FutureBuilder<WatchHistoryItem?>(
                future: WatchHistoryManager.getHistoryItemByEpisode(
                  anime.id,
                  episode.id,
                ),
                builder: (context, snapshot) {
                  final historyItem =
                      snapshot.connectionState == ConnectionState.done
                          ? snapshot.data
                          : null;

                  double progress = sharedEpisode?.progress ?? 0.0;
                  if (historyItem != null &&
                      historyItem.watchProgress >= progress) {
                    progress = historyItem.watchProgress;
                  }

                  final progressText = progress > 0.01
                      ? '${(progress * 100).toStringAsFixed(0)}%'
                      : (sharedPlayableAvailable ? '共享媒体' : null);

                  final trailing = progressText == null
                      ? null
                      : Text(
                          progressText,
                          style: Theme.of(context).textTheme.labelMedium,
                        );

                  return ListTile(
                    dense: true,
                    title: Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: (historyItem != null &&
                            historyItem.duration > 0 &&
                            historyItem.lastPosition > 0)
                        ? Text(
                            '${_formatDuration(Duration(seconds: historyItem.lastPosition))} / ${_formatDuration(Duration(seconds: historyItem.duration))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: trailing,
                      onTap: () async {
                      if (sharedPlayableAvailable) {
                        await _playShared(sharedPlayable);
                        return;
                      }

                      if (snapshot.connectionState != ConnectionState.done) {
                        _showMessage('正在加载剧集信息...');
                        return;
                      }
                      if (historyItem == null) {
                        _showMessage('媒体库中找不到此剧集的视频文件');
                        return;
                      }
                      await _playFromHistory(anime, episode, historyItem);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_anime == null || _error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('番剧详情'),
          actions: [
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：${_error ?? '未知错误'}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _fetchAnimeDetails,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final anime = _anime!;

    final title = _displayTitle(anime) ?? '番剧详情';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: theme.colorScheme.surfaceTint,
          actions: [
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '简介'),
              Tab(text: '剧集'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInfoTab(context, anime),
            _buildEpisodesTab(context, anime),
          ],
        ),
      ),
    );
  }
}
