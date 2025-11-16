# nipaplay 自研 NipaPlay 内核开发与维护技巧

## 1. 架构概览
- **Rust 核心**：`/Library/Afolder/RustProject/libnipa`，基于 `ffmpeg-sys-next` 实现 H.264 软件解码、BGRA 转换、播放/暂停/位置查询接口，并导出 `nipa_*` C ABI；编译生成 `liblibnipa.{dylib,a}` 供上层调用。
- **Dart FFI 包**：`/Library/Afolder/FlutterProject/libnipa`，通过 `NipaNative` 加载动态库并封装 `NipaSoftDecoder`（open/play/pause/position/nextFrame/close）。
- **Flutter 适配器**：`lib/player_abstraction/nipa_player_adapter.dart` 实现 `AbstractPlayer`，周期性拉取 BGRA 帧并转换为 `ui.Image`，通过 `ValueListenable` 传递给 UI。
- **UI & 设置**：`VideoPlayerUI`、`CupertinoPlayVideoPage` 根据内核类型切换渲染；设置页面新增 “NipaPlay” 选项，仅在 macOS 平台呈现。

## 2. Rust 核心开发技巧
- 推荐使用 `ffmpeg-sys-next` 直接绑定 FFmpeg，这样能手动控制生命周期；若 `pkg-config` 报找不到头文件，确认 `PKG_CONFIG_PATH` 指向 Homebrew 的 FFmpeg（例如 `/opt/homebrew/Cellar/ffmpeg/<version>/lib/pkgconfig`）。
- `AVFormatContext*` 等裸指针需 `unsafe impl Send/Sync` 才能放进 `Arc<Mutex<>>`；Drop 中务必按顺序释放（frame/packet/codec_ctx/format_ctx/sws_ctx），避免内存泄漏。
- `avcodec_receive_frame` 返回 `AVERROR(EAGAIN)` 时要继续读；遇到其他负值视为 EOF，该帧循环返回 `Ok(false)` 让上层停止。
- 构建命令：`cd /Library/Afolder/RustProject/libnipa && PKG_CONFIG_PATH=... cargo build --release`，产物在 `target/release/liblibnipa.dylib`。

## 3. 动态库分发策略
- 构建后的 `.dylib` 复制到两个位置：
  1. `macos/Frameworks/liblibnipa.dylib` 供调试时直接加载。
  2. `libnipa/assets/liblibnipa.dylib` 并在 `libnipa/pubspec.yaml` 的 `flutter.assets` 中声明，这样 `flutter build macos` 会把库打包在 `App.framework/Resources/flutter_assets/packages/libnipa/assets/` 下。
- `NipaNative._open()` 会依次在以下路径查找：环境变量（`LIBLIBNIPA_PATH` / `LIBNIPA_PATH`）→ 当前目录 → Flutter 工程 `macos/Frameworks` → 调试可执行目录 `Runner.app/Contents/Frameworks` → Flutter assets 目录。找不到时抛出包含所有候选路径的异常方便排查。

## 4. Dart FFI 与 Flutter 适配
- FFI 的签名需严格匹配 C 类型：如 `_DecodeFrameNative = ffi.Int32 Function(Pointer<Uint8>, ffi.IntPtr)`；`malloc<Uint8>(length)` 对应 `ffi`.package。
- `NipaSoftDecoder.nextFrame()` 返回 `NipaVideoFrame`（`width/height` 与 `Uint8List bgra`），`NipaPlayerAdapter` 在 `_startFramePump` 中 33ms 定期拉帧并通过 `ui.decodeImageFromPixels` 转换为 `ui.Image`，注意重复帧时要 `dispose` 上一个 `ui.Image`，以免 GPU 内存泄漏。
- `PlayerFactory` 里新增 `PlayerKernelType.nipaPlay` 时，要同时更新 `PlayerKernelManager`、设置页面描述、`SystemResourceMonitor` 的显示名等；此外仅在 `Platform.isMacOS` 时允许选择 NipaPlay。
- `VideoPlayerState.initializePlayer` 判断 “准备完成” 时，不能只看 `textureId`，还需把 `player.getPlayerKernelName() == 'NipaPlay'` 视为已就绪。

## 5. 调试流程
1. Rust 侧：`cargo build --release` → 将 `liblibnipa.dylib` 复制到 `macos/Frameworks` 和 `libnipa/assets`。
2. Dart 侧：`cd /Library/Afolder/FlutterProject/libnipa && flutter pub get`，然后 `cd ../nipaplay && flutter pub get`。
3. 运行：`flutter run -d macos`，在设置里切换 “播放器内核” 为 “NipaPlay” 并播放本地 H.264 文件验证。
4. 若提示 “未找到 liblibnipa.dylib”，可 `export LIBLIBNIPA_PATH=/absolute/path/to/liblibnipa.dylib` 后重试，或确认 `.app/Contents/Frameworks`/`flutter_assets` 目录中存在该库。

## 6. 常见问题与修复
| 问题 | 解决建议 |
| --- | --- |
| `ffmpeg-next` 与系统 FFmpeg 版本不匹配 | 替换为 `ffmpeg-sys-next` 或安装对应版本的 FFmpeg。 |
| UI 不显示画面 | 检查 `isNipaKernel` 路径是否渲染 `RawImage`，并确认 `_frameStream` 有推送。 |
| 设置项无效或崩溃 | 仅在 macOS 暴露 NipaPlay 选项；`PlayerFactory.saveKernelType` 对不支持的平台回退到默认。 |
| Flutter 打包后库丢失 | 确保 `libnipa` 的 assets 包含 `.dylib`，或在 Xcode Build Phases 添加 Copy Files → Frameworks，手动把库复制到 `.app/Contents/Frameworks`。 |
| 解码 CPU 占用高 | 适当降低 `_framePumpTimer` 频率或在 `NipaPlayerAdapter` 中做帧率调度；必要时可考虑后续实现 Metal 纹理渲染或硬解。 |

## 7. 发布注意
- `flutter build macos` 后，确认 `./build/macos/Build/Products/Release/nipaplay.app/Contents/Frameworks` 下存在 `liblibnipa.dylib`，以及 `App.framework/Resources/flutter_assets/packages/libnipa/assets/liblibnipa.dylib`。
- 如需自动化，可在 `macos/Runner.xcodeproj` 的 `post_install` 脚本中增加：
  ```ruby
  target.build_phases.each do |phase|
    next unless phase.display_name == 'Copy Files'
    # 确保 liblibnipa.dylib 被复制到 Frameworks
  end
  ```
- 版本升级时：先更新 Rust 依赖→重新编译→覆盖 `libnipa/assets/liblibnipa.dylib`→`flutter pub get`→`flutter run` 验证。

以上内容涵盖了 nipaplay 自研 NipaPlay 内核在开发、调试、部署过程中的关键经验，后续维护可参考此文档逐项检查。
