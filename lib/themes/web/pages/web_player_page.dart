import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/themes/fluent/widgets/fluent_video_controls_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_widget.dart';
import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class WebPlayerPage extends StatefulWidget {
  const WebPlayerPage({
    super.key,
    required this.item,
  });

  final WebPlaybackItem? item;

  @override
  State<WebPlayerPage> createState() => _WebPlayerPageState();
}

class _WebPlayerPageState extends State<WebPlayerPage> {
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadItem(widget.item);
  }

  @override
  void didUpdateWidget(covariant WebPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?.uri != widget.item?.uri) {
      _loadItem(widget.item);
    }
  }

  Future<void> _loadItem(WebPlaybackItem? item) async {
    final int generation = ++_loadGeneration;
    if (!mounted) return;

    final videoState = context.read<VideoPlayerState>();

    if (item == null) {
      // 不强制 reset，避免频繁切换时闪烁；用户可用播放器返回按钮清空。
      return;
    }

    final uriString = item.uri.toString();
    final displayAnimeTitle =
        (item.subtitle ?? '').trim().isEmpty ? '远程播放' : item.subtitle!;

    try {
      await videoState.initializePlayer(
        uriString,
        displayAnimeTitle: displayAnimeTitle,
        displayEpisodeTitle: item.title,
      );
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      // VideoPlayerState 会自行进入 error 状态，这里不额外弹窗。
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item == null) {
      return const Center(
        child: Text('暂无播放内容，请从媒体库/观看记录中选择剧集进行播放。'),
      );
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: VideoPlayerWidget()),
              if (videoState.hasVideo) const FluentVideoControlsOverlay(),
            ],
          ),
        );
      },
    );
  }
}
