import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:path_provider/path_provider.dart';

class LibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const LibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<LibraryManagementTab> createState() => _LibraryManagementTabState();
}

class _LibraryManagementTabState extends State<LibraryManagementTab> {
  static const String _lastScannedDirectoryPickerPathKey = 'last_scanned_dir_picker_path';

  final Map<String, List<FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickAndScanDirectory() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后。');
      return;
    }

    String? initialPickerPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      initialPickerPath = prefs.getString(_lastScannedDirectoryPickerPathKey);
    } catch (e) {
      debugPrint("Error loading last scanned directory picker path: $e");
    }

    String? selectedDirectory;
    try {
      selectedDirectory = await FilePicker.platform.getDirectoryPath(
        initialDirectory: initialPickerPath,
      );
    } catch (e) {
      debugPrint("FilePicker error: $e");
      if (mounted) {
        scanService.updateScanMessage("选择文件夹失败: $e");
      }
      return;
    }

    if (selectedDirectory == null) {
      if (mounted) {
        scanService.updateScanMessage("未选择文件夹。");
      }
      return;
    }

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String appDocPath = appDocDir.path;

    if (!selectedDirectory.startsWith(appDocPath)) {
      if (mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "访问提示",
          content: "您选择的文件夹位于 NipaPlay 应用外部。\n\n为了正常扫描和管理媒体文件，请将文件或文件夹拷贝到 NipaPlay 的专属文件夹中。\n\n您可以在\"文件\"应用中，导航至\"我的 iPhone / iPad\" > \"NipaPlay\"找到此文件夹。\n\n这是由于iOS系统的安全和权限机制，确保应用仅能访问您明确置于其管理区域内的数据。",
          actions: <Widget>[
            TextButton(
              child: const Text("知道了", style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      String pathToSave = selectedDirectory;
      try {
        // Check if the selected directory is not the root of the filesystem
        // For example, on Linux/macOS, root is '/', on Windows it might be 'C:\'
        // Directory('.').parent.path on root might give the root itself or error,
        // so we explicitly check if parent is different.
        final Directory parentDir = Directory(selectedDirectory).parent;
        if (parentDir.path != selectedDirectory && await parentDir.exists()) { // Ensure parent is different and exists
          pathToSave = parentDir.path;
        }
      } catch (e) {
        debugPrint("Error getting parent directory for $selectedDirectory, or it's a root directory: $e");
        // Fallback to selectedDirectory if parent cannot be determined or is the root
        pathToSave = selectedDirectory;
      }
      await prefs.setString(_lastScannedDirectoryPickerPathKey, pathToSave);
      debugPrint("Saved picker path: $pathToSave (selected: $selectedDirectory)");
    } catch (e) {
      debugPrint("Error saving last scanned directory picker path: $e");
    }

    await scanService.startDirectoryScan(selectedDirectory); // Scan the actually selected directory
  }

  Future<void> _handleRemoveFolder(String folderPathToRemove) async {
    final scanService = Provider.of<ScanService>(context, listen: false);

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '确认移除',
      content: '确定要从列表中移除文件夹 "$folderPathToRemove" 吗？\n相关的媒体记录也会被清理。',
      actions: <Widget>[
        TextButton(
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('移除', style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      debugPrint("User confirmed removal of: $folderPathToRemove");
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

  Future<List<FileSystemEntity>> _getDirectoryContents(String path) async {
    final List<FileSystemEntity> contents = [];
    final directory = Directory(path);
    if (await directory.exists()) {
      try {
        await for (var entity in directory.list(recursive: false, followLinks: false)) {
          if (entity is Directory) {
            contents.add(entity);
          } else if (entity is File) {
            String extension = p.extension(entity.path).toLowerCase();
            if (extension == '.mp4' || extension == '.mkv') {
              contents.add(entity);
            }
          }
        }
      } catch (e) {
        debugPrint("Error listing directory contents for $path: $e");
        if (mounted) {
          setState(() {
            // _scanMessage = "加载文件夹内容失败: $path ($e)";
          });
        }
      }
    }
    contents.sort((a, b) {
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return contents;
  }

  Future<void> _loadFolderChildren(String folderPath) async {
    if (mounted) {
      setState(() {
        _loadingFolders.add(folderPath);
      });
    }

    final children = await _getDirectoryContents(folderPath);

    if (mounted) {
      setState(() {
        _expandedFolderContents[folderPath] = children;
        _loadingFolders.remove(folderPath);
      });
    }
  }

  List<Widget> _buildFileSystemNodes(List<FileSystemEntity> entities, String parentPath, int depth) {
    if (entities.isEmpty && !_loadingFolders.contains(parentPath)) {
      return [Padding(
        padding: EdgeInsets.only(left: depth * 16.0 + 16.0, top: 8.0, bottom: 8.0),
        child: const Text("文件夹为空", style: TextStyle(color: Colors.white54)),
      )];
    }
    
    return entities.map<Widget>((entity) {
      final indent = EdgeInsets.only(left: depth * 16.0);
      if (entity is Directory) {
        final dirPath = entity.path;
        return Padding(
          padding: indent,
          child: ExpansionTile(
            key: PageStorageKey<String>(dirPath),
            leading: const Icon(Icons.folder_outlined, color: Colors.white70),
            title: Text(p.basename(dirPath), style: const TextStyle(color: Colors.white)),
            onExpansionChanged: (isExpanded) {
              if (isExpanded && _expandedFolderContents[dirPath] == null && !_loadingFolders.contains(dirPath)) {
                _loadFolderChildren(dirPath);
              }
            },
            children: _loadingFolders.contains(dirPath)
                ? [const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))]
                : _buildFileSystemNodes(_expandedFolderContents[dirPath] ?? [], dirPath, depth + 1),
          ),
        );
      } else if (entity is File) {
        return Padding(
          padding: indent,
          child: ListTile(
            leading: const Icon(Icons.videocam_outlined, color: Colors.tealAccent),
            title: Text(p.basename(entity.path), style: const TextStyle(color: Colors.white)),
            onTap: () {
              // Create a minimal WatchHistoryItem to initiate playback
              final WatchHistoryItem tempItem = WatchHistoryItem(
                filePath: entity.path,
                animeName: p.basenameWithoutExtension(entity.path), // Use filename as a basic anime name
                episodeTitle: '', // Can be empty, VideoPlayerState might fill it later
                duration: 0, // Will be updated by VideoPlayerState
                lastPosition: 0, // Will be updated by VideoPlayerState
                watchProgress: 0.0, // Will be updated by VideoPlayerState
                lastWatchTime: DateTime.now(), // Current time, or can be a default
                // thumbnailPath, episodeId, animeId can be null/default initially
              );
              widget.onPlayEpisode(tempItem);
              debugPrint("Tapped on file: ${entity.path}, attempting to play.");
            },
          ),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanService>(
      builder: (context, scanService, child) {
        return Container(
          color: Colors.transparent,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: GlassmorphicContainer(
                  width: double.infinity,
                  height: 50,
                  borderRadius: 12,
                  blur: 10,
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
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickAndScanDirectory,
                      borderRadius: BorderRadius.circular(12),
                      child: const Center(
                        child: Text(
                          '添加并扫描文件夹',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (scanService.isScanning || scanService.scanMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scanService.scanMessage, style: const TextStyle(color: Colors.white70)),
                      if (scanService.isScanning && scanService.scanProgress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: LinearProgressIndicator(
                            value: scanService.scanProgress,
                            backgroundColor: Colors.grey[700],
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: scanService.scannedFolders.isEmpty && !scanService.isScanning
                    ? const Center(child: Text('尚未添加任何扫描文件夹。\n点击上方按钮添加。', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        itemCount: scanService.scannedFolders.length,
                        itemBuilder: (context, index) {
                          final folderPath = scanService.scannedFolders[index];
                          return ExpansionTile(
                            key: PageStorageKey<String>(folderPath),
                            leading: const Icon(Icons.folder_open_outlined, color: Colors.white70),
                            title: Text(p.basename(folderPath), style: const TextStyle(color: Colors.white)),
                            subtitle: Text(folderPath, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              onPressed: () => _handleRemoveFolder(folderPath),
                            ),
                            onExpansionChanged: (isExpanded) {
                              if (isExpanded && _expandedFolderContents[folderPath] == null && !_loadingFolders.contains(folderPath)) {
                                _loadFolderChildren(folderPath);
                              }
                            },
                            children: _loadingFolders.contains(folderPath)
                                ? [const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))]
                                : _buildFileSystemNodes(_expandedFolderContents[folderPath] ?? [], folderPath, 1),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
} 