"""Install only a local Dart SDK and unpack the credential-free source bundle."""
from pathlib import Path
import os
import subprocess
import sys
import zipfile

windows = os.name == 'nt'
root = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
root.mkdir(exist_ok=True)
sdk = root / 'x43-tools/dart-sdk'
platform = 'windows' if windows else 'linux'
archive = root / f'x43-tools/dartsdk-{platform}.zip'
archive.parent.mkdir(exist_ok=True)
if not sdk.exists():
    subprocess.run(['curl.exe' if windows else 'curl', '-fL', '--retry', '2',
        '--connect-timeout', '15', '--max-time', '300',
        f'https://storage.googleapis.com/dart-archive/channels/stable/release/3.12.2/sdk/dartsdk-{platform}-x64-release.zip',
        '-o', str(archive)], check=True)
    with zipfile.ZipFile(archive) as z:
        z.extractall(sdk.parent)
    if not windows:
        for file in sdk.rglob('*'):
            if file.is_file() and (file.parent.name == 'bin' or file.suffix == ''):
                file.chmod(file.stat().st_mode | 0o111)
bundle = Path('D:/nipaplay-next/x43-headless.zip') if windows else Path('/mnt/d/nipaplay-next/x43-headless.zip')
with zipfile.ZipFile(bundle) as z:
    z.extractall(root / 'x43-headless')
dart = sdk / ('bin/dart.exe' if windows else 'bin/dart')
subprocess.run([str(dart), '--version'], check=True)
print('Local SDK and source ready:', root / 'x43-headless', flush=True)
