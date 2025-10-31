// remote_media_library_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_library_settings_section.dart';

class RemoteMediaLibraryPage extends StatefulWidget {
  const RemoteMediaLibraryPage({super.key});

  @override
  State<RemoteMediaLibraryPage> createState() => _RemoteMediaLibraryPageState();
}

class _RemoteMediaLibraryPageState extends State<RemoteMediaLibraryPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<JellyfinProvider, EmbyProvider>(
      builder: (context, jellyfinProvider, embyProvider, child) {
        // 检查 Provider 是否已初始化
        if (!jellyfinProvider.isInitialized && !embyProvider.isInitialized) {
          final colorScheme = Theme.of(context).colorScheme;
          final secondaryColor = ThemeColorUtils.secondaryForeground(context);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  '正在初始化远程媒体库服务...',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          );
        }
        
        // 检查是否有严重错误
        final hasJellyfinError = jellyfinProvider.hasError && 
                                 jellyfinProvider.errorMessage != null &&
                                 !jellyfinProvider.isConnected;
        final hasEmbyError = embyProvider.hasError && 
                            embyProvider.errorMessage != null &&
                            !embyProvider.isConnected;
        
        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // 显示错误信息（如果有的话）
            if (hasJellyfinError || hasEmbyError) ...[
              _buildErrorCard(jellyfinProvider, embyProvider),
              const SizedBox(height: 20),
            ],
            
            // Jellyfin服务器配置部分
            _buildJellyfinSection(jellyfinProvider),

            const SizedBox(height: 20),

            // Emby服务器配置部分
            _buildEmbySection(embyProvider),

            const SizedBox(height: 20),

            const SharedRemoteLibrarySettingsSection(),

            const SizedBox(height: 20),

            // 其他远程媒体库服务 (预留)
            _buildOtherServicesSection(),
          ],
        );
      },
    );
  }

  Widget _buildErrorCard(JellyfinProvider jellyfinProvider, EmbyProvider embyProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final infoBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.16, lightOpacity: 0.12);
    final infoBorder = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.28, lightOpacity: 0.18);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.error, size: 24),
              const SizedBox(width: 12),
              Text(
                '服务初始化错误',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (jellyfinProvider.hasError && jellyfinProvider.errorMessage != null)
            _buildErrorItem('Jellyfin', jellyfinProvider.errorMessage!),
          if (embyProvider.hasError && embyProvider.errorMessage != null) ...[
            if (jellyfinProvider.hasError) const SizedBox(height: 8),
            _buildErrorItem('Emby', embyProvider.errorMessage!),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: infoBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: infoBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: colorScheme.tertiary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '这些错误不会影响其他功能的正常使用。您可以尝试重新配置服务器连接。',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: secondaryColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorItem(String serviceName, String errorMessage) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final warningBackground = isDark
        ? colorScheme.error.withOpacity(0.22)
        : colorScheme.error.withOpacity(0.12);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: warningBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.error.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            errorMessage,
            locale:Locale("zh-Hans","zh"),
style: TextStyle(
              color: colorScheme.error.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJellyfinSection(JellyfinProvider jellyfinProvider) {
    const jellyfinBrandColor = Color(0xFF02A4FF);
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final statusBackground = isDark
        ? jellyfinBrandColor.withOpacity(0.25)
        : jellyfinBrandColor.withOpacity(0.12);
    final statusBorder = jellyfinBrandColor.withOpacity(isDark ? 0.9 : 0.6);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/jellyfin.svg',
                colorFilter: const ColorFilter.mode(jellyfinBrandColor, BlendMode.srcIn),
                width: 24,
                height: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Jellyfin 媒体服务器',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const Spacer(),
              if (jellyfinProvider.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusBorder, width: 1),
                  ),
                  child: Text(
                    '已连接',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: jellyfinBrandColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
              
          const SizedBox(height: 16),
              
          if (!jellyfinProvider.isConnected) ...[
                Text(
                  'Jellyfin是一个免费的媒体服务器软件，可以让您在任何设备上流式传输您的媒体收藏。',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: secondaryColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _buildGlassButton(
                    onPressed: () => _showJellyfinServerDialog(),
                    icon: Icons.add,
                    label: '连接Jellyfin服务器',
                  ),
                ),
              ] else ...[
                // 已连接状态显示服务器信息
                _buildServerInfo(jellyfinProvider),
                
                const SizedBox(height: 16),
                
                // 媒体库信息
                _buildLibraryInfo(jellyfinProvider),
                
                const SizedBox(height: 16),
                
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _showJellyfinServerDialog(),
                        icon: Icons.settings,
                        label: '管理服务器',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _disconnectServer(jellyfinProvider),
                        icon: Icons.logout,
                        label: '断开连接',
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ],
        ],
      ),
    );
  }

  Widget _buildServerInfo(JellyfinProvider jellyfinProvider) {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final overlayBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.12, lightOpacity: 0.08);
    final borderColor = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.2, lightOpacity: 0.12);
    final Color accentColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overlayBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.dns, color: accentColor, size: 16),
              const SizedBox(width: 8),
              Text('服务器:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  jellyfinProvider.serverUrl ?? '未知',
                  style: TextStyle(color: primaryColor, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person, color: accentColor, size: 16),
              const SizedBox(width: 8),
              Text('用户:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                jellyfinProvider.username ?? '匿名',
                style: TextStyle(color: primaryColor, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryInfo(JellyfinProvider jellyfinProvider) {
    final selectedLibraries = jellyfinProvider.selectedLibraryIds;
    final availableLibraries = jellyfinProvider.availableLibraries;
    
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    const jellyfinBrandColor = Color(0xFF02A4FF);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBackground = isDark
        ? jellyfinBrandColor.withOpacity(0.25)
        : jellyfinBrandColor.withOpacity(0.12);
    final unknownChipBackground = isDark
        ? Colors.orange.withOpacity(0.25)
        : Colors.orange.withOpacity(0.16);
    final unknownChipText = Colors.orange.shade700;
    final overlayBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.12, lightOpacity: 0.08);
    final borderColor = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.2, lightOpacity: 0.12);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overlayBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.library_outline, color: jellyfinBrandColor, size: 16),
              const SizedBox(width: 8),
              Text('媒体库:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
                style: TextStyle(color: primaryColor, fontSize: 14),
              ),
            ],
          ),
          if (selectedLibraries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectedLibraries.map((libraryId) {
                // 安全地查找媒体库，避免数组越界异常
                final library = availableLibraries.where((lib) => lib.id == libraryId).isNotEmpty
                    ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                    : null;
                
                if (library == null) {
                  // 如果找不到对应的库，显示ID
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: unknownChipBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '未知媒体库 ($libraryId)',
                      style: TextStyle(
                        color: unknownChipText,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    library.name,
                    style: TextStyle(
                      color: jellyfinBrandColor,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmbySection(EmbyProvider embyProvider) {
    const embyBrandColor = Color(0xFF52B54B);
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final statusBackground = isDark
        ? embyBrandColor.withOpacity(0.26)
        : embyBrandColor.withOpacity(0.12);
    final statusBorder = embyBrandColor.withOpacity(isDark ? 0.9 : 0.6);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/emby.svg',
                colorFilter: const ColorFilter.mode(embyBrandColor, BlendMode.srcIn),
                width: 24,
                height: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Emby 媒体服务器',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const Spacer(),
              if (embyProvider.isConnected)
                Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusBorder, width: 1),
                      ),
                      child: Text(
                        '已连接',
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                          color: embyBrandColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
          if (!embyProvider.isConnected) ...[
                Text(
                  'Emby是一个强大的个人媒体服务器，可以让您在任何设备上组织、播放和流式传输您的媒体收藏。',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: secondaryColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _buildGlassButton(
                    onPressed: () => _showEmbyServerDialog(),
                    icon: Icons.add,
                    label: '连接Emby服务器',
                  ),
                ),
              ] else ...[
                // 已连接状态显示服务器信息
                _buildEmbyServerInfo(embyProvider),
                
                const SizedBox(height: 16),
                
                // 媒体库信息
                _buildEmbyLibraryInfo(embyProvider),
                
                const SizedBox(height: 16),
                
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _showEmbyServerDialog(),
                        icon: Icons.settings,
                        label: '管理服务器',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _disconnectEmbyServer(embyProvider),
                        icon: Icons.logout,
                        label: '断开连接',
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ],
        ],
      ),
    );
  }

  Widget _buildEmbyServerInfo(EmbyProvider embyProvider) {
    const embyBrandColor = Color(0xFF52B54B);
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final overlayBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.12, lightOpacity: 0.08);
    final borderColor = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.2, lightOpacity: 0.12);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overlayBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.dns, color: embyBrandColor, size: 16),
              const SizedBox(width: 8),
              Text('服务器:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  embyProvider.serverUrl ?? '未知',
                  style: TextStyle(color: primaryColor, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, color: embyBrandColor, size: 16),
              const SizedBox(width: 8),
              Text('用户:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                embyProvider.username ?? '匿名',
                style: TextStyle(color: primaryColor, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmbyLibraryInfo(EmbyProvider embyProvider) {
    final selectedLibraries = embyProvider.selectedLibraryIds;
    final availableLibraries = embyProvider.availableLibraries;
    const embyBrandColor = Color(0xFF52B54B);
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.12, lightOpacity: 0.08);
    final borderColor = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.2, lightOpacity: 0.12);
    final chipBackground = isDark
        ? embyBrandColor.withOpacity(0.26)
        : embyBrandColor.withOpacity(0.14);
    final unknownChipBackground = isDark
        ? Colors.orange.withOpacity(0.25)
        : Colors.orange.withOpacity(0.16);
    final unknownChipText = Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overlayBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.library_outline, color: embyBrandColor, size: 16),
              const SizedBox(width: 8),
              Text('媒体库:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryColor, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
                style: TextStyle(color: primaryColor, fontSize: 14),
              ),
            ],
          ),
          if (selectedLibraries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectedLibraries.map((libraryId) {
                final library = availableLibraries
                    .where((lib) => lib.id == libraryId)
                    .isNotEmpty
                    ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                    : null;

                if (library == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: unknownChipBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '未知媒体库 ($libraryId)',
                      style: TextStyle(
                        color: unknownChipText,
                        fontSize: 12,
                      ),
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    library.name,
                    style: const TextStyle(
                      color: embyBrandColor,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtherServicesSection() {
    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final overlayBackground = ThemeColorUtils.overlayColor(context,
        darkOpacity: 0.18, lightOpacity: 0.1);
    final borderColor = ThemeColorUtils.borderColor(context,
        darkOpacity: 0.28, lightOpacity: 0.16);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
          sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: overlayBackground,
            border: Border.all(color: borderColor, width: 0.5),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Ionicons.cloud_outline,
                    color: primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '其他媒体服务',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              Text(
                '更多远程媒体服务支持正在开发中...',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  color: secondaryColor,
                  fontSize: 14,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 预留的服务列表
              ..._buildFutureServices(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFutureServices() {
    final services = [
      {'name': 'DLNA/UPnP', 'icon': Ionicons.wifi_outline, 'status': '计划中'},
    ];

    final primaryColor = ThemeColorUtils.primaryForeground(context);
    final secondaryColor = ThemeColorUtils.secondaryForeground(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final statusBackground = isDark
        ? Colors.grey.withOpacity(0.25)
        : Colors.grey.withOpacity(0.16);
    final statusColor = isDark ? Colors.grey.shade200 : Colors.grey.shade700;

    return services
        .map(
          (service) => ListTile(
            leading: Icon(
              service['icon'] as IconData,
              color: primaryColor,
            ),
            title: Text(
              service['name'] as String,
              style: TextStyle(color: secondaryColor),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                service['status'] as String,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                ),
              ),
            ),
            onTap: null,
          ),
        )
        .toList();
  }

  Future<void> _showJellyfinServerDialog() async {
    final result = await NetworkMediaServerDialog.show(context, MediaServerType.jellyfin);
    
    if (result == true) {
      if (mounted) {
        BlurSnackBar.show(context, 'Jellyfin服务器设置已更新');
      }
    }
  }

  Future<void> _disconnectServer(JellyfinProvider jellyfinProvider) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '断开连接',
      content: '确定要断开与Jellyfin服务器的连接吗？\n\n这将清除服务器信息和登录状态。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: ThemeColorUtils.secondaryForeground(context))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('断开连接', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await jellyfinProvider.disconnectFromServer();
        if (mounted) {
          BlurSnackBar.show(context, '已断开与Jellyfin服务器的连接');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '断开连接时出错: $e');
        }
      }
    }
  }

  Widget _buildGlassButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool isDestructive = false,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;

        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration:
                    _glassButtonDecoration(context, isHovered: isHovered, isDestructive: isDestructive),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: _glassButtonIconColor(context, isDestructive: isDestructive),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color:
                                  _glassButtonTextColor(context, isDestructive: isDestructive),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
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
      },
    );
  }

  BoxDecoration _glassButtonDecoration(BuildContext context,
      {required bool isHovered, required bool isDestructive}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isDestructive ? colorScheme.error : colorScheme.primary;
    final double backgroundOpacity = isDark
        ? (isHovered ? 0.2 : 0.14)
        : (isHovered ? 0.9 : 0.82);
    final backgroundColor = Colors.white.withOpacity(backgroundOpacity);
    final borderColor = isDark
        ? Colors.white.withOpacity(isHovered ? 0.45 : 0.28)
        : Colors.black.withOpacity(isHovered ? 0.12 : 0.08);

    return BoxDecoration(
      color: Color.alphaBlend(
        accentColor.withOpacity(isHovered ? 0.12 : 0.08),
        backgroundColor,
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: borderColor,
        width: 0.5,
      ),
    );
  }

  Color _glassButtonTextColor(BuildContext context, {required bool isDestructive}) {
    if (isDestructive) {
      return Theme.of(context).colorScheme.error;
    }
    return ThemeColorUtils.primaryForeground(context);
  }

  Color _glassButtonIconColor(BuildContext context, {required bool isDestructive}) {
    final colorScheme = Theme.of(context).colorScheme;
    return isDestructive ? colorScheme.error : colorScheme.primary;
  }

  Future<void> _showEmbyServerDialog() async {
    final result = await NetworkMediaServerDialog.show(context, MediaServerType.emby);
    
    if (result == true) {
      if (mounted) {
        BlurSnackBar.show(context, 'Emby服务器设置已更新');
      }
    }
  }

  Future<void> _disconnectEmbyServer(EmbyProvider embyProvider) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '断开连接',
      content: '确定要断开与Emby服务器的连接吗？\n\n这将清除服务器信息和登录状态。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: ThemeColorUtils.secondaryForeground(context))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('断开连接', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await embyProvider.disconnectFromServer();
        if (mounted) {
          BlurSnackBar.show(context, '已断开与Emby服务器的连接');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '断开连接时出错: $e');
        }
      }
    }
  }
}
