"""Real host-unavailable, terminal CLI, cancellation and busy-thread observations."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

workspace = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM

evidence = Path(__file__).parent
profile = 'x25-controls-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
media = root / 'data/fixture'
media.mkdir(parents=True)
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True,
    'flutter.downloader_enabled': False,
    'flutter.nipaplay_scanned_folders': [str(media)],
    'flutter.skip_danmaku_matching': True,
}))
config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
hosts = ['127.0.0.1', 'localhost']
for url in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config):
    hosts.append(urllib.parse.urlparse(url).hostname)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
env = os.environ.copy()
env.update(NIPAPLAY_PROFILE=profile, CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'),
           SSL_CERT_FILE=str(root / 'system-ca.pem'), NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
app = None
endpoint = None
vm = None
records = []
tokens = []


def record(label, value):
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    records.append({'label': label, 'at': time.time(), 'value': value})
    (evidence / 'controls.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))


def call(action, inputs):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs,
    }).encode(), headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=60) as response:
        result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']


def launch(index, host):
    global app, endpoint, vm
    old = endpoint['token'] if endpoint else None
    log = Path('/tmp/nipa-next/x25') / ('controls-app-' + str(index) + '.log')
    with log.open('w') as stream:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                               env=env, stdout=stream, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 90
    while True:
        assert app.poll() is None and time.monotonic() < deadline
        path = root / 'endpoint.json'
        if path.exists():
            fresh = json.loads(path.read_text())
            if fresh['token'] != old:
                endpoint = fresh
                try:
                    vm = LabVM(log)
                    if host:
                        vm.chat('status')
                    break
                except RuntimeError:
                    pass
        time.sleep(.5)
    tokens.append(endpoint['token'])
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch', {'pid': app.pid, 'hostExpected': host, 'profile': profile})


def stop(host):
    if app is not None and app.poll() is None:
        if host:
            vm.chat('close')
        app.terminate()
        app.wait(timeout=15)
        record('stop', {'pid': app.pid, 'returncode': app.returncode})


def until(predicate, seconds=180):
    deadline = time.monotonic() + seconds
    while True:
        result = predicate()
        if result:
            return result
        assert time.monotonic() < deadline, 'control observation timeout'
        time.sleep(.5)


def row(identifier):
    return next(r for r in call('followup.list', {})['followups'] if r['id'] == identifier)


try:
    # Omitted lab CODEX_HOME config deliberately makes ChatHost.start fail.
    launch(0, False)
    scan = call('media.library.scan', {'root': str(media), 'requestId': 'controls-empty'})['job']
    until(lambda: call('task.get', {'jobId': scan['jobId']})['job']['state'] == 'succeeded')
    first = call('followup.register', {'when': {'jobId': scan['jobId']},
           'title': 'CLI terminal task followup', 'instruction': '请告诉用户：后台扫描已经结束。这次无需进一步操作。'})['followup']
    pending = until(lambda: (r := row(first['id'])) and (r if r['state'] == 'ready' and 'Prepare provider' in (r['reason'] or '') else None))
    record('host-unavailable', pending)
    cancel = call('followup.register', {'when': {'event': 'playback.started'}, 'instruction': 'This will be cancelled.'})['followup']
    record('cancel', call('followup.cancel', {'id': cancel['id']}))
    record('cancel-again', call('followup.cancel', {'id': cancel['id']}))
    stop(False)
    home = root / 'codex-home'
    home.mkdir(mode=0o700)
    (home / 'config.toml').write_text(config)
    (home / 'config.toml').chmod(0o600)
    shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
    (home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
    launch(1, True)
    finished = until(lambda: (r := row(first['id'])) and (r if r['state'] in ('completed', 'execution_failed') else None))
    record('cli-new-thread', finished)
    assert finished['state'] == 'completed'
    invalid = call('followup.register', {'when': {'jobId': scan['jobId']},
              'threadId': 'x25-missing-thread', 'instruction': 'Inspect the scan.'})['followup']
    record('invalid-thread', until(lambda: (r := row(invalid['id'])) and (r if r['state'] == 'execution_failed' else None)))
    busy = call('followup.register', {'when': {'event': 'library.file_added'},
           'threadId': finished['threadId'], 'title': 'File added while thread busy',
           'instruction': '请告诉用户：新文件已经进入索引。这次无需进一步操作。'})['followup']
    vm.chat('turn', text='请执行 python3 -c \'import time; time.sleep(20); print("busy finished")\'，然后只回复完成。')
    until(lambda: vm.chat('status')['liveness']['status'] == 'inProgress')
    shutil.copy2('/tmp/nipa-next/x25/Sintel-trailer.mp4', media / 'Sintel-controls.mp4')
    added = call('media.library.scan', {'root': str(media), 'requestId': 'controls-file'})['job']
    waiting = until(lambda: (r := row(busy['id'])) and (r if r['state'] == 'ready' else None))
    record('busy-pending', {'followup': waiting, 'chat': vm.chat('status')})
    assert 'active turn' in waiting['reason']
    record('busy-finished', until(lambda: (r := row(busy['id'])) and (r if r['state'] in ('completed', 'execution_failed') else None)))
    ids_before = {r['id']: r['turnId'] for r in call('followup.list', {})['followups']}
    stop(True)
    launch(2, True)
    time.sleep(4)
    ids_after = {r['id']: r['turnId'] for r in call('followup.list', {})['followups']}
    record('one-shot-after-restart', {'before': ids_before, 'after': ids_after, 'chat': vm.chat('status')})
    assert ids_before == ids_after and vm.chat('status')['header']['threadId'] is None
    activity = call('state.query', {'view': 'activity', 'limit': 1000})
    (evidence / 'controls-activity.json').write_text(json.dumps(activity, ensure_ascii=False, indent=2))
finally:
    try:
        stop((root / 'codex-home/config.toml').exists())
    finally:
        path = root / 'chat-events.jsonl'
        if path.exists():
            text = path.read_text()
            for token in tokens:
                assert token not in text
            (evidence / 'controls-chat.jsonl').write_text(text)
        shutil.rmtree(root)
        record('cleanup', {'rootAbsent': not root.exists(), 'pidStopped': app is None or app.poll() is not None})
