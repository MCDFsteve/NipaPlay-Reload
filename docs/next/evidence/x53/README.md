# X53 证据索引

日期：2026-10-13。结论及限制见 [X53_REPORT.md](../../X53_REPORT.md)。JSON按label记录实际输出，不把失败覆盖成成功；不同阶段的实验分别保存。网关夹具、测试账号、CC0弹幕与公共服务结果明确区分。

| 文件 | 内容与判读 |
|---|---|
| online.json / online-run.txt | 公开影片hash/资料搜索初验；headless弹弹play超时，整体比较false |
| preparation.json / preparation-run.txt | GUI准备成功、headless弹幕搜索失败，保留已保存事实 |
| completion.json / completion-run.txt | headless完成身份/资料/本地CC0弹幕准备，和GUI比较equal=true；当时在线搜索仍失败 |
| source-check.json / source-check-proxy-run.txt | 最终宿主代理环境下headless公开hash/资料/弹幕搜索成功，无弹弹play候选 |
| gateway.json / gateway-run.txt | 回环合成网关，两端非空hash/metadata/弹幕fetch链与凭据域校验；不是公共弹幕池 |
| final-facts.json / final-facts-run.txt | 最终CLI可用前置、族describe、stdin登记、拒绝错误marker、TMDB引用变化及清理 |
| mesh/local-loopback.json / mesh-run.txt | 真实本机mTLS、程序授权、字幕、bundle、回传；没有模型或工作站节点 |
| mesh-final/ / mesh-final-run.txt | 修复前远程mesh.devices超帧失败，所有实例清理 |
| mesh-scope-success/ / mesh-scope-success-run.txt | 修复后完整/筛选设备、settings写、远端CLI目录、族describe、清理 |
| next-full-tests.txt | 最终一次全test/next：515 passed、5 skipped |
| constraints-final.txt | 相关领域与Classic网关/client最终50 passed |
| mesh-constraints-final.txt | 帧/事实补修后的相关数据约束19 passed |
| classic-settings-tests.txt | Classic统一网络设置与服务器对话框5 passed |
| targeted-tests-final.txt / storage-tests-final.txt | 迭代相关测试42 passed / 持久绑定和部分失败2 passed |
| analyze-final.txt | 最终0 error/warning，5条已有info |
| gui-build-final.txt / gui-signature-final.txt | 本worktree Debug GUI构建及runtime签名/strict验证 |
| mac-headless-build-final.txt / native-build.txt | 本机AOT与offline native构建 |
| headless-graph-final.txt | 公共纯Dart图，dart_ui_files=[]；没有未解析依赖操作 |
| windows-compile-final.txt / wsl-compile-final.txt | 最新Windows/WSL只编译，nodeStarted=false |
| verification.json | 公开搜索稳定字段对比、准备/网关/远程结果、旧帧大小计算、JSON/秘密检查及清理核对 |

无final后缀的build/analyze/tests日志保留迭代状态，以final为最终结论。`storage-tests.txt`含早期夹具断言错误，最终日志已经通过；`source-check-run.txt`含第一次源查询网络失败，以source-check-proxy-run为最终成功。

复现脚本：`scripts/next/x53_online_experiment.py`（公开Blender影片及已配置的临时测试账号）、`x53_gateway_experiment.py`（纯回环合成网关）、`x53_facts_check.py`（只本机临时宿主）、`tool/next/headless_loopback_check.py --scope-only/--programs`。脚本需要本worktree现成产物，均在finally退出自有PID并清理节点数据；公开视频输入需先准备到`/tmp/nipa-next/x53-online/bbb.zip`，最终删除此输入目录。

证据没有endpoint token、原始账户秘密、私钥、cookie或带认证URL；returnTicket已脱敏，credentialRef只保留namespace/key。Mesh目录里的storage路径是已经删除的夹具路径，不是用户真实库。
