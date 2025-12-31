import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/airplay_route_picker.dart';

class MaterialVideoControlsOverlay extends StatelessWidget {
  const MaterialVideoControlsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final videoState = context.watch<VideoPlayerState>();
    if (!videoState.hasVideo) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => videoState.setControlsHovered(true),
      onExit: (_) => videoState.setControlsHovered(false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: videoState.showControls ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !videoState.showControls,
          child: Stack(
            children: const [
              _MaterialPlayerHeader(),
              _MaterialPlayerControlBar(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialPlayerHeader extends StatelessWidget {
  const _MaterialPlayerHeader();

  Future<void> _shareCurrent(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    if (!SystemShareService.isSupported) return;

    final currentVideoPath = videoState.currentVideoPath;
    final currentActualUrl = videoState.currentActualPlayUrl;

    String? filePath;
    String? url;

    if (currentVideoPath != null && currentVideoPath.isNotEmpty) {
      final uri = Uri.tryParse(currentVideoPath);
      final scheme = uri?.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        url = currentVideoPath;
      } else if (scheme == 'jellyfin' || scheme == 'emby') {
        url = currentActualUrl;
      } else if (scheme == 'smb' || scheme == 'webdav' || scheme == 'dav') {
        url = currentVideoPath;
      } else {
        filePath = currentVideoPath;
      }
    } else {
      url = currentActualUrl;
    }

    final titleParts = <String>[
      if ((videoState.animeTitle ?? '').trim().isNotEmpty)
        videoState.animeTitle!.trim(),
      if ((videoState.episodeTitle ?? '').trim().isNotEmpty)
        videoState.episodeTitle!.trim(),
    ];
    final subject = titleParts.isEmpty ? null : titleParts.join(' · ');

    if ((filePath == null || filePath.isEmpty) && (url == null || url.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可分享的内容')));
      return;
    }

    try {
      await SystemShareService.share(
        text: subject,
        url: url,
        filePath: filePath,
        subject: subject,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  Future<void> _showAirPlayPicker(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('投屏', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 12),
                Text('点击下方 AirPlay 图标选择设备'),
                SizedBox(height: 16),
                Center(child: AirPlayRoutePicker(size: 44)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoState = context.watch<VideoPlayerState>();

    final showBack =
        videoState.hasVideo && !(globals.isDesktop && videoState.isFullscreen);
    final showShare =
        SystemShareService.isSupported && !globals.isDesktop;
    final showAirPlay =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (showBack)
                  IconButton(
                    tooltip: '返回',
                    onPressed: () async {
                      try {
                        await videoState.handleBackButton();
                        await videoState.resetPlayer();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('返回失败: $e')));
                      }
                    },
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                if (showBack) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((videoState.animeTitle ?? '').trim().isNotEmpty)
                        Text(
                          videoState.animeTitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      if ((videoState.episodeTitle ?? '').trim().isNotEmpty)
                        Text(
                          videoState.episodeTitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                if (showAirPlay)
                  IconButton(
                    tooltip: '投屏 (AirPlay)',
                    onPressed: () async {
                      videoState.resetHideControlsTimer();
                      await _showAirPlayPicker(context);
                    },
                    icon: const Icon(Icons.airplay_rounded, color: Colors.white),
                  ),
                if (showShare)
                  IconButton(
                    tooltip: '分享',
                    onPressed: () async {
                      videoState.resetHideControlsTimer();
                      await _shareCurrent(context, videoState);
                    },
                    icon: const Icon(Icons.share_rounded, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MaterialPlayerControlBar extends StatefulWidget {
  const _MaterialPlayerControlBar();

  @override
  State<_MaterialPlayerControlBar> createState() =>
      _MaterialPlayerControlBarState();
}

class _MaterialPlayerControlBarState extends State<_MaterialPlayerControlBar> {
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '${twoDigits(hours)}:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _seekBy(VideoPlayerState videoState, int deltaSeconds) {
    final next = videoState.position + Duration(seconds: deltaSeconds);
    videoState.seekTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final videoState = context.watch<VideoPlayerState>();

    final durationMs =
        videoState.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final positionMs = videoState.position.inMilliseconds
        .toDouble()
        .clamp(0.0, durationMs);

    final bool canPrev = videoState.canPlayPreviousEpisode;
    final bool canNext = videoState.canPlayNextEpisode;
    final bool showFullscreen =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    final Color? settingsColor = videoState.showRightMenu
        ? Theme.of(context).colorScheme.primary
        : null;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: positionMs,
                    min: 0,
                    max: durationMs,
                    onChanged: (value) {
                      videoState.seekTo(Duration(milliseconds: value.round()));
                    },
                    onChangeStart: (_) => videoState.setControlsHovered(true),
                    onChangeEnd: (_) => videoState.setControlsHovered(false),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: canPrev ? '上一话' : '无法播放上一话',
                      onPressed: canPrev
                          ? () async {
                              videoState.resetHideControlsTimer();
                              await videoState.playPreviousEpisode();
                            }
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: '快退 ${videoState.seekStepSeconds} 秒',
                      onPressed: () {
                        videoState.resetHideControlsTimer();
                        _seekBy(videoState, -videoState.seekStepSeconds);
                      },
                      icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white),
                    ),
                    Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: videoState.status == PlayerStatus.playing
                            ? '暂停'
                            : '播放',
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          videoState.togglePlayPause();
                        },
                        icon: Icon(
                          videoState.status == PlayerStatus.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '快进 ${videoState.seekStepSeconds} 秒',
                      onPressed: () {
                        videoState.resetHideControlsTimer();
                        _seekBy(videoState, videoState.seekStepSeconds);
                      },
                      icon: const Icon(Icons.fast_forward_rounded, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: canNext ? '下一话' : '无法播放下一话',
                      onPressed: canNext
                          ? () async {
                              videoState.resetHideControlsTimer();
                              await videoState.playNextEpisode();
                            }
                          : null,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '设置',
                      onPressed: () {
                        videoState.resetHideControlsTimer();
                        videoState.toggleRightMenu();
                      },
                      icon: Icon(Icons.settings_rounded, color: settingsColor ?? Colors.white),
                    ),
                    if (showFullscreen)
                      IconButton(
                        tooltip: videoState.isFullscreen ? '退出全屏' : '全屏',
                        onPressed: () async {
                          videoState.resetHideControlsTimer();
                          await videoState.toggleFullscreen();
                        },
                        icon: Icon(
                          videoState.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
