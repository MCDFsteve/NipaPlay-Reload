"""Real embedded CPA chat + X19 licensed trailer/BT TCP fixture.

Run in this worktree after a Debug build:
  mkdir -p /tmp/nipa-next/x25
  curl --noproxy '*' -fL https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4 -o /tmp/nipa-next/x25/Sintel-trailer.mp4
  python3 docs/next/evidence/x25/experiment.py online|restart
No installed application or normal application data is opened.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import sys
import time
import urllib.parse
import urllib.request

workspace = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM

mode = sys.argv[1]
assert mode in ('online', 'restart')
evidence = Path(__file__).parent
source = workspace / 'docs/next/evidence/x19/roundtrip.py'
fixture = source.read_text().split("profile = 'x19-downloads-'")[0]
fixture = fixture.replace('time.sleep(.04)', 'time.sleep(.8)')
fixture = fixture.replace("b'Sintel-trailer.mp4'", ("b'Sintel-X25-" + mode + ".mp4'"))
saved_args = sys.argv
sys.argv = [str(source), '/tmp/nipa-next/x25/Sintel-trailer.mp4']
namespace = {'__file__': str(source)}
exec(compile(fixture, str(source), 'exec'), namespace)
sys.argv = saved_args
profile = 'x25-' + mode + '-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
home = root / 'codex-home'
home.mkdir(mode=0o700)
config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
assert 'model = "deepseek-v4.1-flash"' in config
(home / 'config.toml').write_text(config)
(home / 'config.toml').chmod(0o600)
for name in ('auth.json',):
    path = Path.home() / '.codex' / name
    if path.exists():
        shutil.copy2(path, home / name)
(home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
downloads = root / 'data/downloads'
downloads.mkdir(parents=True)
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True,
    'flutter.downloader_enabled': True,
    'flutter.downloader_auto_scan_completed_tasks': False,
    'flutter.desktop_startup_window_state': 'maximized',
    'flutter.nipaplay_scanned_folders': [str(downloads)],
    'flutter.skip_danmaku_matching': True,
}))
env = os.environ.copy()
hosts = ['127.0.0.1', 'localhost']
for url in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config):
    host = urllib.parse.urlparse(url).hostname
    if host:
        hosts.append(host)
env.update(NIPAPLAY_PROFILE=profile, CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'),
           SSL_CERT_FILE=str(root / 'system-ca.pem'), NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
executable = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
records = []
samples = []
app = None
vm = None
endpoint = None
tokens = []
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def record(label, value):
    item = {'label': label, 'at': time.time(), 'value': value}
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    records.append(item)
    (evidence / (mode + '-operations.json')).write_text(json.dumps(records, ensure_ascii=False, indent=2))


def call(action, inputs):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs,
    }).encode(), headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=60) as response:
        result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']


def launch(index):
    global app, vm, endpoint
    old = endpoint['token'] if endpoint else None
    log_path = Path('/tmp/nipa-next/x25') / (mode + '-app-' + str(index) + '.log')
    log = log_path.open('w')
    app = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=subprocess.STDOUT)
    log.close()
    deadline = time.monotonic() + 90
    while True:
        assert app.poll() is None and time.monotonic() < deadline, 'startup failed'
        path = root / 'endpoint.json'
        if path.exists():
            current = json.loads(path.read_text())
            if current['token'] != old:
                endpoint = current
                tokens.append(current['token'])
                try:
                    vm = LabVM(log_path)
                    status = vm.chat('status')
                    break
                except RuntimeError:
                    pass
        time.sleep(.5)
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch', {'profile': profile, 'pid': app.pid, 'chat': status, 'index': index})


def stop():
    if app and app.poll() is None:
        try:
            vm.chat('close')
        except Exception as error:
            record('close-error', str(error))
        app.terminate()
        try:
            app.wait(timeout=15)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait(timeout=5)
        record('stopped', {'pid': app.pid, 'returncode': app.returncode})


def observe():
    status = vm.chat('status')
    jobs = call('task.list', {'type': 'download'})['jobs']
    followups = call('followup.list', {})['followups']
    sample = {'at': time.time(), 'header': status['header'], 'liveness': status['liveness'],
              'downloads': jobs, 'followups': followups}
    samples.append(sample)
    (evidence / (mode + '-samples.json')).write_text(json.dumps(samples, ensure_ascii=False, indent=2))
    return sample


def offline_transfer():
    """An independent BT client finishes the local output while NipaPlay is off.
    Does not change jobs, followups, receipts or rqbit session registrations.
    """
    output = downloads / ('Sintel-X25-' + mode + '.mp4')
    assert output.exists()
    before = hashlib.sha256(output.read_bytes()).hexdigest()
    assert before != hashlib.sha256(namespace['data']).hexdigest()
    with socket.create_connection(('127.0.0.1', namespace['peer_port'])) as sock:
        sock.settimeout(30)
        sock.sendall(b'\x13BitTorrent protocol' + b'\0' * 8 + namespace['infohash'] + b'-X25OFF-'.ljust(20, b'0'))
        namespace['receive'](sock, 68)
        with output.open('r+b') as file:
            for index, piece in enumerate(namespace['pieces']):
                for offset in range(0, len(piece), 16384):
                    length = min(16384, len(piece) - offset)
                    namespace['send'](sock, b'\x06' + struct.pack('!III', index, offset, length))
                    while True:
                        size = struct.unpack('!I', namespace['receive'](sock, 4))[0]
                        body = namespace['receive'](sock, size)
                        if body and body[0] == 7:
                            actual_index, actual_offset = struct.unpack('!II', body[1:9])
                            assert (actual_index, actual_offset, len(body) - 9) == (index, offset, length)
                            file.seek(index * namespace['piece_length'] + offset)
                            file.write(body[9:])
                            break
            file.flush()
            os.fsync(file.fileno())
    assert output.read_bytes() == namespace['data']
    record('completed-while-offline', {'appStopped': app.poll() is not None,
           'transport': 'independent BT TCP client to the same local seed peer',
           'sha256Before': before, 'sha256After': hashlib.sha256(output.read_bytes()).hexdigest(),
           'wire': namespace['wire'].copy()})
    # rqbit fastresume tracks only pieces received by its own process. Keep that
    # fixture cache as a backup so startup hashes the independent client's file.
    bitv = root / 'support/torrent_session' / (namespace['infohash'].hex() + '.bitv')
    backup = bitv.with_suffix('.bitv.x25-backup')
    if bitv.exists():
        bitv.rename(backup)
        record('fixture-full-recheck', {'cache': str(bitv), 'backup': str(backup),
               'reason': 'file was completed by an independent client while rqbit was off'})


try:
    launch(0)
    record('settings', call('settings.set', {'changes': [
        {'key': 'download.directory', 'value': str(downloads)},
        {'key': 'download.createFolderForTask', 'value': False},
    ]}))
    started = vm.chat('start')
    thread_id = started['thread']['id']
    source_url = 'http://127.0.0.1:' + str(namespace['http_port']) + '/sintel.torrent'
    text = '帮我下载这个种子 ' + source_url + ' ，下完以后加进媒体库，然后告诉我；下载时不用一直等着。'
    record('user-request', {'text': text, 'threadId': thread_id})
    first = vm.chat('turn', text=text)
    record('first-turn', first)
    deadline = time.monotonic() + 600
    while True:
        sample = observe()
        assert time.monotonic() < deadline, 'Agent did not register and finish the initial turn'
        if sample['followups'] and sample['liveness']['status'] not in ('inProgress', 'starting'):
            assert sample['downloads'] and sample['downloads'][0]['state'] not in ('succeeded', 'failed', 'cancelled')
            record('initial-turn-ended', sample)
            break
        time.sleep(2)
    if mode == 'restart':
        time.sleep(8)
        record('before-stop', observe())
        stop()
        offline_transfer()
        launch(1)
    deadline = time.monotonic() + 600
    while True:
        sample = observe()
        assert time.monotonic() < deadline, 'followup did not complete'
        followups = sample['followups']
        if all(row['state'] in ('completed', 'execution_failed', 'cancelled') for row in followups):
            record('followups-finished', sample)
            break
        time.sleep(2)
    output = downloads / ('Sintel-X25-' + mode + '.mp4')
    record('download-content', {'size': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                               'wire': namespace['wire'].copy()})
    record('library', call('state.query', {'view': 'library.files', 'limit': 100}))
    activity = call('state.query', {'view': 'activity', 'limit': 1000})
    (evidence / (mode + '-activity.json')).write_text(json.dumps(activity, ensure_ascii=False, indent=2))
    record('activity', {'rows': len(activity['rows']), 'warnings': activity['warnings']})
    record('same-thread', {'initial': thread_id, 'followupThreads': [r['threadId'] for r in followups],
           'followupTurns': [r['turnId'] for r in followups]})
finally:
    stop()
    events = root / 'chat-events.jsonl'
    if events.exists():
        text = events.read_text()
        for token in tokens:
            assert token not in text, 'endpoint credential found in redacted chat events'
        (evidence / (mode + '-chat.jsonl')).write_text(text)
        completed = []
        for line in text.splitlines():
            entry = json.loads(line)
            m = entry['m']
            if m.get('method') in ('item/completed', 'turn/started', 'turn/completed'):
                completed.append(entry)
        (evidence / (mode + '-transcript.json')).write_text(json.dumps(completed, ensure_ascii=False, indent=2))
    for server in (namespace['tracker'], namespace['peer_server']):
        server.shutdown()
        server.server_close()
    shutil.rmtree(root)
    record('cleanup', {'profile': profile, 'rootAbsent': not root.exists(),
                       'appStopped': app is None or app.poll() is not None})
