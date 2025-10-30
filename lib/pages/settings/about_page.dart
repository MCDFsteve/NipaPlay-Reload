// about_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '加载中...';
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // 静默检查更新，不显示加载状态
    _checkForUpdates();
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

  Future<void> _checkForUpdates() async {
    // 静默检查更新，不显示加载状态
    debugPrint('开始检查更新...');
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      debugPrint('检查更新完成: 当前版本=${updateInfo.currentVersion}, 最新版本=${updateInfo.latestVersion}, 有更新=${updateInfo.hasUpdate}');
      if (updateInfo.hasUpdate) {
        debugPrint('发现新版本: ${updateInfo.latestVersion}, 下载链接: ${updateInfo.releaseUrl}');
      }
      if (updateInfo.error != null) {
        debugPrint('检查更新时出现错误: ${updateInfo.error}');
      }
      if (mounted) {
        setState(() {
          _updateInfo = updateInfo;
        });
      }
    } catch (e) {
      // 静默处理错误，不影响用户体验
      debugPrint('检查更新失败: $e');
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Log or show a snackbar if url can't be launched
      //debugPrint('Could not launch $urlString');
      if (mounted) {
        BlurSnackBar.show(context, '无法打开链接: $urlString');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nipaplayColors;
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final accent = colors.accent;
    final errorColor = Theme.of(context).colorScheme.error;
    final highlightShadow = errorColor.withOpacity(context.isDarkMode ? 0.35 : 0.18);
    final linkColor = accent;
    final linkUnderline = accent.withOpacity(context.isDarkMode ? 0.6 : 0.4);
    final iconMuted = colors.iconSecondary.withOpacity(context.isDarkMode ? 0.85 : 0.7);
    final textTheme = Theme.of(context).textTheme.apply(
          bodyColor: textPrimary,
          displayColor: textPrimary,
        );

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      child: ConstrainedBox( // Limit max width for better readability on wide screens
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // Change to start
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40), // Add some space at the top
            Image.asset(
              'assets/logo.png', // Ensure this path is correct
              height: 120, // Adjust size as needed
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Ionicons.image_outline,
                  size: 100,
                  color: colors.iconSecondary,
                );
              },
            ),
            const SizedBox(height: 24),
            // 版本信息，点击跳转到releases页面（如果有更新）
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _updateInfo?.hasUpdate == true 
                        ? () => _launchURL(_updateInfo!.releaseUrl) 
                        : null,
                    child: MouseRegion(
                      cursor: _updateInfo?.hasUpdate == true 
                          ? SystemMouseCursors.click 
                          : SystemMouseCursors.basic,
                      child: Text(
                        'NipaPlay Reload 当前版本: $_version',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // NEW 标识 - 独立定位
                  if (_updateInfo?.hasUpdate == true)
                    Positioned(
                      top: -8,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: errorColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: highlightShadow,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'NEW',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildInfoCard(
              context: context,
              children: [
                _buildRichText(
                  context,
                  [
                    TextSpan(text: 'NipaPlay,名字来自《寒蝉鸣泣之时》里古手梨花 (ふるて りか) 的标志性口头禅 "', style: TextStyle(color: textSecondary)),
                    TextSpan(
                      text: 'にぱ〜☆',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    TextSpan(
                      text: '" \n为解决我 macOS和Linux 、IOS看番不便。我创造了 NipaPlay。',
                      style: TextStyle(color: textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildInfoCard(
              context: context,
              title: '致谢',
              children: [
                 _buildRichText(
                  context,
                  [
                    TextSpan(
                      text: '感谢弹弹play (DandanPlay) 和开发者 ',
                      style: TextStyle(color: textSecondary),
                    ),
                    TextSpan(
                      text: 'Kaedei',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                    TextSpan(
                      text: '！提供了 NipaPlay 相关api接口和开发帮助。',
                      style: TextStyle(color: textSecondary),
                    ),
                  ]
                ),
                _buildRichText(
                  context,
                  [
                    TextSpan(
                      text: '感谢开发者 ',
                      style: TextStyle(color: textSecondary),
                    ),
                    TextSpan(
                      text: 'Sakiko',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                    TextSpan(
                      text: '！提供了Emby和Jellyfin的媒体库支持。',
                      style: TextStyle(color: textSecondary),
                    ),
                  ]
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            _buildInfoCard(
              context: context,
              title: '开源与社区',
              children: [
                _buildRichText(
                  context,
                  [
                    TextSpan(
                      text: '欢迎贡献代码，或者将其发布到各个软件仓库。(不会 Dart 也没关系，用 Cursor 这种ai编程也是可以的。)',
                      style: TextStyle(color: textSecondary),
                    ),
                  ]
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _launchURL('https://www.github.com/MCDFsteve/NipaPlay-Reload'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.logo_github, color: iconMuted, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MCDFsteve/NipaPlay-Reload',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: linkColor,
                            decoration: TextDecoration.underline,
                            decorationColor: linkUnderline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _launchURL('https://qm.qq.com/q/w9j09QJn4Q'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.chatbubbles_outline, color: iconMuted, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'QQ群: 961207150',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: linkColor,
                            decoration: TextDecoration.underline,
                            decorationColor: linkUnderline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _launchURL('https://nipaplay.aimes-soft.com'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.globe_outline, color: iconMuted, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'NipaPlay 官方网站',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: linkColor,
                            decoration: TextDecoration.underline,
                            decorationColor: linkUnderline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildInfoCard(
              context: context,
              title: '赞助支持',
              children: [
                _buildRichText(
                  context,
                  [
                    TextSpan(
                      text: '如果你喜欢 NipaPlay 并且希望支持项目的持续开发，欢迎通过爱发电进行赞助。赞助者的名字将会出现在项目的 README 文件和每次软件更新后的关于页面名单中。',
                      style: TextStyle(color: textSecondary),
                    ),
                  ]
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _launchURL('https://afdian.com/a/irigas'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.heart, color: accent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '爱发电赞助页面',
                          style: TextStyle(
                            color: accent,
                            decoration: TextDecoration.underline,
                            decorationColor: accent.withOpacity(context.isDarkMode ? 0.6 : 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({required BuildContext context, String? title, required List<Widget> children}) {
    final colors = context.nipaplayColors;
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _buildRichText(BuildContext context, List<InlineSpan> spans) {
    final colors = context.nipaplayColors;
    return RichText(
      textAlign: TextAlign.start, // Or TextAlign.justify if preferred
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: colors.textSecondary,
          height: 1.6, // Improved line spacing
        ), // Default text style for spans
        children: spans,
      ),
    );
  }
}
