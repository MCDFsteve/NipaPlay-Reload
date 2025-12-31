import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';

class WebManagementPage extends StatefulWidget {
  const WebManagementPage({
    super.key,
    required this.api,
    required this.onPlay,
  });

  final WebRemoteApiClient api;
  final ValueChanged<WebPlaybackItem> onPlay;

  @override
  State<WebManagementPage> createState() => _WebManagementPageState();
}

class _WebManagementPageState extends State<WebManagementPage> {
  late Future<WebManagementData> _future;
  final TextEditingController _folderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchManagement();
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = widget.api.fetchManagement();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('库管理'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: _refresh,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.search),
              label: const Text('重新扫描'),
              onPressed: () async {
                await widget.api.rescanAll();
                _refresh();
              },
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<WebManagementData>(
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

            final data = snapshot.data ?? const WebManagementData();
            final status = data.scanStatus;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status != null) ...[
                  _ScanStatusCard(status: status),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _FoldersCard(
                          folders: data.folders,
                          onRemove: (path) async {
                            await widget.api.removeFolder(path);
                            _refresh();
                          },
                          onBrowse: (path) async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => ContentDialog(
                                title: const Text('远程浏览'),
                                content: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 980,
                                    maxHeight: 720,
                                  ),
                                  child: _RemoteBrowser(
                                    api: widget.api,
                                    initialPath: path,
                                    onPlay: widget.onPlay,
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
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: _AddFolderCard(
                          controller: _folderController,
                          onAdd: (path) async {
                            await widget.api.addFolder(path, scan: true);
                            _folderController.clear();
                            _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({required this.status});

  final SharedRemoteScanStatus status;

  @override
  Widget build(BuildContext context) {
    final bool scanning = status.isScanning;
    final double progress = status.progress.clamp(0.0, 1.0);

    return Card(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(scanning ? FluentIcons.sync : FluentIcons.completed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scanning ? '扫描中' : '空闲',
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 8),
                ProgressBar(value: scanning ? progress * 100 : null),
                const SizedBox(height: 8),
                Text(
                  [
                    if (status.message.isNotEmpty) status.message,
                    '已发现文件：${status.totalFilesFound}',
                  ].join(' · '),
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoldersCard extends StatelessWidget {
  const _FoldersCard({
    required this.folders,
    required this.onRemove,
    required this.onBrowse,
  });

  final List<SharedRemoteScannedFolder> folders;
  final Future<void> Function(String path) onRemove;
  final Future<void> Function(String path) onBrowse;

  @override
  Widget build(BuildContext context) {
    return Card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '扫描文件夹',
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: folders.isEmpty
                ? const Center(child: Text('暂无扫描文件夹'))
                : ListView.separated(
                    itemCount: folders.length,
                    separatorBuilder: (_, __) => const Divider(size: 1),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile.selectable(
                        leading: Icon(
                          folder.exists
                              ? FluentIcons.fabric_folder
                              : FluentIcons.folder_open,
                        ),
                        title: Text(folder.name),
                        subtitle: Text(folder.path),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: '浏览',
                              child: IconButton(
                                icon: const Icon(FluentIcons.search),
                                onPressed: () => onBrowse(folder.path),
                              ),
                            ),
                            Tooltip(
                              message: '移除',
                              child: IconButton(
                                icon: const Icon(FluentIcons.delete),
                                onPressed: () => onRemove(folder.path),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddFolderCard extends StatelessWidget {
  const _AddFolderCard({
    required this.controller,
    required this.onAdd,
  });

  final TextEditingController controller;
  final Future<void> Function(String path) onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '添加文件夹（服务端路径）',
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          TextBox(
            controller: controller,
            placeholder: '/Volumes/Media/Anime',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isEmpty) return;
                await onAdd(path);
              },
              child: const Text('添加并扫描'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '提示：此处填写的是运行 NipaPlay 的机器上的绝对路径。',
            style: FluentTheme.of(context).typography.caption,
          ),
        ],
      ),
    );
  }
}

class _RemoteBrowser extends StatefulWidget {
  const _RemoteBrowser({
    required this.api,
    required this.initialPath,
    required this.onPlay,
  });

  final WebRemoteApiClient api;
  final String initialPath;
  final ValueChanged<WebPlaybackItem> onPlay;

  @override
  State<_RemoteBrowser> createState() => _RemoteBrowserState();
}

class _RemoteBrowserState extends State<_RemoteBrowser> {
  late String _path;
  late Future<List<SharedRemoteFileEntry>> _future;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _future = widget.api.browseDirectory(_path);
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _future = widget.api.browseDirectory(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: '当前路径',
            child: Text(
              _path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<SharedRemoteFileEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: ProgressRing());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    title: '读取目录失败',
                    message: snapshot.error.toString(),
                    onRetry: () => _open(_path),
                  );
                }
                final entries = snapshot.data ?? const <SharedRemoteFileEntry>[];
                if (entries.isEmpty) {
                  return const Center(child: Text('空目录'));
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(size: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final subtitle = <String>[
                      if (entry.modifiedTime != null)
                        DateFormat('yyyy-MM-dd HH:mm')
                            .format(entry.modifiedTime!.toLocal()),
                      if (!entry.isDirectory && entry.size != null)
                        '${(entry.size! / (1024 * 1024)).toStringAsFixed(1)} MB',
                      if (entry.animeName?.isNotEmpty == true) entry.animeName!,
                      if (entry.episodeTitle?.isNotEmpty == true)
                        entry.episodeTitle!,
                    ].join(' · ');

                    return ListTile.selectable(
                      leading: Icon(
                        entry.isDirectory
                            ? FluentIcons.fabric_folder
                            : FluentIcons.video,
                      ),
                      title: Text(entry.name),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      onPressed:
                          entry.isDirectory ? () => _open(entry.path) : null,
                      trailing: entry.isDirectory
                          ? const Icon(FluentIcons.chevron_right_small)
                          : FilledButton(
                              onPressed: () {
                                final uri =
                                    widget.api.resolveManageStream(entry.path);
                                widget.onPlay(
                                  WebPlaybackItem(
                                    uri: uri,
                                    title: entry.name,
                                    subtitle: entry.path,
                                  ),
                                );
                                Navigator.of(context).pop();
                              },
                              child: const Text('播放'),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
