"""两台安静的真实实例，回环协调器与测试网关；数据库仅在实例停止时准备。"""
import base64
import functools
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).parent
private = workspace / '.dart_tool/pc-sources-lab/mesh'
private.mkdir(parents=True, exist_ok=True, mode=0o700)
base = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles'
roots = {name: base / ('core-lab-s' + ('' if name == 'main' else '-peer')) for name in ('main', 'peer')}
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
exe = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
coordinator_exe = workspace / 'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator'
records, processes = [], []


def record(label, value):
    def redact(value):
        if isinstance(value, str):
            return re.sub(r'(http://127\.0\.0\.1:\d+/)[A-Za-z0-9_-]{40,}/', r'\1<grant>/', value)
        if isinstance(value, dict):
            return {key: redact(item) for key, item in value.items()}
        if isinstance(value, list):
            return [redact(item) for item in value]
        return value
    value = redact(value)
    records.append({'label': label, 'value': value})
    (evidence / 'operations-mesh.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def rpc(name, method, **params):
    with opener.open(instances[name]['url'] + method + '?' + urllib.parse.urlencode(params), timeout=75) as response:
        value = json.load(response)
    if 'error' in value:
        raise RuntimeError(str(value['error']))
    return value['result']


def call(name, action, inputs=None, save=True):
    value = rpc(name, 'ext.nipaplay.nextui', isolateId=instances[name]['isolate'],
        op='guicall', action=action, input=json.dumps(inputs or {}))
    if save:
        record(name + ' ' + action, value)
    if 'failure' in value:
        raise RuntimeError(str(value))
    return value.get('result', value)


def state(name='main'):
    result = call(name, 'playback.state', save=False)
    return result.get('state', result)


def configure():
    for name, root in roots.items():
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not (root / 'system-ca.pem').exists():
            shutil.copy2(roots['main'] / 'system-ca.pem', root / 'system-ca.pem')
        prefs_file = root / 'preferences.json'
        prefs = json.loads(prefs_file.read_text()) if prefs_file.exists() else {}
        prefs.update({'flutter.labs_enable_agent_endpoint': True,
            'flutter.labs_use_next_interface': True, 'flutter.player_kernel': 'FVP',
            'flutter.player_volume': 0.0, 'flutter.skip_danmaku_matching': True,
            'flutter.downloader_enabled': False, 'flutter.auto_sync_enabled': False,
            'flutter.remote_control_receiver_enabled': True,
            'flutter.dandanplay_token': token})
        prefs_file.write_text(json.dumps(prefs)); prefs_file.chmod(0o600)
        vault_file = root / 'credential-vault.json'
        vault = json.loads(vault_file.read_text()) if vault_file.exists() else {}
        vault['11:preferencesdandanplay_token'] = token
        vault_file.write_text(json.dumps(vault)); vault_file.chmod(0o600)
        data = root / 'data/next'
        data.mkdir(parents=True, exist_ok=True)
        (data / 'mesh.json').write_text(json.dumps({'coordinator': coordinator_url,
            'name': 'S Lab ' + name, 'loopbackOnly': True, 'broadcastDiscovery': False,
            'port': ports[name], 'addresses': [{'kind': 'manual', 'host': '127.0.0.1',
                'port': ports[name]}]}))


def launch(round_name):
    global instances
    instances = {}
    for name, root in roots.items():
        env = clean_env.copy()
        env.update(NIPAPLAY_PROFILE=root.name, NIPAPLAY_LAB_DHT='0',
            NIPAPLAY_MESH_DEV_CA=str(private / 'ca.pem'),
            CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
            NIPAPLAY_ENDPOINT_FILE=str(root / 'endpoint.json'))
        log_path = private / (name + '-' + round_name + '.log')
        log = log_path.open('w')
        process = subprocess.Popen([str(exe)], cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
        processes.append((process, log))
        instances[name] = {'process': process, 'log': log_path, 'env': env}
        for _ in range(180):
            assert process.poll() is None, name + ' exited'
            matches = re.findall(r'Dart VM service is listening on (http://[^\s]+)', log_path.read_text(errors='replace'))
            if matches:
                instances[name]['url'] = matches[-1]
                try:
                    instances[name]['isolate'] = next(i['id'] for i in rpc(name, 'getVM')['isolates'] if i['name'] == 'main')
                    subprocess.run(['python3', str(Path.home() / '.nipa-next/labmute.py'), str(log_path)],
                        check=True, env=env, timeout=75)
                    break
                except (OSError, subprocess.CalledProcessError, StopIteration):
                    pass
            time.sleep(.5)
        else:
            raise RuntimeError('Lab startup timed out')
        record('instance ' + round_name, {'name': name, 'pid': process.pid, 'profile': root.name})


def stop_instances():
    for name, inst in instances.items():
        if inst['process'].poll() is None:
            try:
                record(name + ' responsive', state(name))
            except Exception as error:
                record(name + ' response failure', type(error).__name__)
            inst['process'].terminate()
            inst['process'].wait(timeout=40)
        lines = inst['log'].read_text(errors='replace').splitlines()
        record(name + ' main isolate blocked', [line for line in lines if 'main isolate blocked' in line])
        record(name + ' stopped', inst['process'].returncode)


def seed_stopped_profiles():
    identities = {name: json.loads((root / 'data/next/mesh-identity.json').read_text())['deviceId']
        for name, root in roots.items()}
    assert identities['main'] != identities['peer']
    for name, root in roots.items():
        other = 'main' if name == 'peer' else 'peer'
        prefs_file = root / 'preferences.json'
        prefs = json.loads(prefs_file.read_text())
        prefs['flutter.remote_control_trusted_devices'] = json.dumps([{
            'clientKey': 'id:' + identities[other], 'clientId': identities[other], 'clientName': 'S Lab ' + other}])
        if name == 'peer':
            prefs['flutter.nipaplay_scanned_folders'] = [str(private / 'media')]
        prefs_file.write_text(json.dumps(prefs)); prefs_file.chmod(0o600)
    # Both apps have terminated here. Never inspect or mutate a running next.db.
    root = roots['peer'] / 'data/next'
    owner = json.loads((root / 'device.json').read_text())['deviceId']
    media = private / 'media'
    media.mkdir(exist_ok=True)
    database = sqlite3.connect(root / 'next.db')
    with database:
        def entity(identity, kind, parent, attributes):
            database.execute('INSERT OR REPLACE INTO media_entities(id,kind,parent_id,attributes) VALUES(?,?,?,?)',
                (identity, kind, parent, json.dumps(attributes)))
        entity('pcs-work', 'work', None, {'title': 'Sintel Mesh Lab'})
        entity('pcs-season', 'release', 'pcs-work', {'season': 1})
        for number in (1, 2):
            filename = f'Sintel Mesh S01E0{number}.mkv'
            path = media / filename
            shutil.copy2(private.parent / 'media/Sintel Lab/Season 01' / f'Sintel Lab S01E0{number}.mkv', path)
            path.with_suffix('.srt').write_text('1\n00:00:50,000 --> 00:01:10,000\nS 线 Mesh 对端字幕\n')
            path.with_suffix('.xml').write_text('<i><d p="52,1,25,16777215,0,0,s-lab,1">S 线 Mesh 对端弹幕</d></i>')
            episode, file_id = f'pcs-episode-{number}', f'pcs-file-{number}'
            entity(episode, 'episode', 'pcs-season', {'number': str(number), 'title': f'第 {number} 集', 'runtime': 1.5})
            entity(file_id, 'file', None, {'probe': {}, 'bindingRevision': 0,
                'name': filename, 'size': path.stat().st_size, 'durationMs': 90084})
            database.execute('INSERT OR REPLACE INTO media_locations(id,file_id,source,owner_device_id,locator,available) VALUES(?,?,?,?,?,1)',
                ('pcs-location-' + str(number), file_id, 'local', owner, str(path)))
            database.execute('INSERT OR REPLACE INTO media_file_episodes(file_id,episode_id,relation,ordinal,start_ms,end_ms) VALUES(?,?,?,?,0,90084)',
                (file_id, episode, 'exact', number))
    database.close()
    record('distinct identities', identities)


def merged(name):
    result = call(name, 'state.query', {'view': 'library.merged', 'limit': 100}, save=False)
    return {'rows': [row for row in result['rows'] if row.get('title') == 'Sintel Mesh Lab']}


def play():
    deadline = time.monotonic() + 65
    while time.monotonic() < deadline:
        result = merged('main')
        if any(row.get('episodes') and all(ep.get('playable') and
                (ep.get('device') or {}).get('online') for ep in row['episodes'])
                for row in result['rows']):
            break
        time.sleep(1)
    else:
        record('no merged work', result)
        call('main', 'mesh.devices', {'includeCatalog': False})
        raise RuntimeError('Peer catalogue unavailable')
    record('merged catalogue', result)
    # The merged view carries stable episode IDs; it never reads SQLite here.
    rows = result.get('items', result.get('rows', []))
    work = next(row for row in rows if row.get('title') == 'Sintel Mesh Lab')
    episodes = work['episodes']
    first = episodes[0].get('episodeId', episodes[0].get('id'))
    # Establish a fresh remote baseline so a previous run's persistent
    # observation cannot satisfy the playback progress assertion.
    call('main', 'media.library.progress', {'entries': [
        {'episodeId': first, 'progress': 0.0, 'positionMs': 0, 'durationMs': 90084}]})
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        peer = merged('peer')
        initial = [ep for row in peer['rows'] for ep in row.get('episodes', [])
                   if ep.get('number') == 1]
        if initial and all((ep.get('progress') or 0) < .01 for ep in initial):
            break
        time.sleep(1)
    else:
        raise RuntimeError('Peer did not receive the fresh zero baseline')
    record('peer progress before playback', peer)
    opened = call('main', 'ui.open', {'entityId': first})
    assert opened['interface'] == 'next'
    call('main', 'playback.seek', {'positionMs': 54000})
    time.sleep(2)
    assert state()['positionMs'] >= 53000
    call('main', 'playback.playlist')
    screenshot = subprocess.run(['./nipa', 'call', 'ui.capture', '{}'],
        cwd=roots['main'] / 'harness', env=instances['main']['env'], capture_output=True, text=True, timeout=60)
    captured = json.loads(screenshot.stdout)
    shutil.copy2(captured.get('result', captured)['path'], evidence / 'mesh-peer-seek.png')
    record('capture', 'mesh-peer-seek.png')
    call('main', 'playback.set_paused', {'paused': True})
    local = state()
    # Peer exchange uses its normal authenticated Mesh RPC and persistent
    # observations. Wait only in the driver, never add product polling.
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        peer = merged('peer')
        if any(.58 <= (ep.get('progress') or 0) <= .66
               for row in peer['rows'] for ep in row.get('episodes', [])
               if ep.get('number') == 1):
            break
        time.sleep(1)
    else:
        record('peer progress missing', peer)
        raise RuntimeError('Peer did not receive the real playback progress')
    record('peer progress after playback', {'localPositionMs': local['positionMs'], 'peer': peer})
    call('main', 'playback.switch_episode', {'direction': 'next'})
    following = call('main', 'playback.playlist')
    assert following['currentIndex'] == 1
    record('next episode', state())
    assert state()['path'] != local['path']
    assert state()['canPrevious']
    call('main', 'playback.switch_episode', {'direction': 'previous'})
    previous = call('main', 'playback.playlist')
    assert previous['currentIndex'] == 0
    record('previous episode', state())
    call('main', 'playback.close')
    record('player perf', rpc('main', 'ext.nipaplay.player.perf', isolateId=instances['main']['isolate'], op='read'))


clean_env = os.environ.copy()
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
    clean_env.pop(key, None)
clean_env.update(NO_PROXY='localhost,127.0.0.1', no_proxy='localhost,127.0.0.1')
encode = lambda value: base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
token = encode({'alg': 'EdDSA'}) + '.' + encode({'userId': 565656, 'testOnly': True}) + '.synthetic-test-signature'


class Gateway(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        accepted = self.path.startswith('/dandanplay/api/v2/playhistory') and self.headers.get('Authorization') == 'Bearer ' + token
        self.send_response(200 if accepted else 401)
        self.send_header('Content-Type', 'application/json'); self.end_headers()
        self.wfile.write(json.dumps({'success': accepted}).encode())

    def log_message(self, *args):
        pass


gateway = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Gateway)
threading.Thread(target=gateway.serve_forever, daemon=True).start()
if not (private / 'ca.pem').exists():
    subprocess.run([str(coordinator_exe), '--generate-dev-ca', str(private / 'ca.pem'), str(private / 'ca.key')], check=True)
coordinator_port = free_port()
coordinator_url = 'http://127.0.0.1:' + str(coordinator_port)
ports = {name: free_port() for name in roots}
coordinator_env = clean_env.copy()
coordinator_env.update(MESH_LISTEN_ADDR='127.0.0.1:' + str(coordinator_port),
    MESH_DATABASE_PATH=str(private / 'coordinator.db'), MESH_CA_CERT_FILE=str(private / 'ca.pem'),
    MESH_CA_KEY_FILE=str(private / 'ca.key'), MESH_ACCOUNT_CLAIM_POINTER='/userId',
    DANDANPLAY_GATEWAY_BASE='http://127.0.0.1:' + str(gateway.server_port) + '/dandanplay/')
front_before = subprocess.check_output(['lsappinfo', 'front'], text=True).strip()
instances = {}
with (private / 'coordinator.log').open('w') as coordinator_log:
    coordinator = subprocess.Popen([str(coordinator_exe)], env=coordinator_env,
        stdout=coordinator_log, stderr=subprocess.STDOUT)
    try:
        configure()
        if not all((root / 'data/next/mesh-identity.json').exists() for root in roots.values()):
            launch('bootstrap')
            stop_instances()
        seed_stopped_profiles()
        if 'bootstrap' not in sys.argv:
            launch('play')
            play()
    finally:
        stop_instances()
        coordinator.terminate(); coordinator.wait(timeout=20)
        gateway.shutdown(); gateway.server_close()
        record('foreground', {'before': front_before,
            'after': subprocess.check_output(['lsappinfo', 'front'], text=True).strip()})
        record('coordinator stopped', coordinator.returncode)
