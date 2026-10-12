"""Download a native Codex binary locally; no user Codex config is accessed."""
from pathlib import Path
import base64
import hashlib
import json
import os
import subprocess
import tarfile

root = Path('D:/nipaplay-next')
tools = root / 'x43-tools/codex'
tools.mkdir(parents=True, exist_ok=True)
metadata = tools / 'package.json'
subprocess.run(['curl.exe', '-fsSL', '--connect-timeout', '15', '--max-time', '60',
    'https://registry.npmjs.org/@openai/codex/0.162.1-win32-x64', '-o', str(metadata)], check=True)
package = json.loads(metadata.read_text())
archive = tools / 'package.tgz'
subprocess.run(['curl.exe', '-fL', '--connect-timeout', '15', '--max-time', '180',
    package['dist']['tarball'], '-o', str(archive)], check=True)
algorithm, expected = package['dist']['integrity'].split('-', 1)
actual = base64.b64encode(hashlib.new(algorithm, archive.read_bytes()).digest()).decode()
if actual != expected: raise ValueError('Npm package integrity mismatch')
with tarfile.open(archive) as tar:
    # Npm payload paths are relative; extract into this permitted tool directory.
    for member in tar.getmembers():
        destination = (tools / member.name).resolve()
        if not destination.is_relative_to(tools.resolve()) or member.issym() or member.islnk():
            raise ValueError('Unexpected package archive path')
    tar.extractall(tools, filter='data')
binary = next(tools.rglob('codex.exe'))
source = root / 'x43-headless'
dart = root / 'x43-tools/dart-sdk/bin/dart.exe'
probe = root / 'x43-windows-chat-probe.dart'
result = subprocess.run([str(dart), '--packages=.dart_tool/package_config.json',
    str(probe), str(root / 'x43-chat-data'), str(binary)], cwd=source,
    check=True, capture_output=True, text=True, encoding='utf-8')
evidence = {'version': package['version'], 'nativeExecutable': str(binary),
    'userConfigCopied': False, 'modelCredentialsUsed': False,
    'probe': [json.loads(line) for line in result.stdout.splitlines()]}
(root / 'x43-windows-chat.json').write_text(json.dumps(evidence, indent=2))
print(json.dumps(evidence, indent=2))
