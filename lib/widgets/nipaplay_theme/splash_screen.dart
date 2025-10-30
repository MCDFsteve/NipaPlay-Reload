import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'theme_color_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _version = '加载中...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _version = '获取失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final backgroundColor = isDarkMode
        ? const Color.fromARGB(255, 30, 30, 30)
        : theme.colorScheme.background;
    final primaryForeground = ThemeColorUtils.primaryForeground(context);
    final textColor = isDarkMode
        ? primaryForeground.withOpacity(0.6)
        : primaryForeground.withOpacity(0.3);

    return Container(
      color: backgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo512.png',
              width: 128,
              height: 128,
              color: isDarkMode ? primaryForeground.withOpacity(0.8) : null,
              colorBlendMode: isDarkMode ? BlendMode.modulate : null,
            ),
            const SizedBox(height: 24),
            Image.asset(
              'assets/logo.png',
              width: 200,
              color: isDarkMode ? primaryForeground.withOpacity(0.8) : null,
              colorBlendMode: isDarkMode ? BlendMode.modulate : null,
            ),
            const SizedBox(height: 16),
            Text(
              'v$_version',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
