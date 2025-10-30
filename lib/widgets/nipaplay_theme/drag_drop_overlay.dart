import 'package:flutter/material.dart';

import 'theme_color_utils.dart';

class DragDropOverlay extends StatelessWidget {
  const DragDropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ThemeColorUtils.primaryForeground(context);
    final overlayColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black.withOpacity(0.5)
        : Colors.black.withOpacity(0.4);
    return Container(
      color: overlayColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              color: primaryTextColor,
              size: 80.0,
            ),
            const SizedBox(height: 20.0),
            Text(
              '拖放至页面内播放视频',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: primaryTextColor,
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none, // 移除MaterialApp之外的文本下划线
              ),
            ),
          ],
        ),
      ),
    );
  }
}
