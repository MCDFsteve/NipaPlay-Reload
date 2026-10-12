"""Read-only X43 interruption audit; never starts a host or alters user data."""
from pathlib import Path
import json
import os

windows = os.name == 'nt'
root = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
label = 'windows' if windows else 'wsl'
cleanup = json.loads((root / f'x43-{label}-cleanup.json').read_text(encoding='utf-8'))
directories = [root / f'x43-{label}-data']
if windows:
    directories.append(root / 'x43-chat-data')
source = root / 'x43-headless'
binary = source / 'build/headless' / ('nipaplay-headless.exe' if windows else 'nipaplay-headless')
result = {
    'platform': label,
    'experimentDataAbsent': all(not path.exists() for path in directories),
    'sourceRetained': (source / 'bin/nipaplay_headless.dart').is_file(),
    'aotRetained': binary.is_file(),
    'priorCleanupPids': cleanup['exitedPids'],
    'newHostStarted': False,
    'sharedMediaRead': False,
}
print(json.dumps(result))
assert result['experimentDataAbsent'] and result['sourceRetained'] and result['aotRetained']
