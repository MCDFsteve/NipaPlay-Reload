from pathlib import Path
import os
import subprocess
import sys

windows = os.name == 'nt'
root = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
media = Path('D:/Anime') if windows else Path('/mnt/d/Anime')
script = Path('D:/nipaplay-next/x43-experiment.py') if windows else Path('/mnt/d/nipaplay-next/x43-experiment.py')
label = 'windows' if windows else 'wsl'
command = [sys.executable, str(script),
    '--source', str(root / 'x43-headless'),
    '--dart', str(root / 'x43-tools/dart-sdk/bin' / ('dart.exe' if windows else 'dart')),
    '--data', str(root / f'x43-{label}-data'),
    '--media', str(media / '躲在超市后门抽烟的两人'),
    '--evidence', str(root / f'x43-{label}.json'), '--label', f'x43-{label}']
if '--resume' in sys.argv: command.append('--resume')
subprocess.run(command, check=True)
