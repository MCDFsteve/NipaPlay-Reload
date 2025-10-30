import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // Import Ionicons
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/storage_service.dart'; // 导入StorageService
import 'package:permission_handler/permission_handler.dart'; // 导入权限处理库
import 'package:nipaplay/utils/android_storage_helper.dart'; // 导入Android存储辅助类
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart'; // 导入全局变量和设备检测函数
// Import MethodChannel
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:nipaplay/services/manual_danmaku_matcher.dart'; // 导入手动弹幕匹配器
import 'package:nipaplay/services/webdav_service.dart'; // 导入WebDAV服务
import 'package:nipaplay/widgets/nipaplay_theme/webdav_connection_dialog.dart'; // 导入WebDAV连接对话框
import 'theme_color_utils.dart';

class LibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const LibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<LibraryManagementTab> createState() => _LibraryManagementTabState();
}

class _LibraryManagementTabState extends State<LibraryManagementTab> {
  static const String _lastScannedDirectoryPickerPathKey =
      'last_scanned_dir_picker_path';
  static const String _librarySortOptionKey =
      'library_sort_option'; // 新增键用于保存排序选项

  final Map<String, List<io.FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};
  final ScrollController _listScrollController = ScrollController();

  // 存储ScanService引用
  ScanService? _scanService;

  // 排序相关状态
  int _sortOption =
      0; // 0: 文件名升序, 1: 文件名降序, 2: 修改时间升序, 3: 修改时间降序, 4: 大小升序, 5: 大小降序

  // WebDAV相关状态
  bool _showWebDAVFolders = false; // 控制显示本地文件夹还是WebDAV文件夹
  List<WebDAVConnection> _webdavConnections = [];
  final Map<String, List<WebDAVFile>> _webdavFolderContents = {};
  final Set<String> _loadingWebDAVFolders = {};

  Color _foregroundColor(BuildContext context, [double opacity = 1]) {
    final base = ThemeColorUtils.primaryForeground(context);
    return opacity >= 1 ? base : base.withOpacity(opacity);
  }

  @override
  void initState() {
    super.initState();

    // 延迟初始化，确保挂载完成
    _initScanServiceListener();

    // 加载保存的排序选项
    _loadSortOption();

    // 初始化WebDAV服务
    _initWebDAVService();
  }

  // 提取为单独的方法，方便管理生命周期
  void _initScanServiceListener() {
    // 使用微任务确保在当前渲染帧结束后执行
    Future.microtask(() {
      // 确保组件仍然挂载
      if (!mounted) return;

      try {
        final scanService = Provider.of<ScanService>(context, listen: false);
        _scanService = scanService; // 保存引用
        print('初始化ScanService监听器开始');
        scanService.addListener(_checkScanResults);
        print('ScanService监听器添加成功');
      } catch (e) {
        print('初始化ScanService监听器失败: $e');
      }
    });
  }

  // 初始化WebDAV服务
  Future<void> _initWebDAVService() async {
    try {
      await WebDAVService.instance.initialize();
      if (mounted) {
        setState(() {
          _webdavConnections = WebDAVService.instance.connections;
        });
      }
    } catch (e) {
      debugPrint('初始化WebDAV服务失败: $e');
    }
  }

  // 显示WebDAV连接对话框
  Future<void> _showWebDAVConnectionDialog() async {
    final result = await WebDAVConnectionDialog.show(context);
    if (result == true && mounted) {
      // 刷新WebDAV连接列表
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
      });
      BlurSnackBar.show(context, 'WebDAV连接已添加，您可以切换到WebDAV视图查看');
    }
  }

  @override
  void dispose() {
    // 安全移除监听器，使用保存的引用
    if (_scanService != null) {
      _scanService!.removeListener(_checkScanResults);
    }
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAndScanDirectory() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后。');
      return;
    }

    // --- iOS平台逻辑 ---
    if (io.Platform.isIOS) {
      // 使用StorageService获取应用存储目录
      final io.Directory appDir = await StorageService.getAppStorageDirectory();
      await scanService.startDirectoryScan(appDir.path,
          skipPreviouslyMatchedUnwatched:
              false); // Ensure full scan for new folder
      return;
    }
    // --- End iOS平台逻辑 ---

    // Android和桌面平台分开处理
    if (io.Platform.isAndroid) {
      // 获取Android版本
      final int sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();

      // Android 13+：使用媒体API扫描视频文件
      if (sdkVersion >= 33) {
        await _scanAndroidMediaFolders();
        return;
      }

      // Android 13以下：允许自由选择文件夹
      // 检查并请求所有必要的权限...
      // 保留原来的权限请求代码
    }

    // Android 13以下和桌面平台继续使用原来的文件选择器逻辑
    // 使用FilePickerService选择目录（适用于Android和桌面平台）
    String? selectedDirectory;
    try {
      final filePickerService = FilePickerService();
      selectedDirectory = await filePickerService.pickDirectory();

      if (selectedDirectory == null) {
        if (mounted) {
          BlurSnackBar.show(context, "未选择文件夹。");
        }
        return;
      }

      // 验证选择的目录是否可访问
      bool accessCheck = false;
      if (io.Platform.isAndroid) {
        // 使用原生方法检查目录权限
        final dirCheck = await AndroidStorageHelper.checkDirectoryPermissions(
            selectedDirectory);
        accessCheck =
            dirCheck['canRead'] == true && dirCheck['canWrite'] == true;
        debugPrint('Android目录权限检查结果: $dirCheck');
      } else {
        // 非Android平台使用Flutter方法检查
        accessCheck =
            await StorageService.isValidStorageDirectory(selectedDirectory);
      }
      if (!accessCheck && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "文件夹访问受限",
          content: io.Platform.isAndroid
              ? "无法访问您选择的文件夹，可能是权限问题。\n\n如果您使用的是Android 11或更高版本，请考虑在设置中开启「管理所有文件」权限。"
              : "无法访问您选择的文件夹，可能是权限问题。",
          actions: <Widget>[
            TextButton(
              child: Text(
                "知道了",
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(color: _foregroundColor(context, 0.7)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("打开设置",
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, "选择文件夹时出错: $e");
      }
      return;
    }

    // 仅iOS平台需要检查是否为内部路径
    if (io.Platform.isIOS) {
      final io.Directory appDir = await StorageService.getAppStorageDirectory();
      final String appPath = appDir.path;

      // Normalize paths to handle potential '/private' prefix discrepancy on iOS
      String effectiveSelectedDir = selectedDirectory;
      if (selectedDirectory.startsWith('/private') &&
          !appPath.startsWith('/private')) {
        // If selected has /private but appPath doesn't, selected might be /private/var... and appPath /var...
        // No change needed for selectedDirectory here, comparison logic will handle it.
      } else if (!selectedDirectory.startsWith('/private') &&
          appPath.startsWith('/private')) {
        // If selected doesn't have /private but appPath does, this is unusual, but we adapt.
        // This case is less likely if appDir.path is from StorageService.
      }

      // The core comparison: selected path must start with appPath OR /private + appPath
      bool isInternalPath = selectedDirectory.startsWith(appPath) ||
          (appPath.startsWith('/var') &&
              selectedDirectory.startsWith('/private$appPath'));

      if (!isInternalPath) {
        if (mounted) {
          String dialogContent = "您选择的文件夹位于应用外部。\n\n";
          dialogContent += "为了正常扫描和管理媒体文件，请将文件或文件夹拷贝到应用的专属文件夹中。\n\n";
          dialogContent +=
              "您可以在\"文件\"应用中，导航至\"我的 iPhone / iPad\" > \"NipaPlay\"找到此文件夹。\n\n";
          dialogContent += "这是由于iOS的安全和权限机制，确保应用仅能访问您明确置于其管理区域内的数据。";

          BlurDialog.show<void>(
            context: context,
            title: "访问提示 ",
            content: dialogContent,
            actions: <Widget>[
              TextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
        return;
      }
    }

    // Android平台检查是否有访问所选文件夹的权限
    if (io.Platform.isAndroid) {
      try {
        // 尝试读取文件夹内容以检查权限
        final dir = io.Directory(selectedDirectory);
        await dir.list().first.timeout(const Duration(seconds: 2),
            onTimeout: () {
          throw TimeoutException('无法访问文件夹');
        });
      } catch (e) {
        if (mounted) {
          BlurDialog.show<void>(
            context: context,
            title: "访问错误",
            content:
                "无法访问所选文件夹，可能是权限问题。\n\n建议选择您的个人文件夹或媒体文件夹，如Pictures、Download或Movies。\n\n错误: ${e.toString().substring(0, min(e.toString().length, 100))}",
            actions: <Widget>[
              TextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
        return;
      }
    }

    // 保存用户选择的自定义路径
    // [修改] 自定义目录会影响安卓缓存，先注释
    //await StorageService.saveCustomStoragePath(selectedDirectory);
    // 开始扫描目录
    await scanService.startDirectoryScan(selectedDirectory,
        skipPreviouslyMatchedUnwatched:
            false); // Ensure full scan for new folder
  }

  Future<void> _handleRemoveFolder(String folderPathToRemove) async {
    final scanService = Provider.of<ScanService>(context, listen: false);

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '确认移除',
      content: '确定要从列表中移除文件夹 "$folderPathToRemove" 吗？\n相关的媒体记录也会被清理。',
      actions: <Widget>[
        TextButton(
          child: Text('取消',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: _foregroundColor(context, 0.7))),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('移除',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      //debugPrint("User confirmed removal of: $folderPathToRemove");
      await scanService.removeScannedFolder(folderPathToRemove);
      // ScanService.removeScannedFolder will handle:
      // - Removing from its internal list and saving
      // - Cleaning WatchHistoryManager entries (once fully implemented there)
      // - Notifying listeners (which AnimePage uses to refresh WatchHistoryProvider and MediaLibraryPage)

      if (mounted) {
        BlurSnackBar.show(context, '请求已提交: $folderPathToRemove 将被移除并清理相关记录。');
      }
    }
  }

  Future<List<io.FileSystemEntity>> _getDirectoryContents(String path) async {
    final List<io.FileSystemEntity> contents = [];
    final io.Directory directory = io.Directory(path);
    if (await directory.exists()) {
      try {
        await for (var entity
            in directory.list(recursive: false, followLinks: false)) {
          if (entity is io.Directory) {
            contents.add(entity);
          } else if (entity is io.File) {
            String extension = p.extension(entity.path).toLowerCase();
            if (extension == '.mp4' || extension == '.mkv') {
              contents.add(entity);
            }
          }
        }
      } catch (e) {
        //debugPrint("Error listing directory contents for $path: $e");
        if (mounted) {
          setState(() {
            // _scanMessage = "加载文件夹内容失败: $path ($e)";
          });
        }
      }
    }
    // 应用选择的排序方式
    _sortContents(contents);
    return contents;
  }

  // 排序内容的方法
  void _sortContents(List<io.FileSystemEntity> contents) {
    contents.sort((a, b) {
      // 总是优先显示文件夹
      if (a is io.Directory && b is io.File) return -1;
      if (a is io.File && b is io.Directory) return 1;

      // 同种类型文件按选择的排序方式排序
      int result = 0;

      switch (_sortOption) {
        case 0: // 文件名升序
          result = p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
          break;
        case 1: // 文件名降序
          result = p
              .basename(b.path)
              .toLowerCase()
              .compareTo(p.basename(a.path).toLowerCase());
          break;
        case 2: // 修改时间升序（旧到新）
          try {
            final aModified = a.statSync().modified;
            final bModified = b.statSync().modified;
            result = aModified.compareTo(bModified);
          } catch (e) {
            // 如果获取修改时间失败，回退到文件名排序
            result = p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 3: // 修改时间降序（新到旧）
          try {
            final aModified = a.statSync().modified;
            final bModified = b.statSync().modified;
            result = bModified.compareTo(aModified);
          } catch (e) {
            // 如果获取修改时间失败，回退到文件名排序
            result = p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 4: // 大小升序（小到大）
          try {
            final aSize = a is io.File ? a.lengthSync() : 0;
            final bSize = b is io.File ? b.lengthSync() : 0;
            result = aSize.compareTo(bSize);
          } catch (e) {
            // 如果获取大小失败，回退到文件名排序
            result = p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 5: // 大小降序（大到小）
          try {
            final aSize = a is io.File ? a.lengthSync() : 0;
            final bSize = b is io.File ? b.lengthSync() : 0;
            result = bSize.compareTo(aSize);
          } catch (e) {
            // 如果获取大小失败，回退到文件名排序
            result = p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        default:
          result = p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
      }

      return result;
    });
  }

  // 对文件夹路径列表进行排序
  List<String> _sortFolderPaths(List<String> folderPaths) {
    final sortedPaths = List<String>.from(folderPaths);
    sortedPaths.sort((a, b) {
      int result = 0;
      switch (_sortOption) {
        case 0:
          result = p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase());
          break;
        case 1:
          result = p
              .basename(b)
              .toLowerCase()
              .compareTo(p.basename(a).toLowerCase());
          break;
        case 2:
          try {
            final aModified = io.File(a).statSync().modified;
            final bModified = io.File(b).statSync().modified;
            result = aModified.compareTo(bModified);
          } catch (e) {
            result = p
                .basename(a)
                .toLowerCase()
                .compareTo(p.basename(b).toLowerCase());
          }
          break;
        case 3:
          try {
            final aModified = io.File(a).statSync().modified;
            final bModified = io.File(b).statSync().modified;
            result = bModified.compareTo(aModified);
          } catch (e) {
            result = p
                .basename(a)
                .toLowerCase()
                .compareTo(p.basename(b).toLowerCase());
          }
          break;
        case 4:
          result = 0.compareTo(0);
          break; // 文件夹大小排序对路径无效
        case 5:
          result = 0.compareTo(0);
          break; // 文件夹大小排序对路径无效
      }
      return result;
    });
    return sortedPaths;
  }

  Future<void> _loadFolderChildren(String folderPath) async {
    // 检查是否已经在加载中，避免重复加载
    if (_loadingFolders.contains(folderPath)) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingFolders.add(folderPath);
      });
    }

    try {
      final children = await _getDirectoryContents(folderPath);

      if (mounted) {
        setState(() {
          _expandedFolderContents[folderPath] = children;
          _loadingFolders.remove(folderPath);
        });
      }
    } catch (e) {
      // 如果加载失败，确保移除加载状态
      if (mounted) {
        setState(() {
          _loadingFolders.remove(folderPath);
        });
      }
      debugPrint('加载文件夹内容失败: $folderPath, 错误: $e');
    }
  }

  List<Widget> _buildFileSystemNodes(
      List<io.FileSystemEntity> entities, String parentPath, int depth) {
    if (entities.isEmpty && !_loadingFolders.contains(parentPath)) {
      return [
        Padding(
          padding:
              EdgeInsets.only(left: depth * 16.0 + 16.0, top: 8.0, bottom: 8.0),
          child: Text("文件夹为空",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: _foregroundColor(context, 0.54))),
        )
      ];
    }

    return entities.map<Widget>((entity) {
      final indent = EdgeInsets.only(left: depth * 16.0);
      if (entity is io.Directory) {
        final dirPath = entity.path;
        return Padding(
          padding: indent,
          child: ExpansionTile(
            key: PageStorageKey<String>(dirPath),
            leading: Icon(Icons.folder_outlined,
                color: _foregroundColor(context, 0.7)),
            title: Text(p.basename(dirPath),
                style: TextStyle(color: _foregroundColor(context))),
            onExpansionChanged: (isExpanded) {
              if (isExpanded &&
                  _expandedFolderContents[dirPath] == null &&
                  !_loadingFolders.contains(dirPath)) {
                // 使用 Future.microtask 确保在当前构建帧完成后执行
                Future.microtask(() => _loadFolderChildren(dirPath));
              }
            },
            children: _loadingFolders.contains(dirPath)
                ? [
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator()))
                  ]
                : _buildFileSystemNodes(
                    _expandedFolderContents[dirPath] ?? [], dirPath, depth + 1),
          ),
        );
      } else if (entity is io.File) {
        return Padding(
          padding: indent,
          child: FutureBuilder<WatchHistoryItem?>(
            future: WatchHistoryManager.getHistoryItem(entity.path),
            builder: (context, snapshot) {
              // 获取扫描到的动画信息
              final historyItem = snapshot.data;
              final String fileName = p.basename(entity.path);

              // 调试信息
              if (historyItem != null) {
                debugPrint('🎬 文件: $fileName');
                debugPrint('   动画名: ${historyItem.animeName}');
                debugPrint('   集数: ${historyItem.episodeTitle}');
                debugPrint('   来自扫描: ${historyItem.isFromScan}');
                debugPrint('   动画ID: ${historyItem.animeId}');
                debugPrint('   集数ID: ${historyItem.episodeId}');
              }

              // 构建副标题（动画名称和集数）
              String? subtitleText;
              // 放宽条件：只要有历史记录且有动画信息就显示
              if (historyItem != null &&
                  (historyItem.animeId != null ||
                      historyItem.episodeId != null ||
                      (historyItem.animeName.isNotEmpty &&
                          historyItem.animeName !=
                              p.basenameWithoutExtension(entity.path)))) {
                final List<String> subtitleParts = [];

                // 添加动画名称（如果存在且不是文件名）
                if (historyItem.animeName.isNotEmpty &&
                    historyItem.animeName !=
                        p.basenameWithoutExtension(entity.path)) {
                  subtitleParts.add(historyItem.animeName);
                }

                // 添加集数标题（如果存在）
                if (historyItem.episodeTitle != null &&
                    historyItem.episodeTitle!.isNotEmpty) {
                  subtitleParts.add(historyItem.episodeTitle!);
                }

                if (subtitleParts.isNotEmpty) {
                  subtitleText = subtitleParts.join(' - ');
                }
              }

              return ListTile(
                leading: Icon(Icons.videocam_outlined,
                    color: _foregroundColor(context)),
                title: Text(fileName,
                    style: TextStyle(color: _foregroundColor(context))),
                subtitle: subtitleText != null
                    ? Text(
                        subtitleText,
                        locale: Locale("zh-Hans", "zh"),
                        style: TextStyle(
                          color: _foregroundColor(context, 0.7),
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 手动匹配弹幕按钮
                    IconButton(
                      icon: Icon(Icons.subtitles,
                          color: _foregroundColor(context, 0.7), size: 20),
                      onPressed: () => _showManualDanmakuMatchDialog(
                          entity.path, fileName, historyItem),
                    ),
                    // 移除扫描结果按钮
                    if (historyItem != null &&
                        (historyItem.animeId != null ||
                            historyItem.episodeId != null))
                      IconButton(
                        icon: Icon(Icons.clear,
                            color: _foregroundColor(context, 0.7), size: 20),
                        onPressed: () => _showRemoveScanResultDialog(
                            entity.path, fileName, historyItem),
                      ),
                  ],
                ),
                onTap: () {
                  // Use existing history item if available, otherwise create a minimal one
                  final WatchHistoryItem itemToPlay = historyItem ??
                      WatchHistoryItem(
                        filePath: entity.path,
                        animeName: p.basenameWithoutExtension(entity.path),
                        episodeTitle: '',
                        duration: 0,
                        lastPosition: 0,
                        watchProgress: 0.0,
                        lastWatchTime: DateTime.now(),
                      );
                  widget.onPlayEpisode(itemToPlay);
                },
              );
            },
          ),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  // 显示排序选择对话框
  Future<void> _showSortOptionsDialog() async {
    final List<String> sortOptions = [
      '文件名 (A→Z)',
      '文件名 (Z→A)',
      '修改时间 (旧→新)',
      '修改时间 (新→旧)',
      '文件大小 (小→大)',
      '文件大小 (大→小)',
    ];

    final result = await BlurDialog.show<int>(
      context: context,
      title: '选择排序方式',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '选择文件夹中文件和子文件夹的排序方式：',
            locale: Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: _foregroundColor(context, 0.8),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200, // 减少高度
            child: SingleChildScrollView(
              child: Column(
                children: sortOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final isSelected = _sortOption == index;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    child: Material(
                      color: isSelected
                          ? _foregroundColor(context, 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => Navigator.of(context).pop(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              if (isSelected) ...[
                                const Icon(
                                  Icons.check,
                                  color: Colors.lightBlueAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                              ] else ...[
                                const SizedBox(width: 28),
                              ],
                              Expanded(
                                child: Text(
                                  option,
                                  locale: Locale("zh-Hans", "zh"),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.lightBlueAccent
                                        : _foregroundColor(context, 0.7),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消',
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(color: _foregroundColor(context, 0.54))),
          ),
        ],
      ),
    );

    if (result != null && result != _sortOption && mounted) {
      setState(() {
        _sortOption = result;
        // 清空已展开的文件夹内容，强制重新加载和排序
        _expandedFolderContents.clear();
      });

      // 保存排序选项
      _saveSortOption(result);

      BlurSnackBar.show(context, '排序方式已更改为：${sortOptions[result]}');
    }
  }

  // 检查扫描结果，如果没有找到视频文件，显示指导弹窗
  void _checkScanResults() {
    // 首先检查 mounted 状态
    if (!mounted) return;

    try {
      // 使用保存的引用避免在组件销毁时访问Provider
      final scanService = _scanService;
      if (scanService == null) return;

      print(
          '检查扫描结果: isScanning=${scanService.isScanning}, justFinishedScanning=${scanService.justFinishedScanning}, totalFilesFound=${scanService.totalFilesFound}, scannedFolders.isEmpty=${scanService.scannedFolders.isEmpty}');

      // 只在扫描刚结束时检查
      if (!scanService.isScanning && scanService.justFinishedScanning) {
        print('扫描刚结束，准备检查是否显示指导弹窗');

        // 如果没有文件，或者扫描文件夹为空，显示指导弹窗
        if ((scanService.totalFilesFound == 0 ||
                scanService.scannedFolders.isEmpty) &&
            mounted) {
          print('符合条件，即将显示文件导入指导弹窗');
          _showFileImportGuideDialog();
        } else {
          print(
              '不符合显示条件: totalFilesFound=${scanService.totalFilesFound}, scannedFolders.isEmpty=${scanService.scannedFolders.isEmpty}');
        }

        // 重置标志
        scanService.resetJustFinishedScanning();
      }
    } catch (e) {
      print('检查扫描结果时出错: $e');
    }
  }

  // 显示文件导入指导弹窗
  void _showFileImportGuideDialog() {
    if (!mounted) return;

    String dialogContent = "未发现任何视频文件。以下是向NipaPlay添加视频的方法：\n\n";

    if (io.Platform.isIOS) {
      dialogContent += "1. 打开iOS「文件」应用\n";
      dialogContent += "2. 浏览到包含您视频的文件夹\n";
      dialogContent += "3. 长按视频文件，选择「分享」\n";
      dialogContent += "4. 在分享菜单中选择「拷贝到NipaPlay」\n\n";
      dialogContent += "或者：\n";
      dialogContent += "1. 通过iTunes文件共享功能\n";
      dialogContent += "2. 从电脑直接拷贝视频到NipaPlay文件夹\n";
    } else if (io.Platform.isAndroid) {
      dialogContent += "1. 确保将视频文件存放在易于访问的文件夹中\n";
      dialogContent += "2. 您可以创建专门的文件夹，如「Movies」或「Anime」\n";
      dialogContent += "3. 确保文件夹权限设置正确，应用可以访问\n";
      dialogContent += "4. 点击上方「添加并扫描文件夹」选择您的视频文件夹\n\n";
      dialogContent += "常见问题：\n";
      dialogContent += "- 如果无法选择某个文件夹，可能是权限问题\n";
      dialogContent += "- 建议使用标准的媒体文件夹如Pictures、Movies或Documents\n";
    }

    if (io.Platform.isIOS) {
      dialogContent += "\n添加完文件后，点击上方的「扫描NipaPlay文件夹」按钮刷新媒体库。";
    } else {
      dialogContent += "\n添加完文件后，点击上方的「添加并扫描文件夹」按钮选择您存放视频的文件夹。";
    }

    BlurDialog.show<void>(
      context: context,
      title: "如何添加视频文件",
      content: dialogContent,
      actions: <Widget>[
        TextButton(
          child: const Text("知道了",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.lightBlueAccent)),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  // 清除自定义存储路径
  Future<void> _clearCustomStoragePath() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后操作。');
      return;
    }

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '重置存储路径',
      content:
          '确定要重置存储路径吗？这将清除您之前设置的自定义路径，并使用系统默认位置。\n\n注意：这不会删除您已添加到媒体库的视频文件。',
      actions: <Widget>[
        TextButton(
          child: Text('取消',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: _foregroundColor(context, 0.7))),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('重置',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      final success = await StorageService.clearCustomStoragePath();
      if (success && mounted) {
        BlurSnackBar.show(context, '存储路径已重置为默认设置');
      } else if (mounted) {
        BlurSnackBar.show(context, '重置存储路径失败');
      }
    }
  }

  // 检查并显示权限状态
  Future<void> _checkAndShowPermissionStatus() async {
    if (!io.Platform.isAndroid) return;

    // 显示加载提示
    if (mounted) {
      BlurSnackBar.show(context, '正在检查权限状态...');
    }

    try {
      // 获取权限状态
      final status = await AndroidStorageHelper.getAllStoragePermissionStatus();
      final int sdkVersion = status['androidVersion'] as int;

      // 构建状态信息
      final StringBuffer content = StringBuffer();
      content.writeln('Android 版本: $sdkVersion');
      content.writeln('基本存储权限: ${status['storage']}');

      if (sdkVersion >= 30) {
        // Android 11+
        content.writeln('\n管理所有文件权限:');
        content.writeln('- 系统API: ${status['manageExternalStorageNative']}');
        content.writeln(
            '- permission_handler: ${status['manageExternalStorage']}');
      }

      if (sdkVersion >= 33) {
        // Android 13+
        content.writeln('\nAndroid 13+ 分类媒体权限:');
        content.writeln('- 照片访问: ${status['mediaImages']}');
        content.writeln('- 视频访问: ${status['mediaVideo']}');
        content.writeln('- 音频访问: ${status['mediaAudio']}');
      }

      // 显示权限状态对话框
      if (mounted) {
        BlurDialog.show<void>(
          context: context,
          title: 'Android存储权限状态',
          content: content.toString(),
          actions: <Widget>[
            TextButton(
              child: Text('关闭',
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: _foregroundColor(context, 0.7))),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('申请权限',
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () async {
                Navigator.of(context).pop();
                await AndroidStorageHelper.requestAllRequiredPermissions();
                // 延迟后再次检查权限状态
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    _checkAndShowPermissionStatus();
                  }
                });
              },
            ),
          ],
        );
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '检查权限状态失败: $e');
      }
    }
  }

  // 新增：用于Android 13+扫描媒体文件夹的方法
  Future<void> _scanAndroidMediaFolders() async {
    try {
      // 请求媒体权限
      await Permission.photos.request();
      await Permission.videos.request();
      await Permission.audio.request();

      bool hasMediaPermissions = await Permission.photos.isGranted &&
          await Permission.videos.isGranted &&
          await Permission.audio.isGranted;

      if (!hasMediaPermissions && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "需要媒体权限",
          content:
              "NipaPlay需要访问媒体文件权限才能扫描视频文件。\n\n请在系统设置中允许NipaPlay访问照片、视频和音频权限。",
          actions: <Widget>[
            TextButton(
              child: Text("稍后再说",
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: _foregroundColor(context, 0.7))),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("打开设置",
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
        return;
      }

      // 显示加载提示
      if (mounted) {
        BlurSnackBar.show(context, '正在扫描视频文件夹，请稍候...');
      }

      // 获取系统媒体文件夹
      final scanService = Provider.of<ScanService>(context, listen: false);
      String? moviesPath;

      // 尝试获取Movies目录路径
      try {
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          String baseDir = externalDirs[0].path;
          baseDir = baseDir.substring(0, baseDir.indexOf('Android'));
          final moviesDir = io.Directory('${baseDir}Movies');

          if (await moviesDir.exists()) {
            moviesPath = moviesDir.path;
            debugPrint('找到Movies目录: $moviesPath');
          }
        }
      } catch (e) {
        debugPrint('无法获取Movies目录: $e');
      }

      // 如果没有找到Movies目录，尝试其他常用媒体目录
      if (moviesPath == null) {
        try {
          final externalDirs = await getExternalStorageDirectories();
          if (externalDirs != null && externalDirs.isNotEmpty) {
            String baseDir = externalDirs[0].path;
            baseDir = baseDir.substring(0, baseDir.indexOf('Android'));

            // 检查DCIM目录
            final dcimDir = io.Directory('${baseDir}DCIM');
            if (await dcimDir.exists()) {
              moviesPath = dcimDir.path;
              debugPrint('找到DCIM目录: $moviesPath');
            } else {
              // 尝试Download目录
              final downloadDir = io.Directory('${baseDir}Download');
              if (await downloadDir.exists()) {
                moviesPath = downloadDir.path;
                debugPrint('找到Download目录: $moviesPath');
              }
            }
          }
        } catch (e) {
          debugPrint('无法获取备选媒体目录: $e');
        }
      }

      // 如果仍然没有找到任何媒体目录，提示用户
      if (moviesPath == null && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "未找到视频文件夹",
          content: "无法找到系统视频文件夹。建议使用\"管理所有文件\"权限或手动选择文件夹。",
          actions: <Widget>[
            TextButton(
              child: Text("取消",
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: _foregroundColor(context, 0.7))),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("开启完整权限",
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                AndroidStorageHelper.requestManageExternalStoragePermission();
              },
            ),
          ],
        );
        return;
      }

      // 扫描找到的文件夹
      if (moviesPath != null) {
        try {
          // 检查目录权限
          final dirPerms =
              await AndroidStorageHelper.checkDirectoryPermissions(moviesPath);
          if (dirPerms['canRead'] == true) {
            await scanService.startDirectoryScan(moviesPath,
                skipPreviouslyMatchedUnwatched: false);
            if (mounted) {
              BlurSnackBar.show(context, '已扫描视频文件夹: ${p.basename(moviesPath)}');
            }
          } else {
            if (mounted) {
              BlurSnackBar.show(context, '无法读取视频文件夹，请检查权限设置');
            }
          }
        } catch (e) {
          if (mounted) {
            BlurSnackBar.show(context,
                '扫描视频文件夹失败: ${e.toString().substring(0, min(e.toString().length, 50))}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context,
            '扫描视频文件夹时出错: ${e.toString().substring(0, min(e.toString().length, 50))}');
      }
    }
  }

  // 加载保存的排序选项
  Future<void> _loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSortOption = prefs.getInt(_librarySortOptionKey) ?? 0;
      if (mounted) {
        setState(() {
          _sortOption = savedSortOption;
        });
      }
    } catch (e) {
      debugPrint('加载排序选项失败: $e');
    }
  }

  // 保存排序选项
  Future<void> _saveSortOption(int sortOption) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_librarySortOptionKey, sortOption);
    } catch (e) {
      debugPrint('保存排序选项失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            '''媒体文件夹管理功能在Web浏览器中不可用。
此功能需要访问本地文件系统，但Web应用无法获取相关权限。
请在Windows、macOS、Android或iOS客户端中使用此功能。''',
            textAlign: TextAlign.center,
            locale: Locale("zh-Hans", "zh"),
            style:
                TextStyle(color: _foregroundColor(context, 0.7), fontSize: 16),
          ),
        ),
      );
    }

    final scanService = Provider.of<ScanService>(context);
    final appearanceProvider = Provider.of<AppearanceSettingsProvider>(context);
    final bool enableBlur = appearanceProvider.enableWidgetBlurEffect;
    // final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false); // Keep if needed for other actions

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text("媒体文件夹",
                      locale: Locale("zh-Hans", "zh"),
                      style: TextStyle(
                          fontSize: 20,
                          color: _foregroundColor(context),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  // 切换开关：本地文件夹 / WebDAV
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _foregroundColor(context, 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _foregroundColor(context, 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showWebDAVFolders = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: !_showWebDAVFolders
                                  ? _foregroundColor(context, 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '本地',
                              style: TextStyle(
                                color: !_showWebDAVFolders
                                    ? _foregroundColor(context)
                                    : _foregroundColor(context, 0.7),
                                fontSize: 12,
                                fontWeight: !_showWebDAVFolders
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showWebDAVFolders = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _showWebDAVFolders
                                  ? _foregroundColor(context, 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'WebDAV',
                              style: TextStyle(
                                color: _showWebDAVFolders
                                    ? _foregroundColor(context)
                                    : _foregroundColor(context, 0.7),
                                fontSize: 12,
                                fontWeight: _showWebDAVFolders
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // 重置存储路径按钮 - 只在Android平台显示，macOS平台不支持自定义存储路径
                  if (io.Platform.isAndroid)
                    IconButton(
                      icon: Icon(Icons.settings_backup_restore),
                      tooltip: '重置存储路径',
                      color: _foregroundColor(context, 0.7),
                      onPressed: scanService.isScanning
                          ? null
                          : _clearCustomStoragePath,
                    ),
                  if (io.Platform.isAndroid)
                    IconButton(
                      icon: Icon(Icons.security),
                      tooltip: '检查权限状态',
                      color: _foregroundColor(context, 0.7),
                      onPressed: scanService.isScanning
                          ? null
                          : _checkAndShowPermissionStatus,
                    ),
                  IconButton(
                    icon: Icon(Icons.cleaning_services),
                    color: _foregroundColor(context, 0.7),
                    onPressed: scanService.isScanning
                        ? null
                        : () async {
                            final confirm = await BlurDialog.show<bool>(
                              context: context,
                              title: '清理智能扫描缓存',
                              content:
                                  '这将清理所有文件夹的变化检测缓存，下次扫描时将重新检查所有文件夹。\n\n适用于：\n• 怀疑智能扫描遗漏了某些变化\n• 想要强制重新扫描所有文件夹\n\n确定要清理缓存吗？',
                              actions: <Widget>[
                                TextButton(
                                  child: Text('取消',
                                      locale: Locale("zh-Hans", "zh"),
                                      style: TextStyle(
                                          color:
                                              _foregroundColor(context, 0.7))),
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                ),
                                TextButton(
                                  child: const Text('清理',
                                      locale: Locale("zh-Hans", "zh"),
                                      style: TextStyle(
                                          color: Colors.orangeAccent)),
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                ),
                              ],
                            );
                            if (confirm == true) {
                              await scanService.clearAllFolderHashCache();
                              if (mounted) {
                                BlurSnackBar.show(context, '智能扫描缓存已清理');
                              }
                            }
                          },
                  ),
                  IconButton(
                    icon: Icon(Ionicons.refresh_outline),
                    color: _foregroundColor(context, 0.7),
                    onPressed: scanService.isScanning
                        ? null
                        : () async {
                            final confirm = await BlurDialog.show<bool>(
                              context: context,
                              title: '智能刷新确认',
                              content:
                                  '将使用智能扫描技术重新检查所有已添加的媒体文件夹：\n\n• 自动检测文件夹内容变化\n• 只扫描有新增、删除或修改文件的文件夹\n• 跳过无变化的文件夹，大幅提升扫描速度\n• 可选择跳过已匹配且未观看的文件\n\n这可能需要一些时间，但比传统全量扫描快很多。',
                              actions: <Widget>[
                                TextButton(
                                  child: Text('取消',
                                      locale: Locale("zh-Hans", "zh"),
                                      style: TextStyle(
                                          color:
                                              _foregroundColor(context, 0.7))),
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                ),
                                TextButton(
                                  child: const Text('智能刷新',
                                      locale: Locale("zh-Hans", "zh"),
                                      style: TextStyle(
                                          color: Colors.lightBlueAccent)),
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                ),
                              ],
                            );
                            if (confirm == true) {
                              await scanService
                                  .rescanAllFolders(); // skipPreviouslyMatchedUnwatched defaults to true
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              // 左侧按钮：添加本地文件夹
              Expanded(
                child: GlassmorphicContainer(
                  width: double.infinity,
                  height: 50,
                  borderRadius: 12,
                  blur: enableBlur ? 10 : 0,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _foregroundColor(context, 0.15),
                      _foregroundColor(context, 0.05),
                    ],
                  ),
                  borderGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _foregroundColor(context, 0.3),
                      _foregroundColor(context, 0.1),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap:
                          scanService.isScanning ? null : _pickAndScanDirectory,
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: FutureBuilder<bool>(
                          future: io.Platform.isAndroid
                              ? _isAndroid13Plus()
                              : Future.value(false),
                          builder: (context, snapshot) {
                            String buttonText = '添加本地文件夹'; // 默认文本

                            if (io.Platform.isIOS) {
                              buttonText = '扫描NipaPlay文件夹';
                            } else if (io.Platform.isAndroid) {
                              // 如果future完成且为true，说明是Android 13+
                              if (snapshot.hasData && snapshot.data == true) {
                                buttonText = '扫描视频文件夹';
                              } else {
                                buttonText = '添加本地文件夹';
                              }
                            }

                            return Text(
                              buttonText,
                              style: TextStyle(
                                  color: _foregroundColor(context),
                                  fontSize: 16),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12), // 间距

              // 右侧按钮：添加WebDAV服务器
              Expanded(
                child: GlassmorphicContainer(
                  width: double.infinity,
                  height: 50,
                  borderRadius: 12,
                  blur: enableBlur ? 10 : 0,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _foregroundColor(context, 0.15),
                      _foregroundColor(context, 0.05),
                    ],
                  ),
                  borderGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _foregroundColor(context, 0.3),
                      _foregroundColor(context, 0.1),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: scanService.isScanning
                          ? null
                          : _showWebDAVConnectionDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: const Center(
                        child: Text(
                          '添加WebDAV服务器',
                          style: TextStyle(
                              color: _foregroundColor(context), fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (scanService.isScanning || scanService.scanMessage.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scanService.scanMessage,
                    style: TextStyle(color: _foregroundColor(context, 0.7))),
                if (scanService.isScanning && scanService.scanProgress > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: LinearProgressIndicator(
                      value: scanService.scanProgress,
                      backgroundColor: Colors.grey[700],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.lightBlueAccent),
                    ),
                  ),
              ],
            ),
          ),
        // 显示启动时检测到的变化
        if (scanService.detectedChanges.isNotEmpty && !scanService.isScanning)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: GlassmorphicContainer(
              width: double.infinity,
              height: 50,
              borderRadius: 12,
              blur: enableBlur ? 10 : 0,
              alignment: Alignment.centerLeft,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withOpacity(0.15),
                  Colors.orange.withOpacity(0.05),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withOpacity(0.3),
                  Colors.orange.withOpacity(0.1),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notification_important,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "检测到文件夹变化",
                          locale: Locale("zh-Hans", "zh"),
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => scanService.clearDetectedChanges(),
                          child: Text("忽略",
                              locale: Locale("zh-Hans", "zh"),
                              style: TextStyle(
                                  color: _foregroundColor(context, 0.7))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      scanService.getChangeDetectionSummary(),
                      style: TextStyle(
                          color: _foregroundColor(context, 0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    ...scanService.detectedChanges.map((change) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      change.displayName,
                                      style: TextStyle(
                                          color: _foregroundColor(context),
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      change.changeDescription,
                                      style: TextStyle(
                                          color: _foregroundColor(context, 0.6),
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  // 扫描这个有变化的文件夹
                                  await scanService.startDirectoryScan(
                                      change.folderPath,
                                      skipPreviouslyMatchedUnwatched: false);
                                  if (mounted) {
                                    BlurSnackBar.show(context,
                                        '已开始扫描: ${change.displayName}');
                                  }
                                },
                                child: const Text("扫描",
                                    locale: Locale("zh-Hans", "zh"),
                                    style: TextStyle(
                                        color: Colors.lightBlueAccent)),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              // 扫描所有有变化的文件夹
                              for (final change
                                  in scanService.detectedChanges) {
                                if (change.changeType != 'deleted') {
                                  await scanService.startDirectoryScan(
                                      change.folderPath,
                                      skipPreviouslyMatchedUnwatched: false);
                                }
                              }
                              scanService.clearDetectedChanges();
                              if (mounted) {
                                BlurSnackBar.show(context, '已开始扫描所有有变化的文件夹');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.lightBlueAccent.withOpacity(0.2),
                              foregroundColor: Colors.lightBlueAccent,
                            ),
                            child: const Text("扫描所有变化"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 排序选项按钮
        if (scanService.scannedFolders.isNotEmpty || scanService.isScanning)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text('排序方式：',
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(
                        color: _foregroundColor(context, 0.7), fontSize: 14)),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _showSortOptionsDialog,
                  icon: Icon(Icons.sort,
                      color: _foregroundColor(context), size: 18),
                  label: Text(
                    [
                      '文件名 (A→Z)',
                      '文件名 (Z→A)',
                      '修改时间 (旧→新)',
                      '修改时间 (新→旧)',
                      '文件大小 (小→大)',
                      '文件大小 (大→小)',
                    ][_sortOption],
                    style: TextStyle(
                        color: _foregroundColor(context), fontSize: 14),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _showWebDAVFolders
              ? _buildWebDAVFoldersList()
              : (scanService.scannedFolders.isEmpty && !scanService.isScanning
                  ? const Center(
                      child: Text('尚未添加任何扫描文件夹。\n点击上方按钮添加。',
                          textAlign: TextAlign.center,
                          locale: Locale("zh-Hans", "zh"),
                          style:
                              TextStyle(color: _foregroundColor(context, 0.7))))
                  : _buildResponsiveFolderList(scanService)),
        ),
      ],
    );
  }

  // 显示手动匹配弹幕对话框
  Future<void> _showManualDanmakuMatchDialog(
      String filePath, String fileName, WatchHistoryItem? historyItem) async {
    try {
      // 使用文件名作为初始搜索关键词
      String initialSearchKeyword = fileName;

      // 如果有历史记录，优先使用动画名称
      if (historyItem != null && historyItem.animeName.isNotEmpty) {
        initialSearchKeyword = historyItem.animeName;
      } else {
        // 从文件名中提取可能的动画名称（去掉扩展名和可能的集数信息）
        String baseName = p.basenameWithoutExtension(fileName);
        // 简单的清理逻辑：移除可能的集数标识
        baseName = baseName.replaceAll(RegExp(r'第?\d+[话集期]?'), '').trim();
        baseName = baseName.replaceAll(RegExp(r'[Ee]\d+'), '').trim();
        baseName = baseName.replaceAll(RegExp(r'[Ss]\d+[Ee]\d+'), '').trim();
        if (baseName.isNotEmpty) {
          initialSearchKeyword = baseName;
        }
      }

      debugPrint('准备显示手动匹配弹幕对话框：$fileName');
      debugPrint('初始搜索关键词：$initialSearchKeyword');

      // 调用手动匹配弹幕对话框
      final result = await ManualDanmakuMatcher.instance.showManualMatchDialog(
        context,
        initialVideoTitle: initialSearchKeyword,
      );

      if (result != null && mounted) {
        final episodeId = result['episodeId']?.toString() ?? '';
        final animeId = result['animeId']?.toString() ?? '';
        final animeTitle = result['animeTitle']?.toString() ?? '';
        final episodeTitle = result['episodeTitle']?.toString() ?? '';

        if (episodeId.isNotEmpty && animeId.isNotEmpty) {
          try {
            // 获取现有历史记录
            final existingHistory =
                await WatchHistoryManager.getHistoryItem(filePath);

            // 创建更新后的历史记录
            final updatedHistory = WatchHistoryItem(
              filePath: filePath,
              animeName: animeTitle.isNotEmpty
                  ? animeTitle
                  : (existingHistory?.animeName ??
                      p.basenameWithoutExtension(fileName)),
              episodeTitle: episodeTitle.isNotEmpty
                  ? episodeTitle
                  : existingHistory?.episodeTitle,
              episodeId: int.tryParse(episodeId),
              animeId: int.tryParse(animeId),
              watchProgress: existingHistory?.watchProgress ?? 0.0,
              lastPosition: existingHistory?.lastPosition ?? 0,
              duration: existingHistory?.duration ?? 0,
              lastWatchTime: DateTime.now(),
              thumbnailPath: existingHistory?.thumbnailPath,
              isFromScan: existingHistory?.isFromScan ?? false,
              videoHash: existingHistory?.videoHash,
            );

            // 保存更新后的历史记录
            await WatchHistoryManager.addOrUpdateHistory(updatedHistory);

            debugPrint('✅ 成功更新弹幕匹配信息：');
            debugPrint('   文件：$fileName');
            debugPrint('   动画：$animeTitle');
            debugPrint('   集数：$episodeTitle');
            debugPrint('   动画ID：$animeId');
            debugPrint('   集数ID：$episodeId');

            // 显示成功提示
            if (mounted) {
              BlurSnackBar.show(context, '弹幕匹配成功：$animeTitle - $episodeTitle');

              // 刷新UI以显示新的动画信息
              setState(() {
                // 清空已展开的文件夹内容，强制重新加载
                _expandedFolderContents.clear();
              });
            }
          } catch (e) {
            debugPrint('❌ 更新弹幕匹配信息失败：$e');
            if (mounted) {
              BlurSnackBar.show(context, '更新弹幕信息失败：$e');
            }
          }
        } else {
          debugPrint('⚠️ 弹幕匹配结果缺少必要信息');
          if (mounted) {
            BlurSnackBar.show(context, '弹幕匹配结果无效');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ 显示手动匹配弹幕对话框失败：$e');
      if (mounted) {
        BlurSnackBar.show(context, '打开弹幕匹配对话框失败：$e');
      }
    }
  }

  // 显示移除扫描结果确认对话框
  Future<void> _showRemoveScanResultDialog(
      String filePath, String fileName, WatchHistoryItem? historyItem) async {
    if (historyItem == null) return;

    // 构建当前的动画信息描述
    String currentInfo = '';
    if (historyItem.animeName.isNotEmpty) {
      currentInfo += '动画：${historyItem.animeName}';
    }
    if (historyItem.episodeTitle != null &&
        historyItem.episodeTitle!.isNotEmpty) {
      if (currentInfo.isNotEmpty) currentInfo += '\n';
      currentInfo += '集数：${historyItem.episodeTitle}';
    }
    if (historyItem.animeId != null) {
      if (currentInfo.isNotEmpty) currentInfo += '\n';
      currentInfo += '动画ID：${historyItem.animeId}';
    }
    if (historyItem.episodeId != null) {
      if (currentInfo.isNotEmpty) currentInfo += '\n';
      currentInfo += '集数ID：${historyItem.episodeId}';
    }

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '移除扫描结果',
      content:
          '确定要移除文件 "$fileName" 的扫描结果吗？\n\n当前扫描信息：\n$currentInfo\n\n移除后将清除动画名称、集数信息和弹幕ID，但保留观看进度。',
      actions: <Widget>[
        TextButton(
          child: Text('取消',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: _foregroundColor(context, 0.7))),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('移除',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      try {
        // 创建清除了扫描信息的历史记录
        final clearedHistory = WatchHistoryItem(
          filePath: filePath,
          animeName: p.basenameWithoutExtension(fileName), // 恢复为文件名
          episodeTitle: null, // 清除集数标题
          episodeId: null, // 清除集数ID
          animeId: null, // 清除动画ID
          watchProgress: historyItem.watchProgress, // 保留观看进度
          lastPosition: historyItem.lastPosition, // 保留观看位置
          duration: historyItem.duration, // 保留时长
          lastWatchTime: DateTime.now(), // 更新最后操作时间
          thumbnailPath: historyItem.thumbnailPath, // 保留缩略图
          isFromScan: false, // 标记为非扫描结果
          videoHash: historyItem.videoHash, // 保留视频哈希
        );

        // 保存更新后的历史记录
        await WatchHistoryManager.addOrUpdateHistory(clearedHistory);

        debugPrint('✅ 成功移除扫描结果：$fileName');

        // 显示成功提示
        if (mounted) {
          BlurSnackBar.show(context, '已移除 "$fileName" 的扫描结果');

          // 刷新UI
          setState(() {
            // 清空已展开的文件夹内容，强制重新加载
            _expandedFolderContents.clear();
          });
        }
      } catch (e) {
        debugPrint('❌ 移除扫描结果失败：$e');
        if (mounted) {
          BlurSnackBar.show(context, '移除扫描结果失败：$e');
        }
      }
    }
  }

  // 响应式文件夹列表构建方法
  Widget _buildResponsiveFolderList(ScanService scanService) {
    // 对根文件夹进行排序
    final sortedFolders = _sortFolderPaths(scanService.scannedFolders);

    // 检测是否为手机设备 - 手机设备始终使用单列布局
    if (isPhone) {
      // 手机设备使用单列ListView（包括平板，因为平板只能扫描应用目录，文件夹有限）
      if (io.Platform.isAndroid || io.Platform.isIOS) {
        return ListView.builder(
          controller: _listScrollController,
          itemCount: sortedFolders.length,
          itemBuilder: (context, index) {
            final folderPath = sortedFolders[index];
            return _buildFolderTile(folderPath, scanService);
          },
        );
      } else {
        return Scrollbar(
          controller: _listScrollController,
          radius: const Radius.circular(2),
          thickness: 4,
          child: ListView.builder(
            controller: _listScrollController,
            itemCount: sortedFolders.length,
            itemBuilder: (context, index) {
              final folderPath = sortedFolders[index];
              return _buildFolderTile(folderPath, scanService);
            },
          ),
        );
      }
    } else {
      // 桌面设备使用真正的瀑布流布局
      return Scrollbar(
        controller: _listScrollController,
        radius: const Radius.circular(2),
        thickness: 4,
        child: SingleChildScrollView(
          controller: _listScrollController,
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _buildWaterfallLayout(
                scanService,
                sortedFolders,
                constraints.maxWidth,
                300.0,
                16.0,
              );
            },
          ),
        ),
      );
    }
  }

  // 真正的瀑布流布局组件
  Widget _buildWaterfallLayout(
      ScanService scanService,
      List<String> sortedFolders,
      double maxWidth,
      double minItemWidth,
      double spacing) {
    // 预留边距防止溢出
    final availableWidth = maxWidth - 16.0; // 留出16px的安全边距

    // 计算列数
    final crossAxisCount = (availableWidth / minItemWidth).floor().clamp(1, 3);

    // 重新计算间距和项目宽度
    final totalSpacing = spacing * (crossAxisCount - 1);
    final itemWidth = (availableWidth - totalSpacing) / crossAxisCount;

    // 创建列的文件夹列表
    final columnFolders = <List<String>>[];
    for (var i = 0; i < crossAxisCount; i++) {
      columnFolders.add([]);
    }

    // 按列分配已排序的文件夹
    for (var i = 0; i < sortedFolders.length; i++) {
      final columnIndex = i % crossAxisCount;
      columnFolders[columnIndex].add(sortedFolders[i]);
    }

    // 创建列组件
    final columnWidgets = <Widget>[];
    for (var i = 0; i < crossAxisCount; i++) {
      if (columnFolders[i].isNotEmpty) {
        columnWidgets.add(
          SizedBox(
            width: itemWidth,
            child: Column(
              children: columnFolders[i].map((folderPath) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildFolderTile(folderPath, scanService),
                );
              }).toList(),
            ),
          ),
        );
      }
    }

    // 使用Row排列列，添加间距
    final rowChildren = <Widget>[];
    for (var i = 0; i < columnWidgets.length; i++) {
      if (i > 0) {
        rowChildren.add(SizedBox(width: spacing)); // 添加列间距
      }
      rowChildren.add(columnWidgets[i]);
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowChildren,
        ),
      ),
    );
  }

  // 获取显示用的文件夹路径（iOS使用相对路径，其他平台使用绝对路径）
  Future<String> _getDisplayPath(String folderPath) async {
    if (io.Platform.isIOS) {
      try {
        final appDir = await StorageService.getAppStorageDirectory();
        final appPath = appDir.path;

        // 如果路径在应用目录下，显示相对路径
        if (folderPath.startsWith(appPath)) {
          String relativePath = folderPath.substring(appPath.length);
          // 移除开头的斜杠
          if (relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1);
          }
          // 如果是空字符串，表示是根目录
          if (relativePath.isEmpty) {
            return '应用根目录';
          }
          return '~/$relativePath';
        }
      } catch (e) {
        debugPrint('获取相对路径失败: $e');
      }
    }

    // 其他平台或获取相对路径失败时，返回完整路径
    return folderPath;
  }

  // 统一的文件夹Tile构建方法
  Widget _buildFolderTile(String folderPath, ScanService scanService) {
    return FutureBuilder<String>(
      future: _getDisplayPath(folderPath),
      builder: (context, snapshot) {
        final displayPath = snapshot.data ?? folderPath;

        return Container(
          decoration: BoxDecoration(
            color: _foregroundColor(context, 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _foregroundColor(context, 0.1),
              width: 0.5,
            ),
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>(folderPath),
            leading: Icon(Icons.folder_open_outlined,
                color: _foregroundColor(context, 0.7)),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(folderPath),
                    style: TextStyle(
                        color: _foregroundColor(context), fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                displayPath,
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(
                    color: _foregroundColor(context, 0.6), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: _foregroundColor(context), size: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  constraints: const BoxConstraints(),
                  onPressed: scanService.isScanning
                      ? null
                      : () => _handleRemoveFolder(folderPath),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      color: _foregroundColor(context), size: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  constraints: const BoxConstraints(),
                  onPressed: scanService.isScanning
                      ? null
                      : () async {
                          if (scanService.isScanning) {
                            BlurSnackBar.show(context, '已有扫描任务在进行中。');
                            return;
                          }
                          final confirm = await BlurDialog.show<bool>(
                            context: context,
                            title: '确认扫描',
                            content:
                                '将对文件夹 "${p.basename(folderPath)}" 进行智能扫描：\n\n• 检测文件夹内容是否有变化\n• 如无变化将快速跳过\n• 如有变化将进行全面扫描\n\n开始扫描？',
                            actions: <Widget>[
                              TextButton(
                                child: Text('取消',
                                    locale: Locale("zh-Hans", "zh"),
                                    style: TextStyle(
                                        color: _foregroundColor(context, 0.7))),
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                              ),
                              TextButton(
                                child: const Text('扫描',
                                    locale: Locale("zh-Hans", "zh"),
                                    style: TextStyle(
                                        color: Colors.lightBlueAccent)),
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                              ),
                            ],
                          );
                          if (confirm == true) {
                            await scanService.startDirectoryScan(folderPath,
                                skipPreviouslyMatchedUnwatched: false);
                            if (mounted) {
                              BlurSnackBar.show(context,
                                  '已开始智能扫描: ${p.basename(folderPath)}');
                            }
                          }
                        },
                ),
              ],
            ),
            onExpansionChanged: (isExpanded) {
              if (isExpanded &&
                  _expandedFolderContents[folderPath] == null &&
                  !_loadingFolders.contains(folderPath)) {
                Future.microtask(() => _loadFolderChildren(folderPath));
              }
            },
            children: _loadingFolders.contains(folderPath)
                ? [
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator()))
                  ]
                : _buildFileSystemNodes(
                    _expandedFolderContents[folderPath] ?? [], folderPath, 1),
          ),
        );
      },
    );
  }

  // 辅助方法：检查是否为Android 13+
  Future<bool> _isAndroid13Plus() async {
    if (!io.Platform.isAndroid) return false;
    final int sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
    return sdkVersion >= 33;
  }

  // 构建WebDAV文件夹列表
  Widget _buildWebDAVFoldersList() {
    if (_webdavConnections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off,
                  size: 64, color: _foregroundColor(context, 0.54)),
              SizedBox(height: 16),
              Text(
                '尚未添加任何WebDAV服务器。\n点击上方"添加WebDAV服务器"按钮开始。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _foregroundColor(context, 0.7), fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _webdavConnections.length,
      itemBuilder: (context, index) {
        final connection = _webdavConnections[index];
        return _buildWebDAVConnectionTile(connection);
      },
    );
  }

  // 构建WebDAV连接Tile
  Widget _buildWebDAVConnectionTile(WebDAVConnection connection) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _foregroundColor(context, 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _foregroundColor(context, 0.3),
          width: 1,
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('webdav_${connection.name}'),
        leading: Icon(
          Icons.cloud,
          color: _foregroundColor(context),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                connection.name,
                style:
                    TextStyle(color: _foregroundColor(context), fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _foregroundColor(context, 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                connection.isConnected ? '已连接' : '未连接',
                style: TextStyle(
                  color: _foregroundColor(context),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            connection.url,
            style:
                TextStyle(color: _foregroundColor(context, 0.6), fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit,
                  color: _foregroundColor(context, 0.7), size: 20),
              onPressed: () => _editWebDAVConnection(connection),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: _foregroundColor(context, 0.7), size: 20),
              onPressed: () => _removeWebDAVConnection(connection),
            ),
            IconButton(
              icon: Icon(Icons.refresh,
                  color: _foregroundColor(context, 0.7), size: 20),
              onPressed: () => _testWebDAVConnection(connection),
            ),
          ],
        ),
        onExpansionChanged: (isExpanded) {
          if (isExpanded && connection.isConnected) {
            _loadWebDAVFolderChildren(connection, '/');
          }
        },
        children: connection.isConnected
            ? _buildWebDAVFileNodes(connection, '/')
            : [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '连接未建立，无法浏览文件。请点击刷新按钮重新连接。',
                    style: TextStyle(color: _foregroundColor(context, 0.54)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
      ),
    );
  }

  // 构建WebDAV文件节点
  List<Widget> _buildWebDAVFileNodes(WebDAVConnection connection, String path) {
    final key = '${connection.name}:$path';
    final files = _webdavFolderContents[key] ?? [];

    if (_loadingWebDAVFolders.contains(key)) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }

    if (files.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '文件夹为空或无法访问',
            style: TextStyle(color: _foregroundColor(context, 0.54)),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    return files.map((file) {
      if (file.isDirectory) {
        return Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ExpansionTile(
            key: PageStorageKey<String>('${connection.name}:${file.path}'),
            leading: Icon(Icons.folder_outlined,
                color: _foregroundColor(context, 0.7)),
            title: Text(
              file.name,
              style: TextStyle(color: _foregroundColor(context)),
            ),
            trailing: TextButton(
              onPressed: () =>
                  _scanWebDAVFolder(connection, file.path, file.name),
              child: Text(
                '扫描',
                style: TextStyle(color: _foregroundColor(context)),
              ),
            ),
            onExpansionChanged: (isExpanded) {
              if (isExpanded) {
                _loadWebDAVFolderChildren(connection, file.path);
              }
            },
            children: _buildWebDAVFileNodes(connection, file.path),
          ),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.only(left: 32.0),
          child: ListTile(
            leading:
                Icon(Icons.videocam_outlined, color: _foregroundColor(context)),
            title: Text(
              file.name,
              style: TextStyle(color: _foregroundColor(context)),
            ),
            subtitle: file.size != null
                ? Text(
                    '${(file.size! / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: TextStyle(
                        color: _foregroundColor(context, 0.54), fontSize: 12),
                  )
                : null,
            onTap: () => _playWebDAVFile(connection, file),
          ),
        );
      }
    }).toList();
  }

  // 加载WebDAV文件夹内容
  Future<void> _loadWebDAVFolderChildren(
      WebDAVConnection connection, String path) async {
    final key = '${connection.name}:$path';

    if (_loadingWebDAVFolders.contains(key)) return;

    // 使用Future.microtask延迟setState调用，避免在build过程中调用
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _loadingWebDAVFolders.add(key);
        });
      }
    });

    try {
      final files =
          await WebDAVService.instance.listDirectory(connection, path);
      if (mounted) {
        setState(() {
          _webdavFolderContents[key] = files;
          _loadingWebDAVFolders.remove(key);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingWebDAVFolders.remove(key);
        });
        BlurSnackBar.show(context, '加载WebDAV文件夹失败: $e');
      }
    }
  }

  // 扫描WebDAV文件夹
  Future<void> _scanWebDAVFolder(
      WebDAVConnection connection, String folderPath, String folderName) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '扫描WebDAV文件夹',
      content: '确定要扫描WebDAV文件夹 "$folderName" 吗？\n\n这将把该文件夹中的视频文件添加到媒体库中。',
      actions: [
        TextButton(
          child: Text('取消',
              style: TextStyle(color: _foregroundColor(context, 0.7))),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: Text('扫描', style: TextStyle(color: _foregroundColor(context))),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm == true && mounted) {
      try {
        // 递归获取文件夹中的所有视频文件
        final files = await _getWebDAVVideoFiles(connection, folderPath);

        // 将视频文件添加到媒体库
        for (final file in files) {
          final fileUrl =
              WebDAVService.instance.getFileUrl(connection, file.path);
          final historyItem = WatchHistoryItem(
            filePath: fileUrl,
            animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''), // 移除扩展名
            episodeTitle: '',
            duration: 0,
            lastPosition: 0,
            watchProgress: 0.0,
            lastWatchTime: DateTime.now(),
            isFromScan: true,
          );

          await WatchHistoryManager.addOrUpdateHistory(historyItem);
        }

        if (mounted) {
          BlurSnackBar.show(context, '已添加 ${files.length} 个视频文件到媒体库');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '扫描WebDAV文件夹失败: $e');
        }
      }
    }
  }

  // 递归获取WebDAV文件夹中的视频文件
  Future<List<WebDAVFile>> _getWebDAVVideoFiles(
      WebDAVConnection connection, String folderPath) async {
    final List<WebDAVFile> videoFiles = [];

    try {
      final files =
          await WebDAVService.instance.listDirectory(connection, folderPath);

      for (final file in files) {
        if (file.isDirectory) {
          // 递归获取子文件夹中的视频文件
          final subFiles = await _getWebDAVVideoFiles(connection, file.path);
          videoFiles.addAll(subFiles);
        } else {
          // 检查是否为视频文件
          if (WebDAVService.instance.isVideoFile(file.name)) {
            videoFiles.add(file);
          }
        }
      }
    } catch (e) {
      print('获取WebDAV视频文件失败: $e');
    }

    return videoFiles;
  }

  // 播放WebDAV文件
  void _playWebDAVFile(WebDAVConnection connection, WebDAVFile file) {
    final fileUrl = WebDAVService.instance.getFileUrl(connection, file.path);
    final historyItem = WatchHistoryItem(
      filePath: fileUrl,
      animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''), // 移除扩展名
      episodeTitle: '',
      duration: 0,
      lastPosition: 0,
      watchProgress: 0.0,
      lastWatchTime: DateTime.now(),
    );

    widget.onPlayEpisode(historyItem);
  }

  // 编辑WebDAV连接
  Future<void> _editWebDAVConnection(WebDAVConnection connection) async {
    final result =
        await WebDAVConnectionDialog.show(context, editConnection: connection);
    if (result == true && mounted) {
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
      });
      BlurSnackBar.show(context, 'WebDAV连接已更新');
    }
  }

  // 删除WebDAV连接
  Future<void> _removeWebDAVConnection(WebDAVConnection connection) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '删除WebDAV连接',
      content: '确定要删除WebDAV连接 "${connection.name}" 吗？',
      actions: [
        TextButton(
          child: Text('取消',
              style: TextStyle(color: _foregroundColor(context, 0.7))),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm == true && mounted) {
      await WebDAVService.instance.removeConnection(connection.name);
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
        // 清理相关的文件夹内容缓存
        _webdavFolderContents
            .removeWhere((key, value) => key.startsWith('${connection.name}:'));
      });
      BlurSnackBar.show(context, 'WebDAV连接已删除');
    }
  }

  // 测试WebDAV连接
  Future<void> _testWebDAVConnection(WebDAVConnection connection) async {
    try {
      BlurSnackBar.show(context, '正在测试连接...');
      await WebDAVService.instance.updateConnectionStatus(connection.name);

      if (mounted) {
        setState(() {
          _webdavConnections = WebDAVService.instance.connections;
        });

        final updatedConnection =
            WebDAVService.instance.getConnection(connection.name);
        if (updatedConnection?.isConnected == true) {
          BlurSnackBar.show(context, '连接测试成功！');
        } else {
          BlurSnackBar.show(context, '连接测试失败');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '连接测试失败: $e');
      }
    }
  }
}
