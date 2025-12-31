import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';

class WebHistoryPage extends StatefulWidget {
  const WebHistoryPage({
    super.key,
    required this.api,
    required this.searchQuery,
    required this.onPlay,
  });

  final WebRemoteApiClient api;
  final String searchQuery;
  final ValueChanged<WebPlaybackItem> onPlay;

  @override
  State<WebHistoryPage> createState() => _WebHistoryPageState();
}

class _WebHistoryPageState extends State<WebHistoryPage> {
  late Future<List<WebRemoteHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchWatchHistory();
  }

  @override
  void didUpdateWidget(covariant WebHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api.baseUrl != widget.api.baseUrl) {
      _future = widget.api.fetchWatchHistory();
    }
  }

  void _refresh() {
    setState(() {
      _future = widget.api.fetchWatchHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('观看记录'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: _refresh,
            ),
          ],
        ),
      ),
      content: FutureBuilder<List<WebRemoteHistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: ProgressRing());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              title: '加载失败',
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final items = snapshot.data ?? const <WebRemoteHistoryEntry>[];
          final filtered = _filter(items, widget.searchQuery);
          if (filtered.isEmpty) {
            return const Center(child: Text('暂无观看记录'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _HistoryCard(
                entry: filtered[index],
                onPlay: () {
                  final uri = widget.api.resolveExternal(
                    filtered[index].episode.streamPath,
                  );
                  widget.onPlay(
                    WebPlaybackItem(
                      uri: uri,
                      title: filtered[index].episode.title,
                      subtitle: filtered[index].animeName,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<WebRemoteHistoryEntry> _filter(
    List<WebRemoteHistoryEntry> items,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return items;
    return items.where((entry) {
      final t1 = (entry.animeName ?? '').toLowerCase();
      final t2 = entry.episode.title.toLowerCase();
      return t1.contains(normalized) || t2.contains(normalized);
    }).toList(growable: false);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onPlay,
  });

  final WebRemoteHistoryEntry entry;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final ep = entry.episode;
    final double progress = (ep.progress ?? 0).clamp(0.0, 1.0);
    final String timeText = DateFormat('yyyy-MM-dd HH:mm')
        .format((ep.lastWatchTime ?? DateTime.now()).toLocal());

    return Card(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(imageUrl: entry.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.animeName ?? '未知标题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 4),
                Text(
                  ep.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                ProgressBar(value: progress * 100),
                const SizedBox(height: 6),
                Text(
                  '$timeText · ${(progress * 100).toStringAsFixed(1)}%',
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onPlay, child: const Text('播放')),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 112,
        height: 72,
        child: (imageUrl ?? '').isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFE9ECEF),
                  child: Center(child: Icon(FluentIcons.warning)),
                ),
              )
            : const ColoredBox(
                color: Color(0xFFE9ECEF),
                child: Center(child: Icon(FluentIcons.photo2)),
              ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: InfoBar(
          title: Text(title),
          content: Text(message),
          severity: InfoBarSeverity.error,
          isLong: true,
          action: Button(
            child: const Text('重试'),
            onPressed: onRetry,
          ),
        ),
      ),
    );
  }
}
