import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/widgets/dandanplay_user_activity.dart';
import '../../utils/globals.dart' as globals;
import 'package:flutter/foundation.dart' show kIsWeb;

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggedIn = false;
  String _username = '';
  bool _isLoading = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadLoginStatus();
  }

  Future<void> _loadLoginStatus() async {
    setState(() {
      _isLoggedIn = DandanplayService.isLoggedIn;
      _username = DandanplayService.userName ?? '';
      _updateAvatarUrl();
    });
  }

  void _updateAvatarUrl() {
    if (_username.contains('@qq.com')) {
      final qqNumber = _username.split('@')[0];
      String url = 'http://q.qlogo.cn/headimg_dl?dst_uin=$qqNumber&spec=640';
      
      // 如果是Web版本，使用图片代理
      if (kIsWeb) {
        try {
          // 获取当前URL
          final currentUrl = Uri.base.toString();
          final uri = Uri.parse(currentUrl);
          String baseUrl = '${uri.scheme}://${uri.host}';
          
          if (uri.port != 80 && uri.port != 443) {
            baseUrl += ':${uri.port}';
          }
          
          // 对URL进行Base64编码，以便在查询参数中安全传输
          final encodedUrl = base64Url.encode(utf8.encode(url));
          url = '$baseUrl/api/image_proxy?url=$encodedUrl';
        } catch (e) {
          debugPrint('[账户页面] 无法创建代理URL: $e');
          // 保持原始URL
        }
      }
      
      setState(() {
        _avatarUrl = url;
      });
    } else {
      setState(() {
        _avatarUrl = null;
      });
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      BlurSnackBar.show(context, '请输入用户名和密码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 调用弹弹play登录API
      final result = await DandanplayService.login(username, password);
      
      if (result['success'] == true) {
        setState(() {
          _isLoggedIn = true;
          _username = username;
        });

        _updateAvatarUrl();

        // 清空输入框
        _usernameController.clear();
        _passwordController.clear();

        // 显示登录成功提示
        if (mounted) {
          BlurSnackBar.show(context, result['message'] ?? '登录成功');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, result['message'] ?? '登录失败');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '登录失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await DandanplayService.clearLoginInfo();

    setState(() {
      _isLoggedIn = false;
      _username = '';
    });

    if (mounted) {
      BlurSnackBar.show(context, '已退出登录');
    }
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final screenSize = MediaQuery.of(context).size;
          final isPhone = screenSize.shortestSide < 600;
          
          // 使用预计算的对话框宽度和高度
          final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
          final dialogHeight = globals.DialogSizes.loginDialogHeight;
          
          // 获取键盘高度，用于动态调整底部间距
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          
          return Dialog(
            backgroundColor: Colors.transparent,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  width: dialogWidth,
                  height: dialogHeight,
                  padding: EdgeInsets.all(isPhone ? 20.0 : 24.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 5,
                        spreadRadius: 1,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 可滚动的内容区域（标题和输入框）
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '登录弹弹play账号',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: '用户名',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                style: const TextStyle(color: Colors.white),
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: '密码',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 固定在底部的按钮
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 0.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : () async {
                              setState(() {
                                _isLoading = true;
                              });
                              await _login();
                              if (_isLoggedIn && mounted) {
                                Navigator.pop(context);
                              }
                              setState(() {
                                _isLoading = false;
                              });
                            },
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        '登录',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '弹弹play账号',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoggedIn) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_avatarUrl != null)
                          ClipOval(
                            child: Image.network(
                              _avatarUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.person, color: Colors.white, size: 40);
                              },
                            ),
                          )
                        else
                          const Icon(Icons.person, color: Colors.white, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _username,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                '已登录',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: _logout,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 让活动记录铺满剩余空间
              Expanded(
                child: DandanplayUserActivity(key: ValueKey(_username)),
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showLoginDialog,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                '登录弹弹play账号',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
            ],
          ],
        ),
      ),
    );
  }
} 