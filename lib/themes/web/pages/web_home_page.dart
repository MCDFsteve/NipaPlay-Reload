import 'package:fluent_ui/fluent_ui.dart';

import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/themes/web/pages/web_history_page.dart';
import 'package:nipaplay/themes/web/pages/web_library_page.dart';
import 'package:nipaplay/themes/web/pages/web_management_page.dart';
import 'package:nipaplay/themes/web/pages/web_player_page.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';

class WebHomePage extends StatefulWidget {
  const WebHomePage({super.key});

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  int _index = 1;
  final TextEditingController _searchController = TextEditingController();
  WebPlaybackItem? _nowPlaying;

  late final WebRemoteApiClient _api =
      WebRemoteApiClient(baseUrl: _resolveApiBaseUrl());

  void _play(WebPlaybackItem item) {
    setState(() {
      _nowPlaying = item;
      _index = 0;
    });
  }

  String? _resolveApiBaseUrl() {
    final uri = Uri.base;
    final rawBaseUrl = uri.queryParameters['api'] ??
        uri.queryParameters['apiBase'] ??
        uri.queryParameters['baseUrl'];
    final normalizedBaseUrl = rawBaseUrl?.trim();
    if (normalizedBaseUrl != null && normalizedBaseUrl.isNotEmpty) {
      return normalizedBaseUrl;
    }

    final rawPort = uri.queryParameters['apiPort']?.trim();
    final port = int.tryParse(rawPort ?? '');
    if (port != null && port > 0 && port < 65536) {
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final host = uri.host.isNotEmpty ? uri.host : 'localhost';
      return '$scheme://$host:$port';
    }

    return null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String searchQuery = _searchController.text;

    return NavigationView(
      appBar: NavigationAppBar(
        title: Row(
          children: [
            const _WebLogo(),
            const SizedBox(width: 12),
            Expanded(
              child: _SearchBox(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '打开 API /info',
              child: IconButton(
                icon: const Icon(FluentIcons.info),
                onPressed: () async {
                  final info = await _api.fetchInfoSafe();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => ContentDialog(
                      title: const Text('远程访问 API'),
                      content: SizedBox(
                        width: 560,
                        child: SelectableText(
                          info ?? '无法获取 /api/info（请确认服务端已开启远程访问）',
                        ),
                      ),
                      actions: [
                        Button(
                          child: const Text('关闭'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      pane: NavigationPane(
        selected: _index,
        onChanged: (index) {
          setState(() {
            _index = index;
          });
        },
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.play),
            title: const Text('播放'),
            body: WebPlayerPage(item: _nowPlaying),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.video),
            title: const Text('媒体库'),
            body: WebLibraryPage(
              api: _api,
              searchQuery: searchQuery,
              onPlay: _play,
            ),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.folder_open),
            title: const Text('库管理'),
            body: WebManagementPage(api: _api, onPlay: _play),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.history),
            title: const Text('观看记录'),
            body: WebHistoryPage(
              api: _api,
              searchQuery: searchQuery,
              onPlay: _play,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebLogo extends StatelessWidget {
  const _WebLogo();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FluentIcons.play, color: theme.accentColor),
        const SizedBox(width: 8),
        const Text(
          'NipaPlay',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: TextBox(
        controller: controller,
        onChanged: onChanged,
        placeholder: '搜索标题…',
        prefix: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(FluentIcons.search, size: 16),
        ),
      ),
    );
  }
}
