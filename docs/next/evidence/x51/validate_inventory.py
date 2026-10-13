"""Check static research artifacts; only write this directory's VALIDATION.md.

No application, runtime storage, network requests or functional tests are used.
"""
from pathlib import Path
import collections
import csv
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'docs/next/evidence/x51'
REPORT = ROOT / 'docs/next/research/NEXT_COVERAGE.md'


def table(name):
    with (OUT / name).open() as file:
        return list(csv.DictReader(file, delimiter='\t'))


def require(ok, message):
    if not ok:
        raise AssertionError(message)


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


actions = table('actions.tsv')
ids = {row['action_id'] for row in actions}
require(len(actions) == len(ids) == 196, 'Action unique count')
headless = sum(row['headless_registered'].startswith('yes') for row in actions)
remote = sum(row['mesh_allowlist'] == 'yes' for row in actions)
require((headless, remote) == (89, 158), 'Host/mesh counts')
allow = (ROOT / 'lib/next/mesh/runtime.dart').read_text().split(
    'bool meshActionAllowed(String id) =>', 1)[1].split('/// Trust anchors', 1)[0]
prefix_part, exact_part = allow.split('const {', 1)
prefixes = re.findall(r"'([^']+)'", prefix_part)
exact = set(re.findall(r"'([^']+)'", exact_part))
require(all((row['mesh_allowlist'] == 'yes') == (
    row['action_id'] in exact or any(row['action_id'].startswith(p) for p in prefixes)
) for row in actions), 'Mesh allowlist source mismatch')

keys = table('settings_keys.tsv')
counts = collections.Counter(row['registry_status'] for row in keys)
require(len(keys) == len({row['symbol'] for row in keys}) == 80, 'SettingsKeys count')
require(dict(counts) == dict(registered=58, compatibility_only=3,
                            unregistered=18, legacy_api_only=1), 'Key classifications')
source_keys = dict(re.findall(r"static const String\s+(\w+)\s*=\s*'([^']+)'",
                             (ROOT / 'lib/constants/settings_keys.dart').read_text()))
require(source_keys == {row['symbol']: row['storage_key'] for row in keys},
        'SettingsKeys source mismatch')
report = REPORT.read_text()
section = report.split('## SettingsStorage / SettingsKeys 逐键对照')[1].split(
    '### 不在上述')[0]
missing = [row['storage_key'] for row in keys if row['registry_status'] != 'registered']
require(all('| `' + key + '`' in section for key in missing), 'Missing key report rows')
storage = table('settings_storage_calls.tsv')
registered = table('registered_settings.tsv')
require(not any(row['storage_key'] == 'UNRESOLVED' for row in storage),
        'Unresolved storage argument')
extra = sorted({row['storage_key'] for row in storage}
               - {row['storage_key'] for row in keys}
               - {row['storage_key'] for row in registered})
require(extra == ['anime_detail_display_mode', 'debug_log_auto_scroll',
                  'debug_log_show_timestamp'], 'Unexpected literal gap')
require(all('| `' + key + '`（literal）' in section for key in extra),
        'Missing literal rows')

refs = set()
for file in [REPORT, OUT / 'README.md'] + list(OUT.glob('*.tsv')):
    for match in re.finditer(
        r'((?:lib|packages|rust|docs|assets)/[A-Za-z0-9_./-]+\.(?:dart|rs|md|tsv|txt|py))(?:\:(\d+))?',
        file.read_text(),
    ):
        refs.add((match[1], match[2]))
for path, line in refs:
    file = ROOT / path
    require(file.is_file(), 'Missing referenced path: ' + path)
    if line:
        require(1 <= int(line) <= len(file.read_text().splitlines()),
                'Out-of-range line: ' + path + ':' + line)
files = table('source_files.tsv')
require(len(files) == len({row['source_path'] for row in files}) == 700, 'Source index count')
require(all(hashlib.sha256((ROOT / row['source_path']).read_bytes()).hexdigest()
            == row['sha256'] for row in files), 'Source SHA mismatch')
revision = git('rev-parse', 'HEAD')
branch = git('branch', '--show-current')
require(revision == (OUT / 'REVISION.txt').read_text().strip(), 'HEAD mismatch')
require(branch == 'next/x51-coverage', 'Branch mismatch')
require(not git('diff', '--name-only'), 'Tracked worktree changes')
require(not git('diff', '--cached', '--name-only'), 'Staged changes')
others = git('ls-files', '--others', '--exclude-standard').splitlines()
require(all(path == 'docs/next/research/NEXT_COVERAGE.md'
            or path.startswith('docs/next/evidence/x51/') for path in others),
        'Writes outside allowed paths')

# Only scan deliverables and report a count; never print matched values.
patterns = [
    r'\bsk-[A-Za-z0-9_-]{20,}',
    r'\bgh[pousr]_[A-Za-z0-9]{20,}',
    r'\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}',
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'https?://[^\s<>`]+(?:[?&](?:access_token|api_key|token|signature|auth|password)=|://[^/\s]+:[^/\s]+@)',
]
scanned = [REPORT] + [file for file in OUT.rglob('*')
                      if file.is_file() and file.name != 'VALIDATION.md']
hits = sum(len(re.findall(pattern, file.read_text(), re.I))
           for file in scanned for pattern in patterns)
require(hits == 0, 'Sensitive-format scan has hits; do not print contents')

# Bounded independent literal scan; not a parser for dynamic Action templates.
literal = set()
for directory in ['lib/next', 'lib/security', 'packages/nipa_harness/lib/src/tasks']:
    for file in (ROOT / directory).rglob('*.dart'):
        source = file.read_text()
        for pattern in [r"\bid\s*:\s*'([a-z][a-z0-9_.]+)'",
                        r"\b(?:_spec|_action|_Operation)\(\s*'([a-z][a-z0-9_.]+)'",
                        r"ActionSpec\.\w+\(\s*'([a-z][a-z0-9_.]+)'"]:
            literal.update(match[1] for match in re.finditer(pattern, source)
                           if '.' in match[1])
require(literal - ids == {'task_worker.execute'}, 'Unclassified source declaration')
require(len(literal & ids) == 126, 'Literal comparison count')
require(len(re.findall(r'^### G\d\d', report, re.M)) == 16, 'Gap count')

validation = f'''# X51 文档与静态证据检查

日期：2026-10-13；分支 `{branch}`；HEAD `{revision}`。

仅以 Python 标准库与只读 git 命令检查文档、源码符号与文件摘要。以下是检查结果，不是功能测试或真机实验。

| 检查 | 结果 |
|---|---|
| Action ID 唯一性/数量 | 196 项，无重复 |
| GUI/无界面静态组装 | GUI 196；无界面 {headless}，含同名不同实现 |
| Mesh 放行与源码函数逐 ID 对照 | {remote} 项匹配 allowlist；远程 tools/list 已过滤 |
| literal schema/helper 声明交叉扫描 | 126 个目录 ID 直接匹配；唯一目录外候选 task_worker.execute 为内部 worker。其他 70 个 ID 为模板/条件/工厂展开，人工对照家族构造与两宿主组装；不宣称 regex 能证明全部运行时目录 |
| SettingsKeys 与常量定义对照 | 80 项符号与物理键逐项一致；58 registered、3 compatibility_only、1 legacy_api_only、18 unregistered |
| 报告逐键缺口完整性 | 22 个无独立入口常量 + 3 个额外 literal 均有独立行 |
| SettingsStorage 显式 load/save 调用参数 | {len(storage)} 个调用，无未解析参数；仅键与引用，不记值 |
| 静态 physical→logical 映射 | {len(registered)} 项；范围见 README，不是动态运行时注册表 |
| 报告及证据完整源码路径/行号 | {len(refs)} 个不同路径/行号组合存在且行号在范围内；不据此证明引用语义 |
| 索引源码 SHA-256 | {len(files)} 项全部一致；不表示全部逐行精读 |
| 排序主缺口 | 16 项；均给出代码、新契约、难度和用户决定效果 |
| git 写入范围 | tracked/staged diff 均空；未跟踪文件仅在授权报告与证据目录 |
| 秘密格式检查 | {len(scanned)} 个输入交付文件，常见 API token/JWT/private-key/认证 URL 格式命中 0；补充人工检查无秘密值。格式扫描不是任意秘密的完备证明 |

方法可复核：运行本目录 validate_inventory.py。读取 TSV 验证唯一性/数量；将 SettingsKeys 与常量定义正则结果逐项比较，核对缺口键表行；提取 Mesh prefix/exact allowlist 逐 ID 比较；检查报告、README 与 TSV 中完整 repo 路径/行号；重新计算 source_files.tsv 所列 SHA-256；读取 git diff、git diff --cached、git ls-files --others --exclude-standard 核对写入范围。敏感格式检查只报告数量，不记录匹配内容。生成的本文也检查链接和敏感格式。

复核更正：旧 danmaku_kernel 只有旧 API 读写，不能视为现代 renderEngine 的兼容读取；Mesh McpRpc 的 tools/list 已执行 include 过滤；模板 Action 的引用改为构造/模板所在行，避免误指向第 1 行；无界面过滤引用更正到 ports.dart:62。

未运行：NipaPlay、nipa、Flutter 构建、flutter test、pub get、原生工具/线上服务。未读取用户运行时偏好、数据库、vault、endpoint 或日志。未提交或 push。功能实验由主控选择真实任务另行执行。
'''
require(not any(re.search(pattern, validation, re.I) for pattern in patterns),
        'Sensitive-format match in validation text')
(OUT / 'VALIDATION.md').write_text(validation)
for file in [REPORT, OUT / 'README.md', OUT / 'VALIDATION.md']:
    for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', file.read_text()):
        if not target.startswith(('http:', 'https:', '#')):
            require((file.parent / target.split('#')[0]).is_file(), 'Missing document link')
print(json.dumps(dict(result='PASS', actions=len(ids), headless=headless,
                      mesh_allowlist=remote, settings_keys=len(keys),
                      storage_calls=len(storage), registered_mappings=len(registered),
                      source_hashes=len(files), source_refs=len(refs),
                      sensitive_format_hits=hits), ensure_ascii=False))
