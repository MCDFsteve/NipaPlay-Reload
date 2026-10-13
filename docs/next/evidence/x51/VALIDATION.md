# X51 文档与静态证据检查

日期：2026-10-13；分支 `next/x51-coverage`；HEAD `c1b179e9cd74d8445cb971a0dc8b9026d4a3a02d`。

仅以 Python 标准库与只读 git 命令检查文档、源码符号与文件摘要。以下是检查结果，不是功能测试或真机实验。

| 检查 | 结果 |
|---|---|
| Action ID 唯一性/数量 | 196 项，无重复 |
| GUI/无界面静态组装 | GUI 196；无界面 89，含同名不同实现 |
| Mesh 放行与源码函数逐 ID 对照 | 158 项匹配 allowlist；远程 tools/list 已过滤 |
| literal schema/helper 声明交叉扫描 | 126 个目录 ID 直接匹配；唯一目录外候选 task_worker.execute 为内部 worker。其他 70 个 ID 为模板/条件/工厂展开，人工对照家族构造与两宿主组装；不宣称 regex 能证明全部运行时目录 |
| SettingsKeys 与常量定义对照 | 80 项符号与物理键逐项一致；58 registered、3 compatibility_only、1 legacy_api_only、18 unregistered |
| 报告逐键缺口完整性 | 22 个无独立入口常量 + 3 个额外 literal 均有独立行 |
| SettingsStorage 显式 load/save 调用参数 | 75 个调用，无未解析参数；仅键与引用，不记值 |
| 静态 physical→logical 映射 | 186 项；范围见 README，不是动态运行时注册表 |
| 报告及证据完整源码路径/行号 | 1480 个不同路径/行号组合存在且行号在范围内；不据此证明引用语义 |
| 索引源码 SHA-256 | 700 项全部一致；不表示全部逐行精读 |
| 排序主缺口 | 16 项；均给出代码、新契约、难度和用户决定效果 |
| git 写入范围 | tracked/staged diff 均空；未跟踪文件仅在授权报告与证据目录 |
| 秘密格式检查 | 10 个输入交付文件，常见 API token/JWT/private-key/认证 URL 格式命中 0；补充人工检查无秘密值。格式扫描不是任意秘密的完备证明 |

方法可复核：运行本目录 validate_inventory.py。读取 TSV 验证唯一性/数量；将 SettingsKeys 与常量定义正则结果逐项比较，核对缺口键表行；提取 Mesh prefix/exact allowlist 逐 ID 比较；检查报告、README 与 TSV 中完整 repo 路径/行号；重新计算 source_files.tsv 所列 SHA-256；读取 git diff、git diff --cached、git ls-files --others --exclude-standard 核对写入范围。敏感格式检查只报告数量，不记录匹配内容。生成的本文也检查链接和敏感格式。

复核更正：旧 danmaku_kernel 只有旧 API 读写，不能视为现代 renderEngine 的兼容读取；Mesh McpRpc 的 tools/list 已执行 include 过滤；模板 Action 的引用改为构造/模板所在行，避免误指向第 1 行；无界面过滤引用更正到 ports.dart:62。

未运行：NipaPlay、nipa、Flutter 构建、flutter test、pub get、原生工具/线上服务。未读取用户运行时偏好、数据库、vault、endpoint 或日志。未提交或 push。功能实验由主控选择真实任务另行执行。
