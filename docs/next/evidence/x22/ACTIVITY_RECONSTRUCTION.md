# X22：仅由 activity 重建

输入仅为 `activity-pages.json` 的七次 `state.query` 返回（48 行、48 个不同事件 ID，warnings=[]）。按时间反向阅读，未再查数据库、任务详情或操作清单。以下时间均为 UTC；事件时间相同的状态与回执视为同一提交中的事实，不推断先后。

1. 12:45:18：活动 harness 有一条作者 NipaPlay 的 seed 更新提交。
2. 12:46:05：Agent 经 harness_cli 把快进快退步长从 10 改为 12；随后添加 X22 local source（WebDAV，本地用户名 x22-fixture，尚未连接）。来源保存事实与调用 completed 是两条不同记录，不计为两次添加。
3. 同一秒，Agent 创建扫描任务；系统执行并给 verified 回执，索引一个文件 `file-0cb75353-4b87-4da8-9dbc-7e8e6742ca05`。
4. 12:49:37：Agent 创建弹弹play登录任务；账号事实从未登录变为 x22-fixture 已登录；系统任务 succeeded、回执 verified。第一版 type 是 account.changed，但 before/after 明确表达登录。
5. 12:50:21：收到弹弹play 7001 的元数据快照（X22 catalogue fixture），为作品绑定此身份；随后绑定临时 TMDB x22-synthetic。
6. 同一秒：收到 TMDB 的 X22 submitted snapshot，评分 8.1/10、52 人。抓取时间为前一天，交入时间为此刻；它应在本轮交入处出现。
7. 同一秒：Agent 尝试绑定 TMDB x22-conflicting，被拒绝为 conflict；随后撤销原来的 x22-synthetic 绑定。快照事实仍可读，不能把失败尝试说成成功绑定。
8. 同一秒：Agent 交入 x22-fixture/local-video-1 的一条弹幕，绑定 ID 为 `danmaku-b55c6ba2-7fc5-4783-b1ec-b928f8bc4b5d`。没有播放事实，不能据此声称当时已显示弹幕。
9. 12:50:43：harness 出现作者 X22 Agent 的提交 `af88fb8408790e18a8282c327533827147729d53`，说明为 X22 record real activity experiment；随后 Agent 发起第二个扫描。
10. 12:50:44：扫描触发 library.file_added hook，输入对象是 x22-hook.mp4 的实验路径。扫描回执 verified，索引两个文件；hook 把快进步长从 12 改为 13，origin 是 hook:job-fddd817e49a6022d008f5bfd423f767f，随后 hook 回执 verified，exitCode=0、elapsedMs=600。
11. 12:51:31：Agent 重新绑定 TMDB x22-synthetic，并撤销弹弹play 7001 绑定；最后的作品因而只保留 TMDB 身份。

这些事实都发生在 `device-291870e501383b40db7ca7424c8c8bb2`。Agent 发起任务与系统推进任务分开标 actor；hook 与 harness git 作者也有自己的归属。git 作者只是提交声明的作者，时间精度到秒。

第一版可见偏差：账号登录类型过宽；任务回执虽包含 fileIds，但顶层 entityIds 为空；hook 改设置的 origin 有任务 ID，但 jobId 为空。它们不妨碍这次全流阅读，但会影响类型/实体/任务过滤，须修正派生字段。窗口打开操作及未写入身体的普通失败没有出现在该流中，不能由此还原窗口操作。
