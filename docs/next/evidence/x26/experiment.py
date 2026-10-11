"""Run the worktree executable in an isolated profile; never log credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.parse

workspace = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM

evidence = Path(__file__).parent
profile = 'x26-ui-' + str(os.getpid())
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
env = os.environ.copy()
env.update(NIPAPLAY_PROFILE=profile, HTTP_PROXY='http://127.0.0.1:7897',
           HTTPS_PROXY='http://127.0.0.1:7897', NO_PROXY='127.0.0.1,localhost',
           no_proxy='127.0.0.1,localhost', CODEX_HOME=str(root / 'codex-home'))
log_path = Path('/tmp/nipa-next/x26-app.log')
app = None
vm = None
records = []


def record(label, value):
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    records.append({'label': label, 'at': time.time(), 'value': value})
    (evidence / 'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))


def ui(op, **params):
    url = vm.url + 'ext.nipaplay.uiData?' + urllib.parse.urlencode({'isolateId':vm.isolate,'op':op,**params})
    with vm.opener.open(url, timeout=180) as response:
        data = json.load(response)
    if 'error' in data:
        raise RuntimeError(json.dumps(data['error'], ensure_ascii=False))
    return data['result']


def nipa(action, inputs, session=None, query=False, allow_failure=False):
    cli_env = env.copy()
    cli_env.update(NIPAPLAY_ENDPOINT_FILE=str(root / 'endpoint.json'))
    for name in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY', 'all_proxy'):
        cli_env.pop(name, None)
    if session:
        cli_env['NIPAPLAY_CHAT'] = session
    command = ['./nipa', 'query' if query else 'call', action, json.dumps(inputs, ensure_ascii=False)]
    result = subprocess.run(command, cwd=root / 'harness', env=cli_env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    parsed = json.loads(result.stdout)
    record(('query ' if query else 'call ') + action, parsed)
    if not allow_failure:
        assert result.returncode == 0 and parsed['status'] == 'completed', parsed
    return parsed.get('result', parsed)


try:
    log = log_path.open('w')
    app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                           cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
    for _ in range(240):
        if app.poll() is not None:
            raise RuntimeError('Worktree app exited; inspect the private app log.')
        try:
            vm = LabVM(log_path)
            ui('observations')
            if (root / 'endpoint.json').exists() and (root / 'harness/nipa').exists():
                break
        except (RuntimeError, OSError, KeyError):
            pass
        time.sleep(.25)
    else:
        raise RuntimeError('Lab endpoint did not start.')
    record('instance', {'profile': profile, 'pid': vm.rpc('getVM')['pid'], 'subprocessPid': app.pid})
    assert vm.rpc('getVM')['pid'] == app.pid
    record('credential', ui('credential'))
    works = nipa('media.metadata.search_batch', {'queries': [
        {'provider': 'tmdb', 'query': '葬送的芙莉莲'},
        {'provider': 'tmdb', 'query': '孤独摇滚'},
    ]})['results']
    chosen = []
    for group, expected in zip(works, ('209867', '119100')):
        chosen.append(next(r for r in group['records'] if r['ref']['externalId'] == expected))
    refs = [r['ref'] for r in chosen]
    fetched = nipa('media.metadata.get_batch', {'refs': refs})['results']
    seasons = [next(e for e in r['record']['episodes'] if e['season'] == 1)['ref'] for r in fetched]
    catalogues = nipa('media.metadata.get_batch', {'refs': seasons})['results']
    entries = []
    for wref, sref, catalogue in zip(refs, seasons, catalogues):
        for ep in catalogue['record']['episodes'][:2]:
            entries.append({'kind': 'episode', 'workRef': wref, 'releaseRef': sref,
                            'episodeRefs': [ep['ref']], 'reason': '核对真实目录后绑定。'})
    bound = nipa('media.identity.bind_batch', {'requestId': 'x26-catalogues', 'entries': entries})['entries']
    work_ids = list(dict.fromkeys(b['workId'] for b in bound))
    fixture = media / 'fixture-episode.mp4'
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i',
                    'color=c=blue:s=320x180:r=1','-t','1560','-c:v','mpeg4','-q:v','31',
                    str(fixture)],check=True)
    scan = nipa('media.library.scan',{'root':str(media),'requestId':'x26-fixture'})['job']
    for _ in range(100):
        scanned = nipa('task.get',{'jobId':scan['jobId']})['job']
        if scanned['state'] == 'succeeded': break
        time.sleep(.2)
    file_id = scanned['receipt']['details']['fileIds'][0]
    nipa('media.identity.bind_batch',{'requestId':'x26-fixture-bind','entries':[{
        'kind':'file','entityId':file_id,'workRef':refs[0],'releaseRef':seasons[0],
        'episodeRefs':[catalogues[0]['record']['episodes'][0]['ref']],
        'reason':'实验合成视频，用来观察观看进度。'}]})
    record('Classic history fixture',ui('history',path=str(fixture),durationMs='1560000',positionMs='1020000'))
    initial_home = ui('home')
    record('home initial', initial_home)
    continuing = next(s for s in initial_home['shelves'] if s['kind']=='continueWatching')
    assert continuing['items'][0]['caption']=='第 1 集 · 剩 9 分钟', continuing
    for work_id in work_ids:
        record('work ' + work_id, ui('work', workId=work_id))
        record('episodes ' + work_id, ui('episodes', workId=work_id))
    # Preserve decoded raster evidence before removing the temporary profile.
    image_dir = evidence / 'images'
    image_dir.mkdir(exist_ok=True)
    for index, work_id in enumerate(work_ids):
        w = ui('work', workId=work_id)
        for kind, path in w['artwork'].items():
            if isinstance(path, str):
                shutil.copy2(path, image_dir / (str(index) + '-' + kind + Path(path).suffix))
        for ep in ui('episodes', workId=work_id):
            if ep['still']:
                shutil.copy2(ep['still'], image_dir / (str(index) + '-episode-' + str(ep['number']) + Path(ep['still']).suffix))
        nipa('media.metadata.snapshots', {'entityId':work_id})
    episode_id = bound[0]['episodeIds'][0]
    comments = media / 'comments.json'
    def import_comments(times, platform, video):
        comments.write_text(json.dumps([{'sourceTimeMs': t, 'text': '实验弹幕', 'mode': 1,
            'colorRgb': 16777215, 'sourceEntryId': str(i)} for i, t in enumerate(times)]))
        return nipa('danmaku.import', {'filePath': str(comments), 'platform': platform,
                                     'platformVideoId': video, 'entityId': episode_id})
    import_comments([1000, 2000, 30000, 61000], 'bilibili', 'fixture-a')
    record('heat first source', ui('episodes', workId=work_ids[0])[0]['heat'])
    import_comments([1000, 61000, 62000], 'youku', 'fixture-b')
    record('heat two sources', ui('episodes', workId=work_ids[0])[0]['heat'])
    import_comments([1000, 2000, 3000, 4000, 61000], 'bilibili', 'fixture-a')
    record('heat after refresh', ui('episodes', workId=work_ids[0])[0]['heat'])
    record('changes after identity/artwork/danmaku', ui('observations'))
    nipa('ui.shelves.put', {'placement': 'hero', 'items': [{'workId': work_ids[0]}],
                          'note': '今晚一起走进芙莉莲的旅途。'})
    nipa('ui.shelves.put', {'placement': 'shelf', 'id': 'tonight', 'title': '适合今晚',
                          'items': [{'workId': work_ids[1], 'note': '听一场热闹的演出。'}]})
    # A real hook executor runs; only session metadata is simulated.
    hook = root / 'harness/hooks/playback.started'
    hook.write_text('#!/usr/bin/env python3\nimport sys,time\nsys.stdin.read()\ntime.sleep(12)\nprint("完成")\n')
    hook.chmod(0o700)
    job = ui('hook', workId=work_ids[0])['jobId']
    record('hook task', {'jobId': job})
    record('simulated session', ui('session', session='x26-session', threadId='x26-thread', turnId='x26-turn'))
    nipa('ui.present', {'cards': [
        {'kind': 'work', 'workId': work_ids[0]},
        {'kind': 'episode', 'episodeId': episode_id},
        {'kind': 'candidates', 'items': [{'workId': work_ids[1], 'reason': '想听音乐的时候看。'}]},
        {'kind': 'preparation', 'title': '正在准备', 'workId': work_ids[0], 'steps': [
            {'label': '找到作品', 'entityId': work_ids[0]}, {'label': '整理好了', 'taskId': job}]},
        {'kind': 'task', 'taskId': job},
    ]}, session='x26-session')
    record('cards running', ui('cards', threadId='x26-thread', turnId='x26-turn'))
    nipa('task.wait', {'jobId': job, 'afterRevision': 0, 'timeoutMs': 15000})
    for _ in range(100):
        cards = ui('cards', threadId='x26-thread', turnId='x26-turn')
        if cards[-1]['task']['state'] == 'finished':
            break
        time.sleep(.2)
    else:
        raise RuntimeError('Hook did not finish.')
    record('cards finished', cards)
    record('home curated', ui('home'))
    record('changes after shelves/cards/task', ui('observations'))
    record('GUI removal', ui('remove', id='tonight', workId=work_ids[1]))
    record('home after removal', ui('home'))
    nipa('activity', {'filter': {'type': {'eq': 'ui.shelf_removed'}}}, query=True)
    nipa('ui.shelves.put', {'placement': 'hero', 'items': []})
    nipa('ui.shelves.put', {'placement': 'shelf', 'id': 'invalid', 'title': '测试',
                          'items': [{'workId': 'missing'}]}, allow_failure=True)
    nipa('ui.present', {'cards': [{'kind': 'task', 'taskId': 'missing'}]},
         session='x26-session', allow_failure=True)
    record('changes after removal', ui('observations'))
finally:
    if vm is not None:
        try:
            vm.chat('close')
        except (RuntimeError, OSError):
            pass
    if app is not None:
        app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait(timeout=10)
    shutil.rmtree(root)
    cleanup = {'pid': app.pid if app else None, 'returncode': app.returncode if app else None,
               'profileRemoved': not root.exists()}
    record('cleanup', cleanup)
