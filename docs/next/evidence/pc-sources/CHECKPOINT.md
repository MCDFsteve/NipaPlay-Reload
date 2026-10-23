# S 线实现节点

2026-10-23，基于 bf209633，分支 next/pc-sources。

已接入网络来源解析、稳定路径续播、Jellyfin/Emby 会话与版本/轨道/清晰度重开、独立远端进度回报、剧集列表与导航、播完动作及可取消倒计时。mesh 进度改为订阅会话事件，资源包解析放到 isolate。公共文件只增加接缝；未走 Classic 播放器。

验证命令（先清除代理环境变量）：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/player/sources_test.dart \
  test/next/player/session_playback_test.dart \
  test/next/player/session_test.dart
```

结果尾部：`00:07 +29: All tests passed!`

这是实现节点，不是最终验收。完整 Next/Classic 回归、真实实例播放/跳转/换流/画面截图、服务器进度比对、网络文件续播和 mesh 双实例验收仍待执行。构建按 mac-heavy.lock 排队；实验将只使用 core-lab-s 与一次性容器。

恢复后的第二实现节点：

- 关闭时阻断仍在解析的来源已单独提交 `45c938ff1`。
- Jellyfin/Emby 真实播放、52 秒跳转、第二音轨、1 Mbps 转码保位和远端进度比对已通过；WebDAV/SMB 约 53 秒续播、四种播完动作与取消倒计时已通过，截图和操作记录将在最终验收提交整理。
- 转码停止带逐会话 DeviceId/PlaySessionId，保留反向代理子路径并检查 HTTP 状态；播放列表的定位与序列化移入 isolate。
- mesh 使用编码的 `mesh:///…` 稳定剧集路径，临时地址与资源包逐次直连获取；新增弹弹play稳定路径解析。来源专项 13 项通过，包含跨版本轨道校验、暂停与位置保留、Mesh 冒号 ID 与新地址、弹弹play hash/id 路径。
- mesh 已有两台真实实例和独立身份；修复路径冒号问题后仍需使用新构建完成播放、截图、对端进度和换集验收。不能据此节点宣称全部交付。
