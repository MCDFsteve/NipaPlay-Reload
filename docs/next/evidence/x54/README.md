# X54 证据说明

`experiment.py` 创建临时 LabProfile，直接运行本 worktree 构建，默认安静。
45 秒 testsrc2 视频、自写 SRT 和 JSON 弹幕均为 CC0-1.0，生成方式在脚本内。
没有用户媒体、账号或外部服务；endpoint 凭据只在脚本内存使用，原始应用日志
留在临时目录并随 finally 清理，不交入证据。

最终成立证据：operations.json（完整播放/字幕/弹幕），operations-retry.json
（重试及位置/暂停专项），operations-catalog.json（最终目录关联/进度/撤回专项）。
每份末尾 cleanup 均确认进程退出、临时目录删除。实验输出中的路径都是这些
已删除的临时目录，不是用户实际数据。

保留的初期失败：experiment.log（加载失败后重试失去路径）、catalog-sync-tests.log
（首次新增回归因测试路径 /var 与解析路径 /private/var 不同而未读取到进度）、
quality-final-tests.log（误写了不存在的 subtitle_library_test.dart 文件名）。对应
最终日志是 experiment-retry-final.log、catalog-sync-tests-final.log、quality-delivery-tests.log。
不将失败运行计入最终通过数量。

旧版 retry 脚本的 experiment-complete 汇总误把未执行的字幕/弹幕项目标成 true；
operations-retry.json 中的实际 Action 记录只验证重试。完整字幕/弹幕证据来自
operations.json。当前脚本已按 phase 修正汇总，未人工修改历史输出。

operations.json 的早期目录移除发生在文件关联被同步清掉之后，不能用于证明
完整关系撤回。最终修复后的 operations-catalog.json 验证一条真实 local_catalog
共享文件的两集关系、10000ms 当前进度、文件保留与撤回后的两条关系。

full-tests.log 是本次唯一完整 Next 加相关 Classic 测试运行（563 passed、7 skipped）。
之后只跑受影响文件；每次 Flutter 测试均经共享 lockf 队列并去掉代理。
最终质量回执与字幕分页由相关约束测试验证，没有重复已成立的播放实验。
