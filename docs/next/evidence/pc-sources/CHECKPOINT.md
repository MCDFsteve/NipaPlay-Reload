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
