# X62 ACP 调研证据

调研日期：2026-10-15 UTC。结论与来源编号见[ACP报告](../../research/ACP.md)。本目录只保存来源元数据、本次原创观察和校验结果，不包含第三方文档、源码、SDK、包或许可证原文。

| 文件 | 内容 |
|---|---|
| [sources.json](sources.json) | 资料链接、访问日期、临时原件路径、字节数与SHA-256；497条，其中22条为明确标记的抓取失败 |
| [runtimes.json](runtimes.json) | 17个仓库、20个包的版本、发布日期、固定commit、依赖、许可元数据、大小和上游完整性值；不是完整安装体积清单 |
| [experiments.json](experiments.json) | 本次原创协议实验结论、未通过/未验证项、原始日志和probe程序的临时路径及哈希 |
| [artifact-checks.json](artifact-checks.json) | 最后一次本地交付校验：分支/基线、改动范围、JSON、链接、原件哈希和交付文件哈希 |

第三方原件及实验原始文件均位于 `/tmp/nipa-next/x62/`；临时目录可能被系统清理。仓库中的链接、固定版本/commit、校验值和实验结论可用于追溯；本目录没有把外部原文永久归档。`sources.json` 的 `local_tmp` 与 `tmp_path` 均表示临时原件位置。没有校验值的失败记录只说明访问失败，不支持该页内容结论。

报告以固定发布版本为主。`source_tip` / `pushed_at`用于判断维护状态；它们不证明未发布功能已存在于release。npm integrity/shasum及release upstream_digest来自上游元数据；本地SHA-256才表示本次实际读取过的字节。未下载的分发文件不宣称完成本地校验。

本次只运行了隔离目录中的Codex ACP、Kimi Code与旧Kimi核查；pi仅安装。假模型HTTP服务绑定127.0.0.1，使用假key，真实计费模型对话为0。没有构建或启动NipaPlay，没有修改产品代码，也没有读取用户agent凭据。成功实验只能证明报告列出的固定组合与时序，不能证明真实DeepSeek/GLM模型质量、完整工具兼容或所有平台分发可用。
