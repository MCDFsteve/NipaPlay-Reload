// ThemeModePage.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';

class ThemeModePage extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const ThemeModePage({super.key, required this.themeNotifier});

  @override
  // ignore: library_private_types_in_public_api
  _ThemeModePageState createState() => _ThemeModePageState();
}

class _ThemeModePageState extends State<ThemeModePage> {
  final GlobalKey _dropdownKey = GlobalKey();
  final GlobalKey _blurDropdownKey = GlobalKey();
  final GlobalKey _backgroundImageDropdownKey = GlobalKey();
  final GlobalKey _animationDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 不再需要在 initState 中加载背景图像模式，因为已经在 main.dart 中加载了
  }

  Future<void> _pickCustomBackground(BuildContext context) async {
    if (Platform.isAndroid) { // 只在 Android 上使用 permission_handler
      PermissionStatus status = await Permission.photos.request();
      if (!mounted) return;

      if (status.isGranted) {
        await _pickImageFromGalleryForBackground(context); // 传递 context
      } else {
        // Android 权限被拒绝
        print("Android photos permission denied for custom background. Status: $status");
        if (status.isPermanentlyDenied) {
          BlurDialog.show(
            context: context,
            title: '权限已被永久拒绝',
            content: '相册权限已被永久拒绝。请前往系统设置开启。',
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('去设置'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        } else {
          BlurSnackBar.show(context, '需要相册权限才能选择背景图片');
        }
      }
    } else if (Platform.isIOS) { // 在 iOS 上直接尝试选择
      print("iOS: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    } else { // 其他平台 (如果支持，也直接尝试)
      print("Other platform: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    }
  }

  // 提取选择图片并设置为背景的逻辑
  Future<void> _pickImageFromGalleryForBackground(BuildContext context) async { // 接收 context
    try {
      // 在异步操作前检查 mounted 状态
      if (!mounted) return;

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      // 异步操作后再次检查 mounted 状态
      if (!mounted) return;

      if (image != null) {
        final file = File(image.path);
        
        // 获取原始文件的扩展名
        String extension = path.extension(image.path); 
        if (extension.isEmpty) { 
          extension = '.jpg'; 
        }

        // 生成基于时间戳的唯一文件名
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String uniqueFileName = 'custom_background_$timestamp$extension'; 

        final appDir = await StorageService.getAppStorageDirectory();
        final String backgroundDirectoryPath = path.join(appDir.path, 'backgrounds');
        final targetPath = path.join(backgroundDirectoryPath, uniqueFileName); 
        
        final targetDirectory = Directory(backgroundDirectoryPath);
        if (!await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }
        
        // 复制文件
        await file.copy(targetPath); 
        
        // !! 获取旧路径，用于后续可能的比较和清理，如果 ThemeNotifier 先更新，这里需要注意
        // final oldPath = Provider.of<ThemeNotifier>(context, listen: false).customBackgroundPath;

        // 更新 ThemeNotifier 中的路径
        Provider.of<ThemeNotifier>(context, listen: false).customBackgroundPath = targetPath;
        
        // 清理旧的自定义背景图片
        final dir = Directory(backgroundDirectoryPath);
        if (await dir.exists()) {
          final List<FileSystemEntity> entities = await dir.list().toList();
          for (FileSystemEntity entity in entities) {
            if (entity is File && entity.path != targetPath && path.basename(entity.path).startsWith('custom_background_')) {
              try {
                await entity.delete();
                print('Deleted old background image: ${entity.path}');
              } catch (e) {
                print('Error deleting old background image ${entity.path}: $e');
              }
            }
          }
        }
        // PaintingBinding.instance.imageCache.evict(FileImage(imageFileToClear)); // 这行不再需要，移除
        // print("Evicted image from cache: $targetPath"); // 这行关联代码也移除
        
      } else {
        print("Custom background image picking cancelled or failed (possibly due to permissions).");
      }
    } catch (e) {
      // 异步操作后再次检查 mounted 状态
      if (!mounted) return;
      print("Error picking custom background image: $e");
      BlurSnackBar.show(context, '选择背景图片时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取外观设置提供者
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final settingsProvider = context.watch<SettingsProvider>();
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(0),
        child: ListView(
          children: [
            SettingsItem.dropdown(
              title: "主题模式",
              subtitle: "选择应用界面的颜色主题",
              icon: Ionicons.moon_outline,
              items: [
                DropdownMenuItemData(
                  title: "日间模式",
                  value: ThemeMode.light,
                  isSelected: widget.themeNotifier.themeMode == ThemeMode.light,
                ),
                DropdownMenuItemData(
                  title: "夜间模式",
                  value: ThemeMode.dark,
                  isSelected: widget.themeNotifier.themeMode == ThemeMode.dark,
                ),
                DropdownMenuItemData(
                  title: "跟随系统",
                  value: ThemeMode.system,
                  isSelected: widget.themeNotifier.themeMode == ThemeMode.system,
                ),
              ],
              onChanged: (mode) {
                setState(() {
                  widget.themeNotifier.themeMode = mode;
                  _saveThemeMode(mode);
                });
              },
              dropdownKey: _dropdownKey,
            ),
            const Divider(color: Colors.white12, height: 1),
            SettingsItem.dropdown(
              title: "背景毛玻璃效果",
              subtitle: "调整界面元素的模糊强度",
              icon: Ionicons.water_outline,
              items: [
                DropdownMenuItemData(
                  title: "无",
                  value: 0,
                  isSelected: settingsProvider.blurPower == 0,
                ),
                DropdownMenuItemData(
                  title: "轻微",
                  value: 5,
                  isSelected: settingsProvider.blurPower == 5,
                ),
                DropdownMenuItemData(
                  title: "中等",
                  value: 15,
                  isSelected: settingsProvider.blurPower == 15,
                ),
                DropdownMenuItemData(
                  title: "高",
                  value: 25,
                  isSelected: settingsProvider.blurPower == 25,
                ),
                DropdownMenuItemData(
                  title: "超级",
                  value: 50,
                  isSelected: settingsProvider.blurPower == 50,
                ),
                DropdownMenuItemData(
                  title: "梦幻",
                  value: 100,
                  isSelected: settingsProvider.blurPower == 100,
                ),
              ],
              onChanged: (blur) {
                context
                    .read<SettingsProvider>()
                    .setBlurPower(blur.toDouble());
              },
              dropdownKey: _blurDropdownKey,
            ),
            const Divider(color: Colors.white12, height: 1),
            SettingsItem.toggle(
              title: "控件毛玻璃效果",
              subtitle: "关闭后可提升性能，但会失去部分UI透明感",
              icon: Ionicons.radio_button_on_outline,
              value: appearanceSettings.enableWidgetBlurEffect,
              onChanged: (value) {
                appearanceSettings.setEnableWidgetBlurEffect(value);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            SettingsItem.dropdown(
              title: "背景图像",
              subtitle: "设置应用主界面的背景图片",
              icon: Ionicons.image_outline,
              items: [
                DropdownMenuItemData(
                  title: "看板娘",
                  value: "看板娘",
                  isSelected: widget.themeNotifier.backgroundImageMode == "看板娘",
                ),
                DropdownMenuItemData(
                  title: "看板娘2",
                  value: "看板娘2",
                  isSelected: widget.themeNotifier.backgroundImageMode == "看板娘2",
                ),
                DropdownMenuItemData(
                  title: "关闭",
                  value: "关闭",
                  isSelected: widget.themeNotifier.backgroundImageMode == "关闭",
                ),
                DropdownMenuItemData(
                  title: "自定义",
                  value: "自定义",
                  isSelected: widget.themeNotifier.backgroundImageMode == "自定义",
                ),
              ],
              onChanged: (mode) async {
                setState(() {
                  widget.themeNotifier.backgroundImageMode = mode;
                  _saveBackgroundImageMode(mode);
                });
                if (mode == "自定义") {
                  await _pickCustomBackground(context);
                }
              },
              dropdownKey: _backgroundImageDropdownKey,
            ),
            const Divider(color: Colors.white12, height: 1),
            SettingsItem.toggle(
              title: "页面滑动动画",
              subtitle: "关闭可提升在低性能设备上的流畅度",
              icon: Ionicons.swap_horizontal_outline,
              value: appearanceSettings.enablePageAnimation,
              onChanged: (value) {
                appearanceSettings.setEnablePageAnimation(value);
                BlurSnackBar.show(
                  context, 
                  value ? '已启用页面滑动动画' : '已关闭页面滑动动画'
                );
              },
            ),
            const Divider(color: Colors.white12, height: 1),
          ],
        ),
      ),
    );
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      default:
        modeString = 'system';
    }
    await SettingsStorage.saveString('themeMode', modeString);
  }

  Future<void> _saveBackgroundImageMode(String mode) async {
    await SettingsStorage.saveString('backgroundImageMode', mode);
  }
}
