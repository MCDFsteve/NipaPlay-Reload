"""Verify the final snapshot without repeating the shared-media scan."""
from pathlib import Path
import json
import os
import runpy
import subprocess
import sys
import time

mac = '--mac' in sys.argv
windows = os.name == 'nt'
label = 'macos' if mac else ('windows' if windows else 'wsl')
root = Path('/tmp/nipa-next/x43') if mac else (Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next')
source = Path('/Users/sakiko/Desktop/nipaplay-next-wt/x43-headless') if mac else root / 'x43-headless'
data = root / ('mac-data' if mac else f'x43-{label}-data')
dart = Path('/Users/sakiko/development/flutter-3.44.6/bin/dart') if mac else root / 'x43-tools/dart-sdk/bin' / ('dart.exe' if windows else 'dart')
previous_file = source / 'docs/next/evidence/x43/macos.json' if mac else root / f'x43-{label}.json'
previous = json.loads(previous_file.read_text(encoding='utf-8'))
media = Path('/Volumes/Anime' if mac else ('D:/Anime' if windows else '/mnt/d/Anime')) / '躲在超市后门抽烟的两人'
binary = source / 'build/headless' / ('nipaplay-headless.exe' if windows else 'nipaplay-headless')
binary.parent.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, NIPAPLAY_ENDPOINT_FILE=str(data / 'endpoint.json'))
for key in list(env):
    if key.lower() in {'http_proxy', 'https_proxy', 'all_proxy'}:
        del env[key]
env['NO_PROXY'] = '127.0.0.1,localhost'
os.environ['NIPAPLAY_ENDPOINT_FILE'] = env['NIPAPLAY_ENDPOINT_FILE']
if not mac and '--no-compile' not in sys.argv:
    subprocess.run([str(dart), 'compile', 'exe', '--packages=.dart_tool/package_config.json', 'bin/nipaplay_headless.dart', '-o', str(binary)],
        cwd=source, env=env, check=True)
result = {'platform': label, 'aotExecutable': str(binary), 'iterations': [], 'noMediaRescan': True}
identity = (data / 'device.json').read_text()
for iteration in range(2):
    command = [str(binary), '--data', str(data)]
    with (root / f'x43-{label}-final.host.log').open('a') as log:
        process = subprocess.Popen(command + (['--media-root', str(media)] if iteration == 0 else []),
            cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
    facts = {'pid': process.pid}
    try:
        deadline = time.monotonic() + 30
        while not (data / 'running.json').exists():
            if process.poll() is not None: raise RuntimeError('Final AOT host exited before startup')
            if time.monotonic() > deadline: raise TimeoutError('Final AOT startup exceeded deadline')
            time.sleep(0.1)
        client = runpy.run_path(str(source / 'assets/next/harness/nipa'))['Client']()
        def call(action, values):
            outcome = client.call(action, values)
            assert outcome['status'] == 'completed', outcome
            return outcome['result']
        status = subprocess.run([sys.executable, str(source / 'assets/next/harness/nipa'), 'status'],
            cwd=source, env=env, capture_output=True, text=True, encoding='utf-8', check=True)
        facts['pythonNipaInstance'] = json.loads(status.stdout)['instance']
        facts['configuration'] = json.loads((data / 'headless.json').read_text(encoding='utf-8'))
        facts['identityRetained'] = (data / 'device.json').read_text() == identity
        assert facts['identityRetained']
        assert facts['configuration']['mediaRoots'] == [str(media)]
        work_id = previous['bindings']['entries'][0]['workId']
        ui = call('media.metadata.ui_facts', {'workId': work_id})
        facts['persistedUiFactsRead'] = bool(ui)
        if iteration == 0:
            accepted = call('download.add', {'source': 'magnet:?xt=urn:btih:' + '4' * 40 + '&dn=X43-unavailable'})
            job = client.watch(accepted['job']['jobId'], 30)['result']['job']
            assert job['state'] == 'failed', job
            facts['downloadFailure'] = job
    finally:
        subprocess.run(command + ['--stop'], cwd=source, env=env, check=True)
        try: facts['exitCode'] = process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            facts['forcedStopPid'] = process.pid
        facts['endpointRemoved'] = not (data / 'endpoint.json').exists()
        assert facts.get('exitCode') == 0 and facts['endpointRemoved'], facts
        result['iterations'].append(facts)
(root / f'x43-{label}-final.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps({'platform': label, 'pids': [i['pid'] for i in result['iterations']], 'stopped': True}))
