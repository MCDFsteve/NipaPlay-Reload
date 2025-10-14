import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/widgets/user_activity/fluent_user_activity.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'account_controller.dart';

/// Fluent UI版本的账号页面
class FluentAccountPage extends StatefulWidget {
  const FluentAccountPage({super.key});

  @override
  State<FluentAccountPage> createState() => _FluentAccountPageState();
}

class _FluentAccountPageState extends State<FluentAccountPage> 
    with AccountPageController {

  @override
  void showMessage(String message) {
    FluentInfoBar.show(
      context,
      message,
      severity: InfoBarSeverity.info,
    );
  }

  @override
  void showLoginDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('登录弹弹play账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(
              label: '用户名/邮箱',
              child: TextBox(
                controller: usernameController,
                placeholder: '请输入用户名或邮箱',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '密码',
              child: PasswordBox(
                controller: passwordController,
                placeholder: '请输入密码',
              ),
            ),
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: isLoading ? null : () async {
              await performLogin();
              if (isLoggedIn && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  @override
  void showRegisterDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('注册弹弹play账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(
              label: '用户名',
              child: TextBox(
                controller: registerUsernameController,
                placeholder: '5-20位英文或数字，首位不能为数字',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '密码',
              child: PasswordBox(
                controller: registerPasswordController,
                placeholder: '5-20位密码',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '邮箱',
              child: TextBox(
                controller: registerEmailController,
                placeholder: '用于找回密码',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '昵称',
              child: TextBox(
                controller: registerScreenNameController,
                placeholder: '显示名称，不超过50个字符',
              ),
            ),
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: isLoading ? null : () async {
              await performRegister();
              if (isLoggedIn && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Text('注册'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('弹弹play账号'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: isLoggedIn ? _buildLoggedInView() : _buildLoggedOutView(),
      ),
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // 头像
                avatarUrl != null
                    ? ClipOval(
                        child: material.Image.network(
                          avatarUrl!,
                          width: 48,
                          height: 48,
                          fit: material.BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(FluentIcons.contact, size: 48);
                          },
                        ),
                      )
                    : const Icon(FluentIcons.contact, size: 48),
                const SizedBox(width: 16),
                // 用户信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已登录',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
                  ),
                ),
                // 退出按钮
                Button(
                  onPressed: performLogout,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.sign_out),
                      SizedBox(width: 8),
                      Text('退出登录'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 用户活动记录
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FluentUserActivity(key: ValueKey(username)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Bangumi同步部分
        _buildBangumiSyncSection(),
      ],
    );
  }

  Widget _buildLoggedOutView() {
    return Column(
      children: [
        Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FluentIcons.contact,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '未登录弹弹play账号',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录后可以同步观看记录和个人设置',
                    style: FluentTheme.of(context).typography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: showLoginDialog,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.signin),
                            SizedBox(width: 8),
                            Text('登录账号'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Button(
                        onPressed: showRegisterDialog,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.add_friend),
                            SizedBox(width: 8),
                            Text('注册账号'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Bangumi同步部分
        _buildBangumiSyncSection(),
      ],
    );
  }

  Widget _buildBangumiSyncSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.sync, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Bangumi观看记录同步',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (isBangumiLoggedIn) ...[
              // 已登录状态
              _buildBangumiLoggedInView(),
            ] else ...[
              // 未登录状态
              _buildBangumiLoggedOutView(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBangumiLoggedInView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户信息
        InfoBar(
          title: Text('已连接到 ${bangumiUserInfo?['nickname'] ?? bangumiUserInfo?['username'] ?? 'Bangumi'}'),
          content: lastBangumiSyncTime != null
              ? Text('上次同步: ${_formatDateTime(lastBangumiSyncTime!)}')
              : const Text('尚未同步'),
          severity: InfoBarSeverity.success,
        ),
        const SizedBox(height: 16),

        // 同步状态
        if (isBangumiSyncing) ...[
          InfoBar(
            title: const Text('同步中'),
            content: Text(bangumiSyncStatus),
            severity: InfoBarSeverity.info,
          ),
          const SizedBox(height: 16),
        ],

        // 操作按钮
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Button(
              onPressed: isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: false),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.sync),
                  SizedBox(width: 6),
                  Text('同步到Bangumi'),
                ],
              ),
            ),
            Button(
              onPressed: isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: true),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.refresh),
                  SizedBox(width: 6),
                  Text('同步所有本地记录'),
                ],
              ),
            ),
            Button(
              onPressed: isLoading ? null : testBangumiConnection,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.globe),
                  SizedBox(width: 6),
                  Text('验证令牌'),
                ],
              ),
            ),
            Button(
              onPressed: clearBangumiSyncCache,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.delete),
                  SizedBox(width: 6),
                  Text('清除同步记录缓存'),
                ],
              ),
            ),
            Button(
              onPressed: clearBangumiToken,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.sign_out),
                  SizedBox(width: 6),
                  Text('删除Bangumi令牌'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBangumiLoggedOutView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步本地观看历史到Bangumi收藏',
          style: FluentTheme.of(context).typography.body,
        ),
        const SizedBox(height: 8),
        Text(
          '需要在 https://next.bgm.tv/demo/access-token 创建访问令牌',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        
        // 令牌输入框
        InfoLabel(
          label: 'Bangumi访问令牌',
          child: PasswordBox(
            controller: bangumiTokenController,
            placeholder: '请输入访问令牌',
          ),
        ),
        const SizedBox(height: 16),

        // 保存按钮
        FilledButton(
          onPressed: isLoading ? null : saveBangumiToken,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.save),
                    SizedBox(width: 6),
                    Text('保存令牌'),
                  ],
                ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}