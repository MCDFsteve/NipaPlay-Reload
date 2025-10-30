import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
// import 'package:nipaplay/utils/globals.dart' as globals; // globals is not used in this snippet

class AnimeInfoWidget extends StatefulWidget {
  final VideoPlayerState videoState;

  const AnimeInfoWidget({
    super.key,
    required this.videoState,
  });

  @override
  State<AnimeInfoWidget> createState() => _AnimeInfoWidgetState();
}

class _AnimeInfoWidgetState extends State<AnimeInfoWidget> {
  bool _isEpisodeHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!(widget.videoState.hasVideo &&
        widget.videoState.animeTitle != null &&
        widget.videoState.episodeTitle != null)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;
    final primaryTextColor = isDarkTheme ? Colors.white : Colors.black;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final gradientStart = isDarkTheme
        ? const Color(0xFF808080).withOpacity(0.3)
        : Colors.black.withOpacity(0.15);
    final gradientEnd = isDarkTheme
        ? const Color(0xFF808080).withOpacity(0.3)
        : Colors.black.withOpacity(0.1);
    final borderGradientColor = isDarkTheme
        ? const Color(0xFFFFFFFF).withOpacity(0.5)
        : Colors.black.withOpacity(0.3);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: widget.videoState.showControls ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        offset: Offset(widget.videoState.showControls ? 0 : -0.1, 0),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
          ),
          child: IntrinsicWidth(
            child: MouseRegion(
              onEnter: (_) {
                widget.videoState.setControlsHovered(true);
              },
              onExit: (_) {
                widget.videoState.setControlsHovered(false);
              },
              child: GlassmorphicContainer(
                width: double.infinity,
                height: 40,
                borderRadius: 24,
                blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
                alignment: Alignment.center,
                border: 1,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    gradientStart,
                    gradientEnd,
                  ],
                ),
                borderGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    borderGradientColor,
                    borderGradientColor,
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          widget.videoState.animeTitle!,
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: MouseRegion(
                          onEnter: (_) {
                            setState(() => _isEpisodeHovered = true);
                          },
                          onExit: (_) {
                            setState(() => _isEpisodeHovered = false);
                          },
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: _isEpisodeHovered
                                  ? primaryTextColor
                                  : secondaryTextColor,
                              fontSize: 14,
                            ),
                            child: Text(
                              widget.videoState.episodeTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 
