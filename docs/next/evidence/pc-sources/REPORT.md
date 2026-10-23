# S 线交付与验收报告

基于 `bf209633`，工作树 `pc-sources`，分支 `next/pc-sources`。按 common.md、S.md 和设计 §7 P5 实现；未 push、未派代理、未改主工作树。依赖已初始化：`media-kit-upstream` 为 `7a2135661ff37a717f11d6012fefa56cae27ef36`，Flutter 3.44.6 的 pub get 成功。

## 交付与证据

| 交付 | 实现及验证 | 证据 |
|---|---|---|
| Jellyfin、Emby | 共用数据客户端，逐会话解析播放地址、版本和轨道；支持清晰度、转码及保位重开。真实容器播放，seek 到 52 秒，选第二音轨后原生 `activeAudio=[1]`；1 Mbps 转码后仍有画面 | `operations-all_sources.json`、`jellyfin-audio-seek.png`、`jellyfin-transcode.png`、`emby-audio-seek.png`、`emby-transcode.png` |
| 远端进度和转码清理 | playing 时按真实 5 秒间隔报告，seek/pause/end/close 推送；逐会话捕获地址、认证和 DeviceId/PlaySessionId。关闭发送最终 Stopped 并停止转码 | 同上 progress comparison、transcoders after close；`sources_test.dart` 的 HTTP 心跳和反代清理回归 |
| WebDAV、SMB | 稳定 locator 保存续播，临时 HTTP 地址只用于本次内核。真实容器播放、seek 53 秒、关闭重开 | `operations-all_sources.json`、`webdav-seek.png`、`smb-seek.png` |
| 弹弹play 远程 | 复用远程访问数据客户端，支持 hash/id 稳定 locator；每次重新生成地址，剧集 loader 转回稳定路径 | `sources_test.dart` 的 hash/id 解析回归；本次未连外部真实弹弹play 主机 |
| NipaPlay 共享库 | 接收原有共享 HTTP 流和数据层剧集上下文；复用共享库进度同步服务 | Classic 共享连接 12 项补充回归；本次未部署独立共享库主机实播 |
| Mesh | 每次稳定剧集打开重新取得直连地址与资源包；逐会话进度事件同步对端。双真实实例、独立身份、认证 TLS；跳过中点后有画面，上一集/下一集生成新内核，播放列表索引正确 | `operations-mesh.json`、`mesh-peer-seek.png`；资源包包含对端 SRT/XML |
| 剧集与播完动作 | 列表、当前索引、上一集/下一集、暂停、重播、退出、下一集倒计时及取消；结束事件去重、过期列表与解析结果不能复活关闭会话 | `operations-endings.json`、`operations-transcode_endings.json`、`operations-transcode_loop.json`、`transcode-end-*.png`；`sources_test.dart` |
| EOF 时钟 | 明确结束事件将时钟固定到已知终点，忽略结束后的 native 归零样本；未知时长冻结最后位置，显式 seek 后重新接收样本 | `session_test.dart` 新增 3 项；转码补验记录 |

能力 ID/schema 保持原有契约：`playback.open/playlist/switch_episode/stream_options/select_stream/cancel_auto_next`。Next 使用独立会话与内核，未调用 Classic 播放器或 `VideoPlayerState`。

## 实测数据

Jellyfin 10.10.7、Emby 4.10.1.0，一次性容器 `nipa-pcs-*`，仅回环端口；两集约 90 秒 Sintel 测试片，两个 AAC 音轨。实验全部先静音，使用 `core-lab-s` / `core-lab-s-peer`。

| 项目 | 实测 |
|---|---:|
| Jellyfin 进度误差（直连 / 转码） | 856 / 259 ms |
| Emby 进度误差（直连 / 转码） | 299.005 / 256.388 ms |
| Jellyfin 清晰度重开位置变化 | 58,778 → 59,979 ms，差 1,201 ms |
| Emby 清晰度重开位置变化 | 58,153 → 59,933 ms，差 1,780 ms |
| Jellyfin / Emby 关闭后 ffmpeg | 0 / 0，分别等待 444 / 39 ms |
| WebDAV 续播 | 52,987 → 52,969 ms，差 18 ms |
| SMB 续播 | 52,997 → 53,194 ms，差 197 ms |

以上服务端进度均满足 ±10 秒。`operations-all_sources.json` 的来源部分已通过；该轮随后发现转码 EOF 时位置归零（334 ms），因此整轮并非全部成功。保留失败现场，修复提交 `998e194f5` 后单独复验转码播完动作，不用原画通过结果代替转码结果。

修复后的 HLS 转码补验：暂停停在 90,084 ms；重播从零恢复并持续前进至 12,108 ms，原生位置 12,102 ms，截图看到重新播放的片头；退出后没有视频；4 秒倒计时进入 E02；取消后仍为 E01、暂停且位置 90,084 ms。对应截图已人工核对。

最终 Mesh 验收先经公开 `media.library.progress` 把进度置零，等待对端确实观测到 0，再实播并 seek 54 秒。对端更新到 `0.6252386661`（约 56,324 ms），本地 56,324 ms；排除了旧记录误通过。`ui.open` 返回 `interface=next`。上一集/下一集使用内核实例 1 → 2 → 3，列表索引 0 → 1 → 0。

性能：与全量测试同时运行的短窗口曾记录 `mdk.state` p99 2.375 ms、`mdk.sample` p99 2.287 ms，原始 JSON 保留。全量测试完成后的独立转码重播实验，所有已采集 span 的 p99/max ≤ 0.914 ms。另按 P1 的 B1 稳态量尺采集 60 秒转码播放，再做 5 组暂停/恢复及关闭：

| 项目 | 最终独立窗口 |
|---|---:|
| 真实连续播放位置 | 11,910 → 71,916 ms，前进 60,006 ms |
| 统计窗口（含控件动作和关闭） | 62,168 ms |
| `mdk.sample` 241 次 | p99 70 µs，最大 141 µs |
| `session.kernel` 20 次 | p99/最大 209 µs |
| 所有 span 中最高 p99/最大 | 273 µs（`mdk.state`） |
| 播放层占主线程 | 0.02145% |

数据见 `operations-performance.json`，实播截图 `transcode-sustained.png` 已核对。未改探针或预算阈值。所有实验的 `main isolate blocked` 均为空，结束前公开能力仍正常应答，前台 ASN 前后相同。窗口未自然可见，帧耗时未测，不能据此声称帧预算已测得。

## 验证命令

测试前均清除 `HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy`。构建及全量测试使用 `mac-heavy.lock`，实例实验整段使用 `mac-lab.lock`。

```sh
lockf -k "$HOME/.nipa-next/mac-heavy.lock" zsh -c '
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy
  ~/development/flutter-3.44.6/bin/flutter test --no-pub --concurrency=1 test/next'
```

最终代码结果：`05:46 +1242 ~7: All tests passed!`，进程退出 0，包含 main_thread_budget 和新增 EOF/interface 回归。此前完整串行结果为 `05:40 +1238 ~7: All tests passed!`。最初并行全量遇到预算测试 idle 85.1 ms 超过 60 ms；未改测试或阈值，单文件复测和完整串行均通过。

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/media_source_utils_test.dart \
  test/media_server_playlist_loader_test.dart \
  test/media_server_detail_playback_navigation_test.dart \
  test/media_server_playback_sync_user_agent_test.dart \
  test/playback_position_store_test.dart \
  test/emby_media_source_selection_test.dart
# +42: All tests passed!
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/shared_remote_library_connection_test.dart test/smb_proxy_startup_test.dart
# +12: All tests passed!
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/player/session_test.dart test/next/player/sources_test.dart
# 00:07 +30: All tests passed!
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/player/source_ui_open_test.dart
# 00:00 +1: All tests passed!
```

来源/mesh 专项静态分析以及 EOF/interface 改动文件分析均为 `No issues found!`：

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/player/sources lib/next/mesh/playback.dart test/next/player/sources_test.dart
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/player/core/session.dart lib/next/capabilities/ui_open.dart \
  test/next/player/session_test.dart test/next/player/source_ui_open_test.dart
# No issues found!
```

最终构建使用 common.md 指定 Erika 预编译路径、defines、开发签名与 entitlements：

```sh
lockf -k "$HOME/.nipa-next/mac-heavy.lock" zsh -c '
  ERIKA_MACOS_CAPI_DYLIB=$HOME/.nipa-next/erika-wt/agent-diagnostics/target/release/liberika_capi.dylib \
  ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
  ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub \
    --dart-define-from-file=$HOME/.nipa-next/defines.json && \
  codesign --force --deep --sign "Apple Development: RONGGUANG LIANG (JB76WG94SN)" \
    --entitlements macos/Runner/DebugProfile.entitlements \
    build/macos/Build/Products/Debug/NipaPlay.app'
# ✓ Built build/macos/Build/Products/Debug/NipaPlay.app
# build/macos/Build/Products/Debug/NipaPlay.app: replacing existing signature
```

实验复现入口：

```sh
python3 docs/next/evidence/pc-sources/prepare_servers.py
lockf -k "$HOME/.nipa-next/mac-lab.lock" zsh docs/next/evidence/pc-sources/experiment.sh all_sources
lockf -k "$HOME/.nipa-next/mac-lab.lock" zsh docs/next/evidence/pc-sources/experiment.sh transcode_endings
lockf -k "$HOME/.nipa-next/mac-lab.lock" zsh docs/next/evidence/pc-sources/experiment.sh transcode_loop
lockf -k "$HOME/.nipa-next/mac-lab.lock" zsh docs/next/evidence/pc-sources/experiment.sh performance
lockf -k "$HOME/.nipa-next/mac-lab.lock" zsh docs/next/evidence/pc-sources/mesh_experiment.sh
```

Mesh 脚本需要已编译的本仓库协调器 debug binary；使用回环测试网关和 synthetic JWT，未触及真实账号。仅在实例停止时准备两个本线 profile 的数据库；运行期间通过公开能力查询。截图全部由 profile harness 的 `ui.capture` 取得并人工核对；未置顶、移动、缩放、抢前台或做全屏截图。原始日志与凭据仅留 `.dart_tool` / `/tmp`，不提交；归档 JSON 已清除测试密码、token 和临时 grant。

## 改动文件与公共接缝

新增来源模块：`lib/next/player/sources/{resolver,playback_sources,server_progress,progress,auto_next_overlay}.dart`。主要接入：`lib/next/mesh/playback.dart`。回归：`test/next/player/{sources_test,session_playback_test,session_test,source_ui_open_test}.dart`。文档与实验材料全部位于本目录。

公共文件的增量清单（供主控合并）：

| 文件 | 增量 |
|---|---|
| `lib/next/player/core/host.dart` | 接受网络 scheme；可传 `resolvedSource` 和 `onCreated`，保留每会话新内核 |
| `lib/next/player/core/session.dart` | 网络来源不做本地存在性检查；`closeSource` 收尾钩子；关闭冻结时钟；EOF 固定终点并拒绝晚到样本。原生释放栅栏与拆除顺序未改 |
| `lib/next/player/kernel/driver.dart` | `ResolvedSource` 可带 direct 路由及服务端映射后的轨道/外挂字幕打开参数 |
| `lib/next/player/kernel/mdk_driver.dart` | 新实例 prepare 后选指定轨道，再恢复起点；direct 来源禁代理；不在停止或释放中切轨 |
| `lib/next/player/ports/session_playback.dart` | 挂载来源控制器，打开、关闭、剧集导航及流选择转交；服务端轨道及诊断事实 |
| `lib/next/player/ports/session_ports.dart` | playlist、streams、server tracks、前后集和 autoNext 事实与动作 |
| `lib/next/next_runtime.dart` | 注入带 BuildContext 的数据层来源解析器 |
| `lib/next/ui/player/player_layer.dart` | 倒计时和取消叠层 |
| `lib/next/capabilities/ui_open.dart` | 从观测到的 `state.kernel.layer=next_core` 报告 `interface=next`，显式 interface 优先；另补原有两处 if 的花括号以通过分析 |
| `lib/next/mesh/playback.dart` | 去轮询、订阅会话事件与关闭收尾；稳定编码路径逐次直连；资源包 clone/entries decode 放 isolate，失败不阻塞后续进度写入 |

未提交自动改写的 `pubspec.lock`、`analysis_options.yaml`、GeneratedPluginRegistrant、Podfile.lock。

## 提交与边界

- `c24994c6b`：网络来源会话、剧集控制首个实现节点。
- `45c938ff1`：关闭时作废仍在解析的打开请求。
- `7e55ae896`：稳定网络剧集身份、转码清理与来源回归。
- `998e194f5`：EOF 时钟和 ui.open 界面事实修复。
- 验收归档提交：本报告所在提交（最终回复给出哈希）。

本线没有剩余已知的来源/剧集故障。验证边界：真实播放使用 MDK；Erika、Media Kit、video_player 的驱动实现由 K 线交付，新增 ResolvedSource 参数需按公共清单合并。资源包的直连获取与加载接缝已交付；本基线 P1 的 offersSubtitles/offersDanmaku 为 false，字幕/弹幕最终呈现由 P2/D 接入，本报告不声称已显示。窗口未自然可见，帧耗时未测。

收尾已核对：两个 S 线应用实例和本线协调器均无残留进程；四个本线容器 `nipa-pcs-jellyfin`、`nipa-pcs-emby`、`nipa-pcs-webdav`、`nipa-pcs-smb` 均已停止，未操作其他线的容器。关闭检查归档于 `shutdown.json`。自动改写的 Podfile.lock 已还原，工作树最终检查无空白错误；没有 push。

需要主控决定：无
