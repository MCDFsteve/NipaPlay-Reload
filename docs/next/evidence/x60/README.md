# X60 证据

- validation.json：实际命令范围、完整运行终行、最后局部复核、analyze 与 diff 检查。
- observations.json：通过实验/约束检查观察到的结构结果，不包含端口、登录凭据或私钥。
- bangumi-api.json：公开 API 来源、快照摘要及取消收藏接口核对。

失败及修正过程见 X60_REPORT.md。回环测试使用合成种子、PNG、账号响应；Mesh 使用临时
签发者、保险库和节点，真实双向 TLS。它们不证明线上服务、GUI 或跨平台桌面已经验收。
原始日志留在临时 `/tmp/nipa-next/x60/`，没有复制到仓库。
