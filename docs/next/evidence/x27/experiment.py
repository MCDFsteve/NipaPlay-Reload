"""Real worktree process and CLI calls; all application writes use a disposable lab."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

workspace = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM

evidence = Path(__file__).parent
profile = 'a' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
media_a, media_b, empty = [root / 'data' / name for name in ('a', 'b', 'empty')]
for directory in (media_a, media_b, empty):
    directory.mkdir(parents=True)
fixture = media_a / 'one.mp4'
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
                'testsrc2=size=320x180:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=330',
                '-t', '120', '-c:v', 'mpeg4', '-q:v', '12', '-c:a', 'aac', str(fixture)], check=True)
for directory, name in ((media_a, 'two.mp4'), (media_b, 'three.mp4'), (media_b, 'four.mp4')):
    shutil.copyfile(fixture, directory / name)
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True,
    'flutter.downloader_enabled': False,
    'flutter.nipaplay_scanned_folders': [],
    'flutter.skip_danmaku_matching': True,
    'flutter.player_kernel_type': int(os.environ.get('X27_KERNEL', '2')),
    'flutter.labs_enable_erika_player_kernel': True,
    'flutter.use_hardware_decoder': os.environ.get('X27_HARDWARE') == '1',
}))
env = os.environ.copy()
for name in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
    env.pop(name, None)
env.update(NIPAPLAY_PROFILE=profile, NO_PROXY='127.0.0.1,localhost',
           no_proxy='127.0.0.1,localhost', CODEX_HOME=str(root / 'codex-home'),
           MPV_HOME=str(root / 'mpv-config'), XDG_CONFIG_HOME=str(root / 'config'))
log_path = Path('/tmp/nipa-next/x27-app.log')
records = []
app = None
vm = None
external_pid = None
window_probe = Path('/tmp/nipa-next/x27-windows')
subprocess.run(['swiftc', str(evidence / 'windows.swift'), '-o', str(window_probe)], check=True)


def record(label, value):
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    records.append({'label': label, 'at': time.time(), 'value': value})
    (evidence / 'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))


def call(action, inputs=None, allow_failure=False):
    cli_env = env.copy()
    cli_env['NIPAPLAY_ENDPOINT_FILE'] = str(root / 'endpoint.json')
    result = subprocess.run(['./nipa', 'call', action, json.dumps(inputs or {}, ensure_ascii=False)],
        cwd=root / 'harness', env=cli_env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=150)
    parsed = json.loads(result.stdout)
    record('nipa ' + action, parsed)
    if not allow_failure:
        assert parsed.get('status') == 'completed', parsed
    return parsed.get('result', parsed)


def observe(label):
    value = vm.rpc('ext.nipaplay.localOperations', isolateId=vm.isolate, op='observe')
    record(label, value)
    return value


def capture(label):
    value = call('ui.capture')
    target = evidence / (label + '.png')
    shutil.copyfile(value['path'], target)
    record('capture ' + label, {'artifact': str(target.relative_to(workspace)), 'bytes': value['bytes']})


def control(command, target='main', enabled=None):
    inputs = {'command': command, 'target': target}
    if enabled is not None:
        inputs['enabled'] = enabled
    call('window.control', inputs)
    time.sleep(2 if command == 'fullscreen' else .6)
    return call('window.state')


def native_windows(label):
    rows = json.loads(subprocess.check_output([str(window_probe), str(app.pid)], text=True))
    record(label, rows)
    for row in rows:
        if row['layer'] == 0 and row['onScreen'] and row['number'] != main_window_id:
            target = evidence / (label.replace(' ', '-') + '-' + str(row['number']) + '.png')
            result = subprocess.run(['screencapture', '-x', '-l', str(row['number']), str(target)], capture_output=True)
            record('native window capture', {'number': row['number'], 'saved': result.returncode == 0,
                'path': str(target.relative_to(workspace)) if result.returncode == 0 else None})


try:
    with log_path.open('w') as log:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
    for _ in range(480):
        if app.poll() is not None:
            raise RuntimeError('Worktree app exited; inspect the private app log.')
        try:
            vm = LabVM(log_path)
            if (root / 'endpoint.json').exists() and (root / 'harness/nipa').exists():
                break
        except (RuntimeError, OSError, KeyError):
            pass
        time.sleep(.25)
    else:
        raise RuntimeError('Lab endpoint did not start.')
    instance = call('app.instance')
    record('instance', instance)
    main_window_id = instance['windowId']
    assert vm.rpc('getVM')['pid'] == app.pid
    cli_env = env.copy()
    cli_env['NIPAPLAY_ENDPOINT_FILE'] = str(root / 'endpoint.json')
    described = subprocess.run(['./nipa', 'describe', 'window.control'], cwd=root / 'harness', env=cli_env,
        capture_output=True, text=True, check=True)
    record('nipa describe window.control', json.loads(described.stdout))
    call('media.library.roots.add', {'paths': [str(media_a), str(media_b), str(empty)]})
    call('media.library.roots.list')
    call('media.library.scan_classic', {'paths': [str(empty)], 'skipPreviouslyMatchedUnwatched': True})
    for path, anime_id, episode_id in ((fixture, 2701, 270101), (media_a / 'two.mp4', 2701, 270102),
        (media_b / 'three.mp4', 2702, 270201), (media_b / 'four.mp4', 2702, 270202)):
        record('fixture seed', vm.rpc('ext.nipaplay.localOperations', isolateId=vm.isolate,
            op='seed', path=str(path), animeId=anime_id, episodeId=episode_id))
    observe('Classic seeded state')
    call('playback.open', {'path': str(fixture)})
    time.sleep(3)
    call('playback.set_paused', {'paused': True})
    call('playback.levels', {'volume': .25, 'reason': '实验音量'})
    observe('Classic volume 25%')
    call('playback.levels', {'volume': .8, 'reason': '实验音量回读'})
    call('playback.state')
    call('settings.history', {'key': 'player.volume'})
    call('playback.levels', {'volume': .2, 'brightness': .4}, allow_failure=True)
    capture('playback')
    call('danmaku.send', {'text': '实验弹幕', 'mode': 'top', 'color': '#FFAA00'}, allow_failure=True)
    call('danmaku.send', {'text': '实验弹幕', 'color': '#ZZ0000'}, allow_failure=True)
    if os.environ.get('X27_WINDOWS') == '1':
        control('fullscreen', enabled=True)
        capture('fullscreen')
        control('fullscreen', enabled=False)
        control('always_on_top', enabled=True)
        control('always_on_top', enabled=False)
        control('fit_video')
        control('detached', target='player', enabled=True)
        observe('Classic detached state')
        control('show', target='player')
        control('always_on_top', target='player', enabled=True)
        control('always_on_top', target='player', enabled=False)
        control('fullscreen', target='player', enabled=True)
        native_windows('detached fullscreen')
        control('fullscreen', target='player', enabled=False)
        control('fit_video', target='player')
        control('pip', target='player', enabled=True)
        observe('Classic picture in picture')
        native_windows('picture in picture')
        control('pip', target='player', enabled=False)
        control('close', target='player')
        observe('Classic returned player')
        capture('returned')
        control('minimize')
        control('show')
        control('maximize')
        control('restore')
        control('tray')
        control('show')
        control('close')
        control('show')
    
    call('playback.close')
    call('playback.external_player_path', {'command': 'detect'})
    # Isolate mpv's configuration too. exec preserves the session PID.
    wrapper = root / 'data/mpv'
    wrapper.write_text('#!/bin/sh\nexec /opt/homebrew/bin/mpv --no-config --hwdec=no "$@"\n')
    wrapper.chmod(0o700)
    call('settings.set', {'changes': [
        {'key': 'player.externalPath', 'value': str(wrapper)},
        {'key': 'player.externalType', 'value': 'mpv'},
        {'key': 'player.externalEnabled', 'value': True},
        {'key': 'player.externalDanmakuOverlay', 'value': True},
        {'key': 'danmaku.skipMatching', 'value': False},
    ]})
    call('playback.open', {'path': str(fixture)})
    time.sleep(3)
    ext = call('playback.external_state')
    external_pid = ext.get('processId')
    call('playback.external.danmaku_state')
    call('playback.external.danmaku', {'style': {'opacity': .55, 'fontSize': 36, 'outlineWidth': 2,
        'stacking': True}, 'offsetSeconds': 40.125})
    time.sleep(1)
    record('Classic external ASS style and offset', [{'name': f.name,
        'lines': [line for line in f.read_text().splitlines() if line.startswith(('Style:', 'Dialogue:'))]}
        for f in root.rglob('*.ass')])
    call('playback.external.danmaku', {'rules': [
        {'operation': 'add', 'type': 'keyword', 'value': '蓝色'},
        {'operation': 'add', 'type': 'regex', 'value': '^实验'},
        {'operation': 'add', 'type': 'userId', 'value': 'fixture-one'}]})
    time.sleep(1)
    call('playback.external.danmaku_state')
    record('Classic external ASS blocked', [{'name': f.name, 'dialogueCount': f.read_text().count('Dialogue:')}
        for f in root.rglob('*.ass')])
    call('playback.external.danmaku', {'style': {'opacity': .1}, 'rules': [
        {'operation': 'add', 'type': 'regex', 'value': '['}]}, allow_failure=True)
    call('playback.external.danmaku_state')
    time.sleep(1)
    record('Classic external ASS after invalid rule', [{'name': f.name, 'dialogueCount': f.read_text().count('Dialogue:'),
        'hasFixtureOne': '蓝色的天空' in f.read_text(), 'hasFixtureTwo': '实验弹幕' in f.read_text()}
        for f in root.rglob('*.ass')])
    call('playback.external.danmaku', {'sync': 'to_user', 'reason': '保存实验会话样式'})
    observe('Classic external style written back')
    call('settings.history', {'keys': ['danmaku.opacity', 'danmaku.fontSize', 'danmaku.manualOffset']})
    call('settings.set', {'key': 'danmaku.opacity', 'value': .75})
    call('playback.external.danmaku', {'sync': 'from_user', 'offsetSeconds': 0, 'rules': [
        {'operation': 'remove', 'type': 'keyword', 'value': '蓝色'},
        {'operation': 'remove', 'type': 'regex', 'value': '^实验'},
        {'operation': 'remove', 'type': 'userId', 'value': 'fixture-one'}]})
    call('playback.external.danmaku_state')
    time.sleep(1)
    record('Classic external ASS restored', [{'name': f.name, 'dialogueCount': f.read_text().count('Dialogue:'),
        'hasFixtureOne': '蓝色的天空' in f.read_text(), 'hasFixtureTwo': '实验弹幕' in f.read_text()}
        for f in root.rglob('*.ass')])
    call('settings.set', {'key': 'player.externalConsoleWindowMode', 'value': True})
    time.sleep(1)
    call('window.state')
    control('show', target='external_list')
    capture('external-console')
    native_windows('external windows')
    control('close', target='external_list')
    control('close', target='external_controls')
    call('playback.external_state')
    call('settings.set', {'key': 'player.externalConsoleWindowMode', 'value': False})
    call('playback.close')
    external_pid = None

    call('history.remove', {'paths': [str(media_a / 'two.mp4')]})
    after_single = observe('Classic after single deletion')
    assert (media_a / 'two.mp4').exists()
    call('history.remove', {'animeIds': [2702]})
    observe('Classic after series deletion')
    assert (media_b / 'three.mp4').exists() and (media_b / 'four.mp4').exists()
    call('media.library.roots.remove', {'paths': [str(media_a)]})
    observe('Classic after root removal')
    assert fixture.exists()
    shutil.rmtree(empty)
    call('media.library.roots.cleanup')
    observe('Classic after missing root cleanup')
    call('state.query', {'view': 'activity', 'limit': 100, 'select': ['type', 'title', 'actor', 'origin', 'facts']})
    capture('final')
    call('app.quit')
    app.wait(timeout=20)
    record('quit observed', {'pid': app.pid, 'exitCode': app.returncode,
        'journalHasQuit': 'app.quit' in (root / 'documents/next/journal.jsonl').read_text()
            if (root / 'documents/next/journal.jsonl').exists() else any('app.quit' in f.read_text()
                for f in root.rglob('journal.jsonl'))})
except BaseException as error:
    record('experiment failure', {'type': type(error).__name__, 'message': str(error),
        'processExitCode': app.poll() if app else None})
    raise
finally:
    if external_pid:
        try: os.kill(external_pid, 15)
        except ProcessLookupError: pass
    if app and app.poll() is None:
        app.terminate()
        try: app.wait(timeout=15)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
    shutil.rmtree(root)
    record('cleanup', {'profile': profile, 'removed': not root.exists(), 'appExited': app is None or app.poll() is not None})
