import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'theme_color_utils.dart';

class DanmakuOffsetMenu extends StatefulWidget {
  final VoidCallback onClose;

  const DanmakuOffsetMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<DanmakuOffsetMenu> createState() => _DanmakuOffsetMenuState();
}

class _DanmakuOffsetMenuState extends State<DanmakuOffsetMenu> {
  // 预设的偏移选项（秒）
  static const List<double> _offsetOptions = [-10, -5, -2, -1, -0.5, 0, 0.5, 1, 2, 5, 10];

  String _formatOffset(double offset) {
    if (offset == 0) return '无偏移';
    if (offset > 0) return '+${offset}秒';
    return '${offset}秒';
  }

  Widget _buildOffsetButton(double offset, double currentOffset) {
    final bool isSelected = (offset - currentOffset).abs() < 0.01;
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final borderColor = ThemeColorUtils.borderColor(
      context,
      darkOpacity: isSelected ? 0.5 : 0.2,
      lightOpacity: isSelected ? 0.35 : 0.15,
    );
    final backgroundColor = ThemeColorUtils.overlayColor(
      context,
      darkOpacity: isSelected ? 0.15 : 0.05,
      lightOpacity: isSelected ? 0.1 : 0.03,
    );
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: isSelected
            ? ThemeColorUtils.overlayColor(
                context,
                darkOpacity: 0.2,
                lightOpacity: 0.12,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Provider.of<SettingsProvider>(context, listen: false)
                .setDanmakuTimeOffset(offset);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Text(
              _formatOffset(offset),
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: primaryColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final primaryTextColor = ThemeColorUtils.primaryForeground(context);
        final secondaryTextColor = ThemeColorUtils.secondaryForeground(context);
        final subtleTextColor = ThemeColorUtils.subtleForeground(context);
        final surfaceColor = ThemeColorUtils.overlayColor(
          context,
          darkOpacity: 0.1,
          lightOpacity: 0.06,
        );
        final borderColor = ThemeColorUtils.borderColor(
          context,
          darkOpacity: 0.3,
          lightOpacity: 0.18,
        );
        return BaseSettingsMenu(
          title: '弹幕偏移',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 当前偏移状态
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前偏移',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: borderColor,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            settingsProvider.danmakuTimeOffset > 0
                                ? Icons.fast_forward
                                : settingsProvider.danmakuTimeOffset < 0
                                    ? Icons.fast_rewind
                                    : Icons.sync,
                            color: primaryTextColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatOffset(settingsProvider.danmakuTimeOffset),
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SettingsHintText(
                      settingsProvider.danmakuTimeOffset > 0
                          ? '弹幕将提前${settingsProvider.danmakuTimeOffset}秒显示'
                          : settingsProvider.danmakuTimeOffset < 0
                              ? '弹幕将延后${(-settingsProvider.danmakuTimeOffset)}秒显示'
                              : '弹幕按原始时间显示',
                    ),
                  ],
                ),
              ),
              
              // 快速偏移选项
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '快速设置',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 后退选项
                    Text(
                      '弹幕后退',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      children: _offsetOptions
                          .where((offset) => offset < 0)
                          .map((offset) => _buildOffsetButton(
                              offset, settingsProvider.danmakuTimeOffset))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    
                    // 无偏移
                    Text(
                      '默认',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildOffsetButton(0, settingsProvider.danmakuTimeOffset),
                    const SizedBox(height: 8),
                    
                    // 前进选项
                    Text(
                      '弹幕前进',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      children: _offsetOptions
                          .where((offset) => offset > 0)
                          .map((offset) => _buildOffsetButton(
                              offset, settingsProvider.danmakuTimeOffset))
                          .toList(),
                    ),
                  ],
                ),
              ),
              
              // 说明文字
              Container(
                padding: const EdgeInsets.all(16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsHintText(
                      '弹幕偏移功能用于调整弹幕与视频的同步：',
                    ),
                    SizedBox(height: 4),
                    SettingsHintText(
                      '• 前进(+)：弹幕提前显示，适用于弹幕慢于视频的情况',
                    ),
                    SettingsHintText(
                      '• 后退(-)：弹幕延后显示，适用于弹幕快于视频的情况',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
