# X51 静态调研证据

报告：[NEXT_COVERAGE.md](../../research/NEXT_COVERAGE.md)。日期：2026-10-13。基线保存在 `REVISION.txt`。

此目录只记录源代码符号、路径、行号、源码摘要和文档检查结果。没有运行应用、`nipa`、Flutter 构建/测试或线上请求；没有读取用户运行时数据、凭据、日志或认证链接。

## 文件

| 文件 | 用途与范围 |
|---|---|
| `actions.tsv` | GUI 组装的全部 196 个 Action ID，来源位置、无界面注册/过滤情况与 Mesh ID allowlist。无界面注册 89 个；GUI ID 中 158 个在 Mesh 白名单。注册不代表当前宿主实际后端可执行。 |
| `settings_keys.tsv` | SettingsKeys 的全部 80 个常量；每项物理键、实际注册/兼容关系、注册位置、Classic 代码引用。58 个 registered、3 个 compatibility_only、1 个 legacy_api_only、18 个 unregistered。后两类里包含内部状态/秘密/低影响偏好，不能全作为待开放设置。 |
| `settings_storage_calls.tsv` | 非 Next 的 lib 中全部显式 SettingsStorage.load/save 调用，含换行链式调用。只记录键名与引用位置，无值。ThemeNotifier 常量已解析，没有未解决参数。 |
| `registered_settings.tsv` | ApplicationSettings/ClassicSettings/DownloadSettings 中可静态解析的 storageKey → logical setting 映射。不是完整运行时注册表：不执行动态插件/快捷键/循环插值条目，不含 sync/Mesh/NextUiPreference 等独立工厂。用于核对 SettingsKeys 与调用键；报告另读独立工厂和两宿主组装。 |
| `source_files.tsv` | 指定 Classic 功能目录及 lib/next 下 Dart 文件索引与 SHA-256。文件纳入索引不表示逐行精读；关键结论以报告中具体 schema/实现引用为证据。 |
| `static_inventory.py` | 可复核的源文件解析/清单生成程序，只写本证据目录。Action 家族显式展开清单经人工对照 schema、NextCore、NextRuntime、HeadlessCore、HeadlessCapabilities；不是 Dart 执行器或实时 tools/list。 |
| `validate_inventory.py` | 文档与清单一致性检查程序，只写本目录 VALIDATION.md，不执行应用或功能测试。 |
| `VALIDATION.md` | 文档/证据范围、路径、数量与源码声明对照检查结果；不作为功能测试证据。 |

## 重现

在本 worktree 根目录运行：

```sh
python3 docs/next/evidence/x51/static_inventory.py
python3 docs/next/evidence/x51/validate_inventory.py
```

仅读取仓库 source 和 git HEAD，覆写本目录的生成清单。不访问 SharedPreferences、应用数据库、vault、endpoint、环境变量或用户媒体目录。

解析会保留同一物理键对应多个 schema（例如 Titan 17 个分项）。SettingsKeys 字符串即使出现在 read/migration 分支也不冒充独立 SettingEntry。旧 danmaku_kernel 仍有 PlayerKernelManager getter/setter，现代 renderEngine 是替代能力；这种情况与有新键兼容读写区分。

Action 的 source_reference 对于模板 ID 可能指 family spec/构造参数位置；不能据此宣称该行独立声明一个 literal ID。worker 内部的 task_worker.execute、Debug VM service extension 不作为对外注册 Action 计入。Mesh allowlist 列只判定 ID；不覆盖设备授权、登录、连接、原生支持或用户在场要求。

## 关键复核点

- 两宿主：`lib/next/next_core.dart:233`、`lib/next/next_runtime.dart:364`、`lib/next/headless/core.dart:258`；无界面过滤：`lib/next/headless/ports.dart:62`。
- Mesh 放行：`lib/next/mesh/runtime.dart:19`；文件权限与决定：`lib/next/mesh/files.dart`、`lib/next/mesh/README.md`。
- 通用任务：`packages/nipa_harness/lib/src/tasks/actions.dart:5` 对照 `engine.dart:271`；Classic 扫描：`lib/next/capabilities/local_library_operations.dart:179`。
- 播放快照：`lib/next/capabilities/media_models.dart:263`、`video_player_state_port.dart:16`；内核事实：`lib/player_abstraction/abstract_player.dart:33`。
- 持久字幕：`lib/next/subtitles/capability.dart`、`library.dart:415`、`library_io.dart`；运行时卸载：`lib/next/capabilities/classic_playback_controls.dart:231`。
- 图片：`lib/next/ui_data/metadata_facts.dart:169`，对照 `lib/next/media/media_capability.dart:620` 的 field 枚举。
- 事件：`lib/next/harness_hooks.dart:32` 对照 `lib/next/next_runtime.dart:464`。
- 本地自定义作品：`lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:975` 对照 `lib/next/media/media_capability.dart:405`。

真实任务影响、优先级、工作量和拟新增契约是推断/建议；报告明确列出，未保存任何伪造运行输出。
