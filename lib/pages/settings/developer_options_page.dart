import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/platform_utils.dart' as platform;
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/pages/settings/debug_log_viewer_page.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/utils/linux_storage_migration.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';
// 证书相关的主机快捷信任按钮应用户要求移除，仅保留全局开关

/// 开发者选项设置页面
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        return ListView(
          children: [
            // 危险：全局允许无效/自签名证书（仅 IO 平台生效）
            SettingsItem.toggle(
              title: '允许自签名证书（全局）',
              subtitle: '仅桌面/Android/iOS生效，Web无效。极度危险，仅在内网或调试时开启。',
              icon: Ionicons.alert_circle_outline,
              value: devOptions.allowInvalidCertsGlobal,
              onChanged: (bool value) async {
                await devOptions.setAllowInvalidCertsGlobal(value);
                // 立即反馈
                final status = value ? '已开启（不安全）' : '已关闭（默认安全）';
                BlurSnackBar.show(context, '自签名证书全局开关：$status');
              },
            ),

            Divider(
              color: ThemeColorUtils.borderColor(
                context,
                darkOpacity: 0.16,
                lightOpacity: 0.08,
              ),
              height: 1,
            ),
            // 显示系统资源监控开关（所有平台可用）
            SettingsItem.toggle(
              title: '显示系统资源监控',
              subtitle: '在界面右上角显示CPU、内存和帧率信息',
              icon: Ionicons.analytics_outline,
              value: devOptions.showSystemResources,
              onChanged: (bool value) {
                devOptions.setShowSystemResources(value);
              },
            ),
            
            Divider(
              color: ThemeColorUtils.borderColor(
                context,
                darkOpacity: 0.16,
                lightOpacity: 0.08,
              ),
              height: 1,
            ),
            
            // 调试日志收集开关
            SettingsItem.toggle(
              title: '调试日志收集',
              subtitle: '收集应用的所有打印输出，用于调试和问题诊断',
              icon: Ionicons.document_text_outline,
              value: devOptions.enableDebugLogCollection,
              onChanged: (bool value) async {
                await devOptions.setEnableDebugLogCollection(value);
                
                // 根据设置控制日志服务
                final logService = DebugLogService();
                if (value) {
                  logService.startCollecting();
                } else {
                  logService.stopCollecting();
                }
              },
            ),
            
            Divider(
              color: ThemeColorUtils.borderColor(
                context,
                darkOpacity: 0.16,
                lightOpacity: 0.08,
              ),
              height: 1,
            ),
            
            // 终端输出查看器
            SettingsItem.button(
              title: '终端输出',
              subtitle: '查看应用的所有打印输出，支持搜索、过滤和复制',
              icon: Ionicons.terminal_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () {
                _openDebugLogViewer(context);
              },
            ),
            
            Divider(
              color: ThemeColorUtils.borderColor(
                context,
                darkOpacity: 0.16,
                lightOpacity: 0.08,
              ),
              height: 1,
            ),
            
            // Linux存储迁移选项（仅Linux平台显示，Web环境下不显示）
            if (!kIsWeb && platform.Platform.isLinux) ...[
              // 检查迁移状态
              ListTile(
                title: const Text(
                  '检查Linux存储迁移状态',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '查看Linux平台数据目录迁移状态',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Ionicons.information_circle_outline, color: Colors.white),
                onTap: () => _checkLinuxMigrationStatus(context),
              ),
              
              const Divider(color: Colors.white12, height: 1),
              
              // 手动触发迁移
              ListTile(
                title: const Text(
                  '手动触发存储迁移',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '强制重新执行数据目录迁移（仅用于测试）',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Ionicons.refresh_outline, color: Colors.orange),
                onTap: () => _manualTriggerMigration(context),
              ),
              
              const Divider(color: Colors.white12, height: 1),
              
              // 紧急恢复个人文件
              ListTile(
                title: const Text(
                  '🚨 紧急恢复个人文件',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '将误迁移的个人文件恢复到Documents目录',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Ionicons.medical_outline, color: Colors.red),
                onTap: () => _emergencyRestorePersonalFiles(context),
              ),
              
              const Divider(color: Colors.white12, height: 1),
              
              // 显示存储目录信息
              ListTile(
                title: const Text(
                  '显示存储目录信息',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '查看当前使用的数据和缓存目录路径',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Ionicons.folder_outline, color: Colors.white),
                onTap: () => _showStorageDirectoryInfo(context),
              ),
              
              const Divider(color: Colors.white12, height: 1),
            ],
            
            // 这里可以添加更多开发者选项
          ],
        );
      },
    );
  }

  void _openDebugLogViewer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭终端输出',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GlassmorphicContainer(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.85,
            borderRadius: 12,
            blur: Provider.of<AppearanceSettingsProvider>(context).enableWidgetBlurEffect ? 25 : 0,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.5),
                Colors.white.withOpacity(0.2),
              ],
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '终端输出',
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 24,
                        ),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                // 日志查看器内容
                const Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: DebugLogViewerPage(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  // 检查Linux存储迁移状态
  Future<void> _checkLinuxMigrationStatus(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;
    
    try {
      final needsMigration = await LinuxStorageMigration.needsMigration();
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();
      
      if (!context.mounted) return;
      
      BlurDialog.show<void>(
        context: context,
        title: "Linux存储迁移状态",
        content: """
当前状态: ${needsMigration ? '需要迁移' : '迁移已完成'}

XDG数据目录: $dataDir
XDG缓存目录: $cacheDir

遵循XDG Base Directory规范，提供更好的Linux用户体验。
        """.trim(),
        actions: <Widget>[
          TextButton(
            child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      
      BlurSnackBar.show(context, '检查迁移状态失败: $e');
    }
  }

  // 手动触发存储迁移
  Future<void> _manualTriggerMigration(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;
    
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: "确认迁移",
      content: "这将重新执行数据目录迁移过程。\n\n注意：这是一个测试功能，在正常情况下不应该使用。",
      actions: <Widget>[
        TextButton(
          child: const Text("取消", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: const Text("确认", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.orange)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    
    if (confirm == true && context.mounted) {
      BlurSnackBar.show(context, '开始执行迁移...');
      
      try {
        // 重置迁移状态
        await LinuxStorageMigration.resetMigrationStatus();
        
        // 执行迁移
        final result = await LinuxStorageMigration.performMigration();
        
        if (!context.mounted) return;
        
        if (result.success) {
          BlurDialog.show<void>(
            context: context,
            title: "迁移成功",
            content: """
${result.message}

迁移详情:
- 总项目数: ${result.totalItems}
- 成功项目: ${result.migratedItems}
- 失败项目: ${result.failedItems}
            """.trim(),
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        } else {
          BlurDialog.show<void>(
            context: context,
            title: "迁移失败",
            content: """
${result.message}

错误信息:
${result.errors.join('\n')}
            """.trim(),
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.orange)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        BlurSnackBar.show(context, '迁移过程出错: $e');
      }
    }
  }

  // 显示存储目录信息
  Future<void> _showStorageDirectoryInfo(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;
    
    try {
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();
      
      // 获取环境变量信息
      final xdgDataHome = platform.Platform.environment['XDG_DATA_HOME'] ?? '未设置';
      final xdgCacheHome = platform.Platform.environment['XDG_CACHE_HOME'] ?? '未设置';
      final homeDir = platform.Platform.environment['HOME'] ?? '未知';
      
      if (!context.mounted) return;
      
      BlurDialog.show<void>(
        context: context,
        title: "Linux存储目录信息",
        content: """
=== 当前使用的目录 ===
数据目录: $dataDir
缓存目录: $cacheDir

=== 环境变量 ===
HOME: $homeDir
XDG_DATA_HOME: $xdgDataHome
XDG_CACHE_HOME: $xdgCacheHome

=== 说明 ===
• 数据目录用于存储用户数据（数据库、设置等）
• 缓存目录用于存储临时文件和缓存
• 遵循XDG Base Directory规范
• 提供与其他Linux应用一致的用户体验
        """.trim(),
        actions: <Widget>[
          TextButton(
            child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      BlurSnackBar.show(context, '获取目录信息失败: $e');
    }
  }
  
  // 紧急恢复个人文件
  Future<void> _emergencyRestorePersonalFiles(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;
    
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: "🚨 紧急恢复个人文件",
      content: """
这个功能将把误迁移到 ~/.local/share/NipaPlay 的个人文件恢复到 ~/Documents 目录。

⚠️ 注意事项：
• 只恢复非应用相关的文件
• 应用数据（如数据库、缓存等）会保留在新位置
• 这是一个紧急修复功能

是否继续？
      """.trim(),
      actions: <Widget>[
        TextButton(
          child: const Text("取消", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: const Text("确认恢复", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    
    if (confirm == true && context.mounted) {
      BlurSnackBar.show(context, '开始恢复个人文件...');
      
      try {
        final result = await LinuxStorageMigration.emergencyRestorePersonalFiles();
        
        if (!context.mounted) return;
        
        if (result.success) {
          BlurDialog.show<void>(
            context: context,
            title: "恢复成功",
            content: """
${result.message}

恢复详情:
- 总文件数: ${result.totalItems}
- 成功恢复: ${result.migratedItems}
- 失败项目: ${result.failedItems}

您的个人文件已恢复到 ~/Documents 目录。
            """.trim(),
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        } else {
          BlurDialog.show<void>(
            context: context,
            title: "恢复失败",
            content: """
${result.message}

错误信息:
${result.errors.join('\n')}
            """.trim(),
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.orange)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        BlurSnackBar.show(context, '恢复过程出错: $e');
      }
    }
  }
} 
