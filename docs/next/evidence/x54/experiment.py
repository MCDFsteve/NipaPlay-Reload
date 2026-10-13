"""Real quiet playback using only this worktree and a fresh temporary LabProfile.

All generated test-pattern video, captions and comments are CC0-1.0.
No application activation, user data, accounts or login keychain access.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request

workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).parent
profile = f'x54-catalog-{os.getpid()}'
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
executable = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
phase = os.environ.get('X54_EXPERIMENT_PHASE', 'full')
events = []
app = None
assert not root.exists()
env = dict(os.environ)
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
    env.pop(key, None)
env.update(NIPAPLAY_PROFILE=profile, CODEX_HOME=str(root/'codex-home'),
           NIPAPLAY_ENDPOINT_FILE=str(root/'endpoint.json'))
env.pop('NIPAPLAY_LAB_QUIET', None)
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def record(name, value):
    events.append({'event': name, 'result': value})
    output_name = 'operations.json' if phase == 'full' else f'operations-{phase}.json'
    (evidence/output_name).write_text(json.dumps(events, ensure_ascii=False, indent=2))
    print(name, flush=True)
    return value


def wait_for(callback, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = callback()
        if value:
            return value
        time.sleep(.2)
    raise TimeoutError('Observation deadline exceeded')


def request(operation, action=None, inputs=None, log=True):
    endpoint = json.loads((root/'endpoint.json').read_text())
    fields = {'operation': operation}
    if action is not None:
        fields.update(action=action, input=inputs or {})
    req = urllib.request.Request(endpoint['url'], data=json.dumps(fields).encode(),
        headers={'Authorization': 'Bearer ' + endpoint['token'], 'Content-Type': 'application/json'})
    with opener.open(req, timeout=65) as response:
        result = json.load(response)
    return record(action or operation, result) if log else result


def call(action, inputs=None):
    outcome = request('call', action, inputs)
    assert outcome['status'] == 'completed', action + ': ' + json.dumps(outcome, ensure_ascii=False)
    return outcome['result']


try:
    media = root/'data/fixtures'
    media.mkdir(parents=True, mode=0o700)
    video = media/'cc0-pattern.mp4'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
        '-i', 'testsrc2=size=320x180:rate=24', '-t', '45', '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)], check=True)
    subtitle = media/'public-domain.srt'
    subtitle.write_text('1\n00:00:00,000 --> 00:00:08,000\nA public domain test pattern.\n\n'
        '2\n00:00:08,000 --> 00:00:16,000\nThis is the current line.\n\n'
        '3\n00:00:16,000 --> 00:00:25,000\nThe next line preserves context.\n')
    comments = media/'comments.json'
    comments.write_text(json.dumps({'comments': [
        {'sourceTimeMs': 10000, 'text': 'CC0 current comment', 'mode': 1, 'colorRgb': 16777215},
        {'sourceTimeMs': 11500, 'text': 'CC0 nearby comment', 'mode': 1, 'colorRgb': 16777215}]}))
    (root/'preferences.json').write_text(json.dumps({
        'flutter.labs_enable_agent_endpoint': True,
        'flutter.nipaplay_scanned_folders': [str(media)],
        'flutter.next_harness_path': str(root/'harness'),
        'flutter.skip_danmaku_matching': True,
        'flutter.danmaku_auto_load_strategy': 'disabled',
        'flutter.downloader_enabled': False,
        'flutter.web_server_auto_start': False,
        'flutter.remote_control_receiver_enabled': False,
        'flutter.auto_check_update': False,
        'flutter.player_kernel_type': 2,
        'flutter.player_end_action': 'pause',
    }))
    with (root/'app.log').open('w') as output:
        app = subprocess.Popen([str(executable)], cwd=workspace, env=env,
            stdout=output, stderr=subprocess.STDOUT)
    wait_for(lambda: (root/'endpoint.json').exists(), 90)
    instance = call('app.instance')
    assert instance['pid'] == app.pid
    record('isolated-instance', {'profile': profile, 'pid': app.pid,
        'executable': str(executable), 'quiet': True, 'license': 'CC0-1.0'})
    if phase in ('full', 'catalog'):
        for family in ('media.entities', 'playback', 'subtitle', 'danmaku'):
            request('describe', family)
        job = call('media.library.scan', {'root': str(media), 'requestId': 'x54-scan'})['job']['jobId']
        wait_for(lambda: request('call','task.get',{'jobId':job},log=False)['result']['job']['state'] in ('succeeded','failed'), 30)
        scanned = call('task.get', {'jobId': job})
        assert scanned['job']['state'] == 'succeeded'
        files = call('state.query', {'view': 'library.files'})
        # state.query returns rows, not an undocumented private database read.
        rows = files.get('rows', files.get('items', []))
        file_id = next(row['fileId'] for row in rows if row.get('path') == str(video) or row.get('locator') == str(video))
        call('media.entities.put_batch', {'requestId': 'x54-create', 'reason': 'CC0 local-only collection', 'entries': [
            {'kind': 'work', 'entityId': 'x54-home', 'title': 'CC0 Home Videos'},
            {'kind': 'release', 'entityId': 'x54-release', 'parentId': 'x54-home', 'title': 'Test Collection'},
            {'kind': 'episode', 'entityId': 'x54-episode', 'parentId': 'x54-release',
             'title': 'Test Pattern', 'number': '1', 'fileIds': [file_id]},
            *([{'kind': 'episode', 'entityId': 'x54-bonus', 'parentId': 'x54-release',
                'title': 'Same-file Bonus', 'number': '2', 'fileIds': [file_id]}]
              if phase == 'catalog' else []),
        ]})
        call('media.library.work', {'workId': 'x54-home'})
        opened = call('playback.open', {'path': str(video), 'startPositionMs': 0})
        session = opened['state']['sessionId']
        ready = call('playback.wait', {'sessionId': session, 'until': 'ready', 'timeoutMs': 10000})
        assert ready['outcome'] == 'matched'
        time.sleep(.5)
        moving = call('playback.state')['state']
        assert moving['ready'] is True and moving['positionMs'] > 0
        if phase == 'catalog':
            call('playback.seek', {'positionMs': 10000})
            call('playback.set_paused', {'paused': True})
            wait_for(lambda: abs(request('call','playback.state',log=False)['result']['state']['positionMs']-10000)<1000)
            call('playback.close')
            call('media.library.import_history')
            work = call('media.library.work', {'workId': 'x54-home'})
            removal = {'entityIds': ['x54-home'], 'requestId': 'x54-remove', 'reason': 'Test reversible unlink after playback history sync'}
            preview = call('media.entities.remove_batch', removal)
            episode = next(item for item in preview['preview'] if item['entity']['id'] == 'x54-episode')
            assert len(episode['files']) == 1
            assert episode['files'][0]['link']['relation'] == 'local_catalog'
            progress = episode['files'][0]['progress'][0]
            assert progress['observed'] is True and progress['lastPosition'] > 0
            receipt = call('media.entities.remove_batch', {**removal, 'preview': False, 'expectedPlan': preview['expectedPlan']})
            assert video.exists()
            call('media.entities.restore', {'undoId': receipt['undoId']})
            restored = call('media.library.work', {'workId': 'x54-home'})
            restored_episodes = restored['work']['releases'][0]['episodes']
            assert len(restored_episodes) == 2
            assert all(e['files'][0]['relation'] == 'local_catalog' for e in restored_episodes)
            record('experiment-complete', {'phase': phase, 'localCatalogPlayed': True,
                'associationSurvivesHistorySync': True, 'previewObservedProgress': progress,
                'removalRetainsFile': video.exists(), 'restoredAssociation': True,
                'sharedFileRestoredEpisodes': len(restored_episodes)})
            raise SystemExit(0)
        imported = call('subtitle.import', {'entries': [{'fileId': file_id, 'filePath': str(subtitle),
            'language': 'en', 'title': 'CC0 captions', 'source': {'label': 'CC0-1.0 experimenter'}}]})['entries'][0]['track']
        call('subtitle.select', {'fileId': file_id, 'trackId': imported['id']})
        call('danmaku.import', {'entityId': file_id, 'filePath': str(comments), 'platform': 'x54-cc0', 'platformVideoId': 'pattern'})
        call('playback.seek', {'positionMs': 10000})
        call('playback.set_paused', {'paused': True})
        wait_for(lambda: abs(request('call','playback.state',log=False)['result']['state']['positionMs']-10000)<1000)
        cues = call('subtitle.cues', {'sessionId': session, 'context': 1})
        assert any(item['current'] and 'current line' in item['text'] for item in cues['items'])
        danmaku = call('danmaku.entries', {'sessionId': session, 'windowMs': 3000})
        assert len(danmaku['items']) == 2
        call('playback.chapters')
        call('playback.playlist')
        call('playback.navigate', {'sessionId': session, 'frameDelta': -1})
        facts = call('subtitle.tracks', {'fileIds': [file_id]})['files'][0]
        edited = call('subtitle.update', {'entries': [{'fileId': file_id, 'trackId': imported['id'],
            'expectedRevision': facts['revision'], 'patch': {'language': 'zh-Hant', 'title': 'CC0 corrected language', 'source': {'label': 'CC0 corrected declaration'}}}]})
        assert edited['entries'][0]['facts']['tracks'][-1]['language'] == 'zh-Hant'
        reset = call('subtitle.reset_selection', {'entries': [{'fileId': file_id}]})
        assert reset['entries'][0]['facts']['selection']['basis'] != 'explicit'
        facts = call('subtitle.tracks', {'fileIds': [file_id]})['files'][0]
        call('subtitle.remove', {'entries': [{'fileId': file_id, 'trackId': imported['id'], 'expectedRevision': facts['revision']}]})
        tracks = call('playback.tracks')
        assert not any(t.get('path') == imported['path'] and t.get('selected') for t in tracks['tracks'])
        call('playback.open', {'path': str(video), 'startPositionMs': 0})
        facts = call('subtitle.tracks', {'fileIds': [file_id]})['files'][0]
        assert not any(t['id'] == imported['id'] or t.get('path') == imported['path'] for t in facts['tracks'])
    broken = media/'retry.mp4'
    broken.write_bytes(b'An intentionally corrupt CC0 fixture, not media.')
    failed_open = call('playback.open', {'path': str(broken)})
    failure_session = failed_open['state']['sessionId']
    failed = call('playback.wait', {'sessionId': failure_session, 'until': 'error', 'timeoutMs': 10000})
    assert failed['outcome'] == 'matched' and failed['state']['error']
    shutil.copyfile(video, broken)
    retry = call('playback.retry', {'sessionId': failure_session, 'preservePosition': False})
    recovered = call('playback.wait', {'sessionId': retry['state']['sessionId'], 'until': 'ready', 'timeoutMs': 10000})
    assert recovered['outcome'] == 'matched'
    stale = call('playback.wait', {'sessionId': failure_session, 'until': 'ready', 'timeoutMs': 1000})
    assert stale['outcome'] == 'session_changed'
    if phase == 'retry':
        call('playback.seek', {'positionMs': 7000})
        call('playback.set_paused', {'paused': True})
        wait_for(lambda: abs(request('call','playback.state',log=False)['result']['state']['positionMs']-7000)<500)
        session = call('playback.state')['state']['sessionId']
        preserved = call('playback.retry', {'sessionId': session, 'preservePosition': True})
        call('playback.wait', {'sessionId': preserved['state']['sessionId'], 'until': 'paused', 'timeoutMs': 5000})
        assert abs(call('playback.state')['state']['positionMs']-7000)<500
        restarted = call('playback.retry', {'sessionId': preserved['state']['sessionId'], 'preservePosition': False})
        call('playback.wait', {'sessionId': restarted['state']['sessionId'], 'until': 'paused', 'timeoutMs': 5000})
        assert call('playback.state')['state']['positionMs']<500
    call('playback.close')
    if phase == 'full':
        removal = {'entityIds': ['x54-home'], 'requestId': 'x54-remove', 'reason': 'Test reversible unlink'}
        preview = call('media.entities.remove_batch', removal)
        receipt = call('media.entities.remove_batch', {**removal, 'preview': False, 'expectedPlan': preview['expectedPlan']})
        assert video.exists()
        call('media.entities.restore', {'undoId': receipt['undoId']})
    record('experiment-complete', {'phase': phase, 'localCatalogPlayed': phase == 'full', 'loadFailureRecovered': True,
        'subtitleEditedDetachedReset': phase == 'full', 'currentCuesAndDanmakuRead': phase == 'full'})
finally:
    if app is not None:
        app.terminate()
        try:
            app.wait(timeout=15)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait(timeout=5)
    shutil.rmtree(root)
    record('cleanup', {'pidStopped': app is None or app.poll() is not None, 'profileRemoved': not root.exists()})
