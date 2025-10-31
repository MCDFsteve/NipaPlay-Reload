import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class UIThemePage extends StatefulWidget {
  const UIThemePage({super.key});

  @override
  State<UIThemePage> createState() => _UIThemePageState();
}

class _UIThemePageState extends State<UIThemePage> {
  final GlobalKey _themeDropdownKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, child) {
        final theme = Theme.of(context);
        final Color primaryText = ThemeColorUtils.primaryForeground(context);
        final Color secondaryText = ThemeColorUtils.secondaryForeground(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  '控件主题',
                  locale: const Locale("zh-Hans","zh"),
                  style: theme.textTheme.headlineSmall?.copyWith(
                        color: primaryText,
                        fontWeight: FontWeight.bold,
                      ) ??
                      TextStyle(
                        color: primaryText,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '选择应用的控件主题风格',
                  locale: const Locale("zh-Hans","zh"),
                  style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryText,
                      ) ??
                      TextStyle(
                        color: secondaryText,
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 32),

                // 主题选择
                _buildThemeSelector(uiThemeProvider, primaryText: primaryText),
                
                const SizedBox(height: 24),
                
                // 主题预览区域
                _buildThemePreview(
                  uiThemeProvider,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeSelector(UIThemeProvider uiThemeProvider,
      {required Color primaryText}) {
    final theme = Theme.of(context);
    final availableThemes = UIThemeType.values.where((theme) {
      if (theme == UIThemeType.cupertino) {
        return globals.isPhone;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    if (!availableThemes.contains(uiThemeProvider.currentTheme)) {
      availableThemes.add(uiThemeProvider.currentTheme);
    }

    return Row(
      children: [
        Text(
          '主题风格',
          locale: const Locale("zh-Hans","zh"),
          style: theme.textTheme.titleMedium?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w500,
              ) ??
              TextStyle(
                color: primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: BlurDropdown<UIThemeType>(
            dropdownKey: _themeDropdownKey,
            items: availableThemes.map((theme) {
              return DropdownMenuItemData<UIThemeType>(
                title: uiThemeProvider.getThemeName(theme),
                value: theme,
                isSelected: uiThemeProvider.currentTheme == theme,
              );
            }).toList(),
            onItemSelected: (UIThemeType newTheme) {
              if (uiThemeProvider.currentTheme != newTheme) {
                _showThemeChangeConfirmDialog(newTheme, uiThemeProvider);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThemePreview(
    UIThemeProvider uiThemeProvider, {
    required Color primaryText,
    required Color secondaryText,
  }) {
    final theme = Theme.of(context);

    return SettingsCard(
      padding: const EdgeInsets.all(20),
      backgroundOpacity: 0.25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前主题预览',
            locale: const Locale("zh-Hans","zh"),
            style: theme.textTheme.titleMedium?.copyWith(
                  color: primaryText,
                  fontWeight: FontWeight.w500,
                ) ??
                TextStyle(
                  color: primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 16),
          _buildThemeDescription(
            uiThemeProvider.currentTheme,
            headingColor: primaryText,
            secondaryText: secondaryText,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeDescription(
    UIThemeType theme, {
    required Color headingColor,
    required Color secondaryText,
  }) {
    final textTheme = Theme.of(context).textTheme;

    final TextStyle headingStyle = textTheme.titleMedium?.copyWith(
          color: headingColor,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ) ??
        TextStyle(
          color: headingColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        );

    final TextStyle bodyStyle = textTheme.bodyMedium?.copyWith(
          color: secondaryText,
          fontSize: 14,
          height: 1.5,
        ) ??
        TextStyle(
          color: secondaryText,
          fontSize: 14,
          height: 1.5,
        );

    String title;
    String description;

    switch (theme) {
      case UIThemeType.nipaplay:
        title = 'NipaPlay 主题';
        description = '• 磨砂玻璃效果\n• 渐变背景\n• 圆角设计\n• 适合多媒体应用';
        break;
      case UIThemeType.fluentUI:
        title = 'Fluent UI 主题';
        description = '• Microsoft 设计语言\n• 亚克力材质\n• 现代化界面\n• 统一的交互体验';
        break;
      case UIThemeType.cupertino:
        title = 'Cupertino 主题';
        description = '• 贴近原生 iOS 体验\n• 自适应平台控件\n• 支持浅色/深色模式\n• 底部导航布局';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          locale: const Locale("zh-Hans","zh"),
          style: headingStyle,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          locale: const Locale("zh-Hans","zh"),
          style: bodyStyle,
        ),
      ],
    );
  }

  /// 显示主题切换确认弹窗
  void _showThemeChangeConfirmDialog(UIThemeType newTheme, UIThemeProvider provider) {
    BlurDialog.show(
      context: context,
      title: '主题切换提示',
      content: '切换到 ${provider.getThemeName(newTheme)} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？',
      barrierDismissible: true,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () async {
            // 先保存主题设置
            await provider.setTheme(newTheme);
            Navigator.of(context).pop();
            // 退出应用
            _exitApplication();
          },
          child: const Text('重启应用', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  /// 退出应用
  void _exitApplication() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // 移动平台
      exit(0);
    } else if (!kIsWeb) {
      // 桌面平台
      windowManager.close();
    } else {
      // Web 平台提示用户手动刷新
      BlurSnackBar.show(context, '请手动刷新页面以应用新主题');
    }
  }


}
