# Windows 启动路径代码审阅

审阅基线 3dcac152 和 X57 最终工作区；未运行 Windows、未下载 runtime。

`ChatHost._launchWindows()` 直接 `Process.start(executable, arguments)`，没有 shell
位置参数。可执行文件依次取显式 `codexExecutable`、环境里的
`NIPAPLAY_CODEX_EXECUTABLE`、`codex.exe`；拒绝非原生 `.exe`。

最终 argv 顺序：

| 次序 | 参数 |
|---|---|
| 1 | `app-server` |
| 2 | Next / probe 时 `-c features.shell_snapshot=false` |
| 3 | 自有来源时 `-c model=<JSON 字符串>` |
| 4 | 自有来源时 `-c model_provider=<JSON 字符串>` |
| 5 | `-c projects={<规范 harness 路径>={trust_level="trusted"}}` |
| 6 | `-c shell_environment_policy.set.NIPAPLAY_CHAT="<sessionId>"` |

会话号在 `NIPAPLAY_CHAT`；实验默认 home 写入 `CODEX_HOME`；自有 home 随后覆盖它；
实验临时目录同时写入 `TEMP`、`TMP`。模型 API key 仅经 launch.environment 传入，
不在 argv 和公开诊断白名单。没有 macOS 的 `$1`–`$7` 位移风险。

共同的线程 start/resume 逻辑给当前 harness 的项目 hook 添加实际 key/currentHash
信任。X57 补齐了切换来源、帮手恢复和读取旧 rollout 的 resume 入口；规范化的是
来源文件的权限边界，登记的仍是 Codex 根据实际 cwd 返回的 key。

对照 macOS：`nipaplay-chat` 是 `$0`，之后依次是 `$1` 会话号、`$2` CODEX_HOME、
`$3` TMPDIR、`$4` 可执行文件、`$5` 信任覆盖、`$6` 模型、`$7` 提供方。
script 中 `exec "$4" app-server -c "$5"` 以及可选 `-c "$6" -c "$7"` 对应正确；
未填写模型时不发送 null 模型覆盖。真实三轮启动覆盖了这条 macOS 路径。

结论：参数顺序与环境覆盖正确；Windows 原生运行、路径大小写及 junction 行为
没有本轮的平台证据。
