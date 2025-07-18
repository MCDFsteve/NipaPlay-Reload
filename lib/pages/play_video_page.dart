import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../widgets/vertical_indicator.dart';
import '../utils/globals.dart' as globals;
import '../widgets/video_controls_overlay.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/anime_info_widget.dart';
import '../utils/tab_change_notifier.dart';
import 'package:flutter/gestures.dart';

class PlayVideoPage extends StatefulWidget {
  final String? videoPath;
  
  const PlayVideoPage({super.key, this.videoPath});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  bool _isHoveringAnimeInfo = false;
  bool _isHoveringBackButton = false;
  double _horizontalDragDistance = 0.0;

  @override
  void initState() {
    super.initState();
  }
  
  // 处理系统返回键事件
  Future<bool> _handleWillPop() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    return await videoState.handleBackButton();
  }

  void _handleSideSwipeDragStart(DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance = 0.0;
      //debugPrint("[PlayVideoPage] Side swipe drag start.");
    }
  }

  void _handleSideSwipeDragUpdate(DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance += details.delta.dx;
    }
  }

  void _handleSideSwipeDragEnd(DragEndDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!(globals.isPhone && videoState.isFullscreen)) {
      _horizontalDragDistance = 0.0;
      return;
    }

    //debugPrint("[PlayVideoPage] Side swipe drag end.");
    //debugPrint("[PlayVideoPage] Accumulated Drag Distance: $_horizontalDragDistance");
    //debugPrint("[PlayVideoPage] Drag Velocity: ${details.primaryVelocity}");

    // 先检查是否存在DefaultTabController，避免异常
    final TabController? tabController = 
        context.findAncestorWidgetOfExactType<DefaultTabController>() != null
        ? DefaultTabController.of(context)
        : null;
        
    if (tabController == null) {
      // 如果不存在TabController，直接返回
      _horizontalDragDistance = 0.0;
      return;
    }
    
    final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);

    final currentIndex = tabController.index;
    final tabCount = tabController.length;
    int newIndex = currentIndex;
    
    final double dragThreshold = MediaQuery.of(context).size.width / 15;
    //debugPrint("[PlayVideoPage] Drag Threshold: $dragThreshold");

    if (_horizontalDragDistance < -dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Left detected (by distance).");
      if (currentIndex < tabCount - 1) {
        newIndex = currentIndex + 1;
      }
    } else if (_horizontalDragDistance > dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Right detected (by distance).");
      if (currentIndex > 0) {
        newIndex = currentIndex - 1;
      }
    } else {
       //debugPrint("[PlayVideoPage] Drag distance not enough for side swipe.");
    }

    if (newIndex != currentIndex) {
      //debugPrint("[PlayVideoPage] Changing tab to index: $newIndex via side swipe.");
      tabChangeNotifier.changeTab(newIndex);
    } else {
      //debugPrint("[PlayVideoPage] No tab change needed from side swipe.");
    }
    _horizontalDragDistance = 0.0;
  }

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return WillPopScope(
          onWillPop: _handleWillPop,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          color: videoState.hasVideo 
              ? Colors.black 
              : Colors.transparent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(
                  child: VideoPlayerWidget(),
                ),
                if (videoState.hasVideo) ...[
                  // 弹幕已经在VideoPlayerWidget内部处理，这里不需要重复创建
                  Consumer<VideoPlayerState>(
                    builder: (context, videoState, _) {
                      return VerticalIndicator(videoState: videoState);
                    },
                  ),
                  Positioned(
                    top: 16.0,
                    left: 16.0,
                    child: AnimatedOpacity(
                      opacity: videoState.showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !videoState.showControls,
                        child: Row(
                          children: [
                            MouseRegion(
                              cursor: _isHoveringBackButton
                                  ? SystemMouseCursors.click
                                  : SystemMouseCursors.basic,
                              onEnter: (_) => setState(() => _isHoveringBackButton = true),
                              onExit: (_) => setState(() => _isHoveringBackButton = false),
                              child: BackButtonWidget(videoState: videoState),
                            ),
                            const SizedBox(width: 10.0),
                            MouseRegion(
                              cursor: _isHoveringAnimeInfo 
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                              onEnter: (_) => setState(() => _isHoveringAnimeInfo = true),
                              onExit: (_) => setState(() => _isHoveringAnimeInfo = false),
                              child: AnimeInfoWidget(videoState: videoState),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (globals.isPhone && videoState.isFullscreen)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 60,
                      child: GestureDetector(
                        onHorizontalDragStart: _handleSideSwipeDragStart,
                        onHorizontalDragUpdate: _handleSideSwipeDragUpdate,
                        onHorizontalDragEnd: _handleSideSwipeDragEnd,
                        behavior: HitTestBehavior.translucent,
                        dragStartBehavior: DragStartBehavior.down,
                        child: Container(
                        ),
                      ),
                    ),
                ],
                if (videoState.hasVideo)
                  const VideoControlsOverlay(),
              ],
            ),
          ),
        ),
        );
      },
    );
  }
} 