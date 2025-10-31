import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'theme_color_utils.dart';

class SharedRemoteLibrarySettingsSection extends StatelessWidget {
  const SharedRemoteLibrarySettingsSection({super.key});

  Color _foregroundColor(BuildContext context, [double opacity = 1]) {
    final base = ThemeColorUtils.primaryForeground(context);
    return opacity >= 1 ? base : base.withOpacity(opacity);
  }

  Color _secondaryForeground(BuildContext context) =>
      ThemeColorUtils.secondaryForeground(context);

  Color _panelBackground(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF5F5F8);
  }

  Color _panelBorder(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.05);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        final baseColor = ThemeColorUtils.primaryForeground(context);
        final subtleColor = ThemeColorUtils.secondaryForeground(context);
        final faintColor = baseColor.withOpacity(0.6);
        return SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        baseColor,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/nipaplay.png',
                        width: 20,
                        height: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'NipaPlay 局域网媒体共享',
                    locale: Locale('zh', 'CN'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: baseColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '在另一台设备（手机/平板/电脑等客户端）开启远程访问后，填写其局域网地址即可直接浏览并播放它的本地媒体库。',
                locale: Locale('zh', 'CN'),
                style: TextStyle(color: subtleColor, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (provider.isInitializing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (provider.hosts.isEmpty)
                _buildEmptyState(context, provider)
              else
                _buildHostList(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
      BuildContext context, SharedRemoteLibraryProvider provider) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: _panelBackground(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _panelBorder(context)),
          ),
          child: Column(
            children: [
              Icon(Icons.info_outline, color: _foregroundColor(context, 0.6)),
              const SizedBox(height: 8),
              Text(
                '尚未添加任何共享客户端',
                locale: Locale('zh', 'CN'),
                style: TextStyle(color: _secondaryForeground(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _buildGlassButton(
            context: context,
            onPressed: () => _showAddHostDialog(context, provider),
            icon: Icons.add,
            label: '新增客户端',
          ),
        ),
      ],
    );
  }

  Widget _buildHostList(
      BuildContext context, SharedRemoteLibraryProvider provider) {
    return Column(
      children: [
        ...provider.hosts.map((host) {
          final isActive = provider.activeHostId == host.id;
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final accentColor = Theme.of(context).colorScheme.primary;
          final statusColor =
              host.isOnline ? accentColor : Colors.orangeAccent;
          final containerBackground = _panelBackground(context);
          final containerBorder = _panelBorder(context);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: containerBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? accentColor.withOpacity(isDark ? 0.6 : 0.3)
                    : containerBorder,
                width: isActive ? 1.2 : 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.28)
                      : Colors.black.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      host.isOnline
                          ? Icons.check_circle
                          : Icons.pending_outlined,
                      color: statusColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        host.displayName.isNotEmpty
                            ? host.displayName
                            : host.baseUrl,
                        style: TextStyle(
                          color: _foregroundColor(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (!isActive)
                      TextButton(
                        onPressed: () => provider.setActiveHost(host.id),
                        child: Text('设为当前',
                          style: TextStyle(
                                color: accentColor)),
                      )
                    else
                      Text(
                        '当前使用',
                        locale: Locale('zh', 'CN'),
                        style: TextStyle(
                            color: accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                  host.baseUrl,
                  style: TextStyle(
                      color: _secondaryForeground(context), fontSize: 13),
                ),
                if (host.lastError != null && host.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    host.lastError!,
                    locale: const Locale('zh', 'CN'),
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () =>
                          provider.refreshLibrary(userInitiated: true),
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                      ),
                      child: const Text('刷新'),
                    ),
                    TextButton(
                      onPressed: () => _showRenameDialog(
                          context, provider, host.id, host.displayName),
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                      ),
                      child: const Text('重命名'),
                    ),
                    TextButton(
                      onPressed: () => _showUpdateUrlDialog(
                          context, provider, host.id, host.baseUrl),
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                      ),
                      child: const Text('修改地址'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          _confirmRemoveHost(context, provider, host.id),
                      child: const Text('删除',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _buildGlassButton(
            context: context,
            onPressed: () => _showAddHostDialog(context, provider),
            icon: Icons.add,
            label: '新增客户端',
          ),
        ),
      ],
    );
  }

  Future<void> _showAddHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    await BlurLoginDialog.show(
      context,
      title: '添加共享客户端',
      fields: [
        LoginField(
          key: 'displayName',
          label: '备注名称',
          hint: '例如：家里的电脑',
          required: false,
        ),
        LoginField(
          key: 'baseUrl',
          label: '访问地址',
          hint: '例如：http://192.168.1.100:8080',
        ),
      ],
      loginButtonText: '添加',
      onLogin: (values) async {
        try {
          final displayName = values['displayName']?.trim().isEmpty ?? true
              ? values['baseUrl']!.trim()
              : values['displayName']!.trim();

          await provider.addHost(
            displayName: displayName,
            baseUrl: values['baseUrl']!.trim(),
          );

          return LoginResult(
            success: true,
            message: '已添加共享客户端',
          );
        } catch (e) {
          return LoginResult(
            success: false,
            message: '添加失败：$e',
          );
        }
      },
    );
  }

  Future<void> _confirmRemoveHost(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
  ) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '删除共享客户端',
      content: '确定要删除该客户端吗？',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: TextStyle(color: _secondaryForeground(context))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );

    if (confirm == true) {
      await provider.removeHost(hostId);
      BlurSnackBar.show(context, '已删除共享客户端');
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final confirmed = await BlurDialog.show<bool>(
      context: context,
      title: '重命名',
      contentWidget: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: '备注名称',
          labelStyle: TextStyle(color: _secondaryForeground(context)),
        ),
        style: TextStyle(color: _foregroundColor(context)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: TextStyle(color: _secondaryForeground(context))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('保存', style: TextStyle(color: _foregroundColor(context))),
        ),
      ],
    );

    if (confirmed == true) {
      await provider.renameHost(hostId, controller.text.trim());
      BlurSnackBar.show(context, '名称已更新');
    }
  }

  Future<void> _showUpdateUrlDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentUrl,
  ) async {
    final controller = TextEditingController(text: currentUrl);
    final confirmed = await BlurDialog.show<bool>(
      context: context,
      title: '修改访问地址',
      contentWidget: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: '访问地址',
          labelStyle: TextStyle(color: _secondaryForeground(context)),
        ),
        style: TextStyle(color: _foregroundColor(context)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: TextStyle(color: _secondaryForeground(context))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('保存', style: TextStyle(color: _foregroundColor(context))),
        ),
      ],
    );

    if (confirmed == true) {
      await provider.updateHostUrl(hostId, controller.text.trim());
      BlurSnackBar.show(context, '地址已更新');
    }
  }

  Widget _buildGlassButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color accentColor = Theme.of(context).colorScheme.primary;
        final Color iconColor = accentColor;
        final Color textColor =
            isDark ? Colors.white : ThemeColorUtils.primaryForeground(context);
        final Color baseBackground =
            isDark ? Colors.white.withOpacity(0.16) : Colors.white;
        final Color hoverBackground =
            isDark ? Colors.white.withOpacity(0.22) : Colors.white;
        final Color borderColor = isDark
            ? Colors.white.withOpacity(isHovered ? 0.4 : 0.28)
            : Colors.black.withOpacity(isHovered ? 0.14 : 0.08);
        final BoxShadow shadow = BoxShadow(
          color: isDark
              ? Colors.black.withOpacity(isHovered ? 0.32 : 0.26)
              : Colors.black.withOpacity(isHovered ? 0.16 : 0.1),
          blurRadius: 18,
          offset: const Offset(0, 8),
        );

        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isHovered ? hoverBackground : baseBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 0.6),
                  boxShadow: [shadow],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: iconColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: textColor,
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
}
