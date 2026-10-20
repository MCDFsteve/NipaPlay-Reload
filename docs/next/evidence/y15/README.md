# Y15 压缩证据

`measurements.json.gz` 是原创计量与脱敏事件摘要：首请求仅保留长度、角色布局、工具名、估算 token 和原件 SHA-256；不含第三方系统提示/工具 schema 原文。行为部分保留 18 次正式尝试和全部提供方失败，另列排除的预跑。模型可见输出仅保留 assistant 正文，不含原始思考。

`sources.json.gz` 是公开 npm/GitHub 发布元数据与本机来源文件哈希，不复制第三方源码或 SDK。许可、平台与前次接入研究见 ../../research/ACP.md、../../research/AGENT_RUNTIMES.md。

`lab-scripts.tar.gz` 仅含本任务原创脚本。原始请求、SSE、会话、第三方文件仍在 `~/.nipa-next/y15/`。实验原件为审计存档，不要直接覆盖运行目录。复现须先按报告版本本地安装（所有 cache/tmp/home 指向实验根），将脚本中的实验 ROOT/REPO 改成自己的路径，并准备该报告指定哈希的 AGENTS.md。macOS 正式实验使用 sandbox-exec；不是跨平台测试脚本。

假端点捕获不消耗真实模型额度。`lab.py behavior ...` 会读取用户 config.toml 的 cpa provider 并消耗真实额度；父转发器只在内存读取真实地址/key，子 agent 仅得到 loopback 和假 key。切勿复制真实配置进仓库。

token 估算是 tiktoken o200k_base 替代计数，非 DeepSeek 官方账单；正式行为 token 来自 Responses usage，缓存输入未扣除。provider 失败没有 usage 时不补估。

正式行为组 AGENTS 哈希为 131a9e869dcd5f3b8dde550a0969ce019d95353cbf7de307f2c5f54c01705a36。旧首请求和预跑是另一版本，不用于报告首请求表及正式行为对比。
