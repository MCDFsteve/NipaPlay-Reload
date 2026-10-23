"""S 线真实实例验收；须从 experiment.sh 在 mac-lab.lock 下调用。"""
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
evidence = Path(__file__).parent
private = workspace / '.dart_tool/pc-sources-lab'
fixtures = json.loads((private / 'fixtures.json').read_text())
profile = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles/core-lab-s'
log_path = private / 'run.log'
records = []
secrets = [v for f in fixtures.values() for k, v in f.items()
           if k in ('password', 'token') and isinstance(v, str)]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def scrub(value):
    if isinstance(value, str):
        for secret in secrets:
            value = value.replace(secret, '<redacted>')
        value = re.sub(r'(?i)(api_key|token|password|auth)=([^&\s]+)', r'\1=<redacted>', value)
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    return value


def record(label, value):
    records.append({'label': label, 'value': scrub(value)})
    (evidence / ('operations-' + mode + '.json')).write_text(
        json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(scrub(value), ensure_ascii=False), flush=True)


def rpc(method, **params):
    url = vm_url + method + '?' + urllib.parse.urlencode(params)
    with opener.open(url, timeout=90) as response:
        result = json.load(response)
    if 'error' in result:
        raise RuntimeError(scrub(str(result['error'])))
    return result['result']


def call(action, inputs=None, save=True):
    result = rpc('ext.nipaplay.nextui', isolateId=isolate, op='guicall',
                 action=action, input=json.dumps(inputs or {}))
    if save:
        record(action, result)
    if 'failure' in result:
        raise RuntimeError(scrub(str(result)))
    return result.get('result', result)


def state(save=False):
    result = call('playback.state', save=save)
    return result.get('state', result)


def wait_for(predicate, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = state()
        if value.get('error'):
            record('failed state', value)
            raise RuntimeError('Native playback failed')
        if predicate(value):
            return value
        time.sleep(.3)
    record('timeout state', state())
    raise RuntimeError('Playback condition timed out')


def capture(name):
    result = subprocess.run(['./nipa', 'call', 'ui.capture', '{}'],
        cwd=profile / 'harness', env=env, capture_output=True, text=True, timeout=60)
    value = json.loads(result.stdout)
    if result.returncode:
        raise RuntimeError(scrub(str(value)))
    value = value.get('result', value)
    shutil.copy2(value['path'], evidence / (name + '.png'))
    record('capture', name + '.png')


def setting(key, value):
    return call('settings.set', {'key': key, 'value': value, 'reason': 'S 线一次性实验验收'})


def open_media(path, position=0):
    call('playback.open', {'path': path, 'startPositionMs': position})
    return wait_for(lambda s: s.get('ready') and s.get('durationMs', 0) > 0)


def remote(kind, path):
    f = fixtures[kind]
    prefix = '/emby' if kind == 'emby' else ''
    request = urllib.request.Request(f['baseUrl'] + prefix + path,
        headers={'X-Emby-Token': f['token']})
    with opener.open(request, timeout=10) as response:
        return json.load(response)


def check_progress(kind):
    time.sleep(6)
    local = state()
    sessions = remote(kind, '/Sessions')
    matches = [s for s in sessions if s.get('NowPlayingItem', {}).get('Id') == fixtures[kind]['episodeIds'][0]]
    assert matches, 'Server does not show the playing item'
    server_ms = matches[-1]['PlayState']['PositionTicks'] / 10000
    difference = abs(server_ms - local['positionMs'])
    record(kind + ' progress comparison', {'localMs': local['positionMs'],
        'serverMs': server_ms, 'differenceMs': difference})
    assert difference <= 10000


def servers():
    for kind in ('jellyfin', 'emby'):
        setting('player.playbackEndAction', 'pause')
        path = kind + '://' + fixtures[kind]['episodeIds'][0]
        open_media(path)
        call('playback.playlist')
        call('playback.seek', {'positionMs': 52000})
        wait_for(lambda s: s['positionMs'] >= 51000)
        options = call('playback.stream_options')
        tracks = options['versions'][0]['tracks']
        audio = [t for t in tracks if t['kind'] == 'audio']
        assert len(audio) >= 2
        call('playback.select_stream', {'audioIndex': audio[1]['index']})
        wait_for(lambda s: s['positionMs'] >= 51000)
        call('playback.tracks')
        info = call('playback.info', save=False)
        active = info['kernelDetails']['media']['activeAudio']
        record(kind + ' native audio selection', active)
        assert active == [1]
        capture(kind + '-audio-seek')
        check_progress(kind)
        before = state()
        call('playback.select_stream', {'quality': 'bandwidth1m', 'transcode': True})
        after = wait_for(lambda s: s.get('ready') and s['positionMs'] >= before['positionMs'] - 3000)
        record(kind + ' quality position', {'beforeMs': before['positionMs'], 'afterMs': after['positionMs']})
        assert abs(after['positionMs'] - before['positionMs']) <= 10000
        call('playback.stream_options')
        capture(kind + '-transcode')
        check_progress(kind)
        call('playback.close')
        cleanup_started = time.monotonic()
        while True:
            processes = subprocess.check_output(['docker', '--context', 'colima-nipa-test',
                'top', 'nipa-pcs-' + kind, '-eo', 'pid,comm'], text=True)
            transcoders = sum('ffmpeg' in line for line in processes.splitlines()[1:])
            if transcoders == 0 or time.monotonic() - cleanup_started > 10:
                break
            time.sleep(.2)
        record(kind + ' transcoders after close', {'count': transcoders,
            'elapsedMs': round((time.monotonic() - cleanup_started) * 1000)})
        assert transcoders == 0


def files():
    for kind, prefix in [('webdav', 'webdav://pcs-dav/'), ('smb', 'smb://pcs-smb/media/')]:
        path = prefix + 'Sintel Lab/Season 01/Sintel Lab S01E01.mkv'
        open_media(path)
        call('playback.seek', {'positionMs': 53000})
        wait_for(lambda s: s['positionMs'] >= 52000)
        call('playback.set_paused', {'paused': True})
        before = state()
        capture(kind + '-seek')
        call('playback.close')
        call('playback.open', {'path': path})
        resumed = wait_for(lambda s: s.get('ready') and s['positionMs'] >= 52000)
        record(kind + ' resume', {'beforeMs': before['positionMs'], 'afterMs': resumed['positionMs'], 'path': resumed['path']})
        assert abs(resumed['positionMs'] - before['positionMs']) <= 5000
        call('playback.playlist')
        call('playback.close')


def endings(actions=('pause', 'loop', 'exitPlayer', 'autoNext', 'cancel')):
    path = 'jellyfin://' + fixtures['jellyfin']['episodeIds'][0]
    setting('player.autoNextCountdownSeconds', 4)
    for action in actions:
        setting('player.playbackEndAction', 'autoNext' if action == 'cancel' else action)
        opened = open_media(path)
        sid = opened['sessionId']
        call('playback.seek', {'positionMs': opened['durationMs'] - 1600})
        if action == 'pause':
            result = wait_for(lambda s: s.get('paused') and s['positionMs'] > 85000)
            capture(('transcode-' if mode.startswith('transcode_') else '') + 'end-pause')
        elif action == 'loop':
            result = wait_for(lambda s: s['positionMs'] < 10000)
            result = wait_for(lambda s: 12000 < s['positionMs'] < 20000 and not s.get('paused'))
            native = call('playback.info', save=False)['kernelDetails']['positionMs']
            record('loop native position', native)
            assert abs(native - result['positionMs']) <= 1500
            capture(('transcode-' if mode.startswith('transcode_') else '') + 'end-loop')
        elif action == 'exitPlayer':
            result = wait_for(lambda s: not s.get('hasVideo'))
        else:
            result = wait_for(lambda s: s.get('autoNext') is not None)
            capture(('transcode-' if mode.startswith('transcode_') else '') + 'end-' + action)
            if action == 'cancel':
                call('playback.cancel_auto_next')
                time.sleep(5)
                result = state()
                assert result['sessionId'] == sid and result.get('autoNext') is None
                assert result['paused'] and result['positionMs'] > 85000
            else:
                result = wait_for(lambda s: s.get('sessionId') != sid and s.get('ready'))
                assert result['path'] == 'jellyfin://' + fixtures['jellyfin']['episodeIds'][1]
        record('end action ' + action, result)
        call('playback.close')


def all_sources():
    servers()
    files()
    endings()


def transcode_endings(actions=('pause', 'loop', 'exitPlayer', 'autoNext', 'cancel')):
    path = 'jellyfin://' + fixtures['jellyfin']['episodeIds'][0]
    setting('player.playbackEndAction', 'pause')
    open_media(path)
    call('playback.select_stream', {'quality': 'bandwidth1m', 'transcode': True})
    wait_for(lambda s: s.get('ready'))
    call('playback.stream_options')
    call('playback.close')
    endings(actions)


def transcode_loop():
    transcode_endings(('loop',))


def performance():
    setting('player.playbackEndAction', 'pause')
    path = 'jellyfin://' + fixtures['jellyfin']['episodeIds'][0]
    open_media(path)
    call('playback.select_stream', {'quality': 'bandwidth1m', 'transcode': True})
    call('playback.seek', {'positionMs': 10000})
    wait_for(lambda s: s.get('ready') and s['positionMs'] >= 9500)
    time.sleep(2)
    assert call('playback.stream_options')['isTranscoding']
    rpc('ext.nipaplay.player.perf', isolateId=isolate, op='reset')
    before = state()
    for _ in range(2):
        time.sleep(30)
    after = state()
    record('sustained playback', {'beforeMs': before['positionMs'],
        'afterMs': after['positionMs'], 'sessionId': after['sessionId']})
    assert after['sessionId'] == before['sessionId']
    assert after['positionMs'] - before['positionMs'] >= 58000
    capture('transcode-sustained')
    for _ in range(5):
        call('playback.set_paused', {'paused': True})
        call('playback.set_paused', {'paused': False})
    call('playback.close')


mode = sys.argv[1] if len(sys.argv) > 1 else 'servers'
env = os.environ.copy()
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
    env.pop(key, None)
env.update(NIPAPLAY_PROFILE='core-lab-s', NIPAPLAY_LAB_DHT='0',
    CODEX_CA_CERTIFICATE=str(profile / 'system-ca.pem'), SSL_CERT_FILE=str(profile / 'system-ca.pem'),
    NIPAPLAY_ENDPOINT_FILE=str(profile / 'endpoint.json'), NO_PROXY='localhost,127.0.0.1')
prefs_path = profile / 'preferences.json'
if not (private / 'preferences-before.json').exists():
    shutil.copy2(prefs_path, private / 'preferences-before.json')
prefs = {'flutter.labs_enable_agent_endpoint': True, 'flutter.labs_use_next_interface': True,
    'flutter.player_kernel': 'FVP', 'flutter.player_volume': 0.0, 'flutter.external_player_enabled': False,
    'flutter.skip_danmaku_matching': True, 'flutter.downloader_enabled': False,
    'flutter.auto_sync_enabled': False}
profiles = []
for kind in ('jellyfin', 'emby'):
    f = fixtures[kind]
    identity = 'pcs-' + kind
    profiles.append({'id': identity, 'serverName': 'S disposable ' + kind, 'serverType': kind,
        'username': f['username'], 'serverId': f['serverId'], 'userId': f['userId'], 'accessToken': f['token'],
        'lastSuccessfulAddressId': identity + '-a', 'addresses': [{'id': identity + '-a',
        'url': f['baseUrl'], 'name': 'loopback', 'priority': 0, 'isEnabled': True}]})
    prefs['flutter.' + kind + '_current_profile_id'] = identity
prefs['flutter.server_profiles'] = json.dumps(profiles)
prefs['flutter.webdav_connections'] = json.dumps([{'id': 'pcs-dav', 'name': 'S disposable DAV',
    **fixtures['webdav'], 'isConnected': True}])
prefs['flutter.smb_connections'] = json.dumps([{'id': 'pcs-smb', 'name': 'S disposable SMB',
    **fixtures['smb'], 'domain': '', 'isConnected': True}])
prefs_path.write_text(json.dumps(prefs))
prefs_path.chmod(0o600)
front = subprocess.check_output(['lsappinfo', 'front'], text=True).strip()
exe = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
with log_path.open('w') as log:
    process = subprocess.Popen([str(exe)], cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(240):
            assert process.poll() is None, 'Experiment instance exited'
            text = log_path.read_text(errors='replace')
            matches = re.findall(r'Dart VM service is listening on (http://[^\s]+)', text)
            if matches:
                vm_url = matches[-1]
                try:
                    isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')
                    subprocess.run(['python3', str(Path.home() / '.nipa-next/labmute.py'), str(log_path)],
                        check=True, env=env, timeout=70)
                    break
                except (OSError, subprocess.CalledProcessError, StopIteration):
                    pass
            time.sleep(.5)
        else:
            raise RuntimeError('Lab endpoint did not start')
        record('instance', {'pid': process.pid, 'profile': 'core-lab-s', 'frontBefore': front})
        rpc('ext.nipaplay.player.perf', isolateId=isolate, op='reset')
        globals()[mode]()
        record('player perf', rpc('ext.nipaplay.player.perf', isolateId=isolate, op='read'))
    finally:
        try:
            record('responsive at end', state())
        except Exception as error:
            record('final response error', type(error).__name__)
        record('frontAfter', subprocess.check_output(['lsappinfo', 'front'], text=True).strip())
        record('main isolate blocked', [line for line in log_path.read_text(errors='replace').splitlines()
            if 'main isolate blocked' in line])
        process.terminate()
        process.wait(timeout=40)
        record('instance stopped', {'pid': process.pid, 'exit': process.returncode})
