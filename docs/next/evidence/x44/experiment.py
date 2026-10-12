"""X44: real librqbit, quiet worktree binary, owned disposable profiles only."""
import datetime, gzip, json, os, re, shutil, subprocess, sys, threading, time
from pathlib import Path
from http.server import ThreadingHTTPServer
import urllib.parse, urllib.request

workspace = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(workspace/'scripts/next'))
from x23_vm import LabVM
from x38_protocol import Provider
from local_seed import seed

mode = sys.argv[1]
assert mode in ('body', 'deepseek', 'deepseek-partial', 'deepseek-end-at-submit')
evidence = Path(__file__).parent/mode
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x44-'+mode+'-'+str(os.getpid())
root = Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/profile
assert not root.exists()
root.mkdir(mode=0o700)
data = root/'data'; data.mkdir()
downloads = data/'downloads'; downloads.mkdir()
harness = root/'harness'
shutil.copytree(workspace/'assets/next/harness', harness)
(harness/'nipa').chmod(0o755)
subprocess.run(['git', '-C', str(harness), 'init', '-q', '--template='], check=True)
home = root/'codex-home'; home.mkdir(mode=0o700)
app = vm = provider = None
servers = []; records = []; trace = []; secrets = set()
gates = [threading.Event() for _ in range(3)]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def strings(value):
    if isinstance(value, dict):
        for v in value.values(): yield from strings(v)
    elif isinstance(value, list):
        for v in value: yield from strings(v)
    elif isinstance(value, str): yield value

def sanitize(value):
    if (root/'endpoint.json').exists():
        secrets.add(json.loads((root/'endpoint.json').read_text())['token'])
    for secret in sorted(secrets, key=len, reverse=True): value = value.replace(secret, '[REDACTED]')
    return value

def record(label, value):
    value = json.loads(sanitize(json.dumps(value, ensure_ascii=False)))
    records.append({'at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'label': label, 'value': value})
    (evidence/'timeline.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)

def call(action, inputs, chat=False):
    endpoint = json.loads((root/'endpoint.json').read_text())
    headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer '+endpoint['token']}
    if chat: headers['X-NipaPlay-Chat'] = vm.chat('status')['header']['sessionId']
    request = urllib.request.Request(endpoint['url'], data=json.dumps(
        {'operation': 'call', 'action': action, 'input': inputs}).encode(), headers=headers)
    with opener.open(request, timeout=90) as response: result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']

def until(predicate, seconds=180):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline:
        value = predicate()
        if value: return value
        assert app.poll() is None, 'owned app exited'
        time.sleep(.5)
    raise RuntimeError('observation deadline')

def idle(): return vm.chat('status')['liveness']['status'] not in ('starting', 'inProgress')
def returns(): return call('followup.list', {})['followups']
def auto(): return [r for r in returns() if r.get('automatic') == 'download']
def ready():
    global vm
    if not (root/'endpoint.json').exists(): return False
    try:
        vm = LabVM(root/'app.log')
        header = vm.chat('status')['header']
        return header['threadId'] and header['model']
    except RuntimeError: return False

try:
    if mode == 'body':
        provider = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
        threading.Thread(target=provider.serve_forever, daemon=True).start()
        config = ('model="fixture"\nmodel_provider="fixture"\n[model_providers.fixture]\n'
            'name="fixture"\nwire_api="responses"\nbase_url="http://127.0.0.1:%d/v1"\n' % provider.server_port)
    else:
        config = (Path.home()/'.codex/config.toml').read_text()
        config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
        shutil.copy2(Path.home()/'.codex/auth.json', home/'auth.json')
        secrets.update(v for v in strings(json.loads((home/'auth.json').read_text())) if len(v)>15)
        (home/'skills').symlink_to(Path.home()/'.codex/skills', target_is_directory=True)
    (home/'config.toml').write_text(config); (home/'config.toml').chmod(0o600)
    shutil.copy2('/etc/ssl/cert.pem', root/'system-ca.pem')
    (root/'preferences.json').write_text(json.dumps({
        'flutter.labs_enable_agent_endpoint': True, 'flutter.labs_use_next_interface': True,
        'flutter.next_harness_path': str(harness), 'flutter.downloader_enabled': True,
        'flutter.torrent_download_directory': str(downloads),
        'flutter.downloader_auto_scan_completed_tasks': False, 'flutter.auto_sync_enabled': False}))
    hosts = ['127.0.0.1', 'localhost']+[urllib.parse.urlparse(u).hostname for u in
        re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
    env = dict(os.environ, NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
        CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'), SSL_CERT_FILE=str(root/'system-ca.pem'),
        NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
    env.pop('NIPAPLAY_LAB_QUIET', None)
    secrets.update(v for k,v in env.items() if re.search(r'token|secret|password|api.?key', k, re.I) and len(v)>8)
    videos = []
    for i in range(3):
        video = data/f'source-{i}.mp4'; videos.append(video)
        subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
            f'testsrc2=size=640x360:rate=24:duration={8+i}', '-c:v', 'libx264',
            '-preset', 'fast', '-crf', '24', str(video)], check=True)
    torrent = harness/'collection.torrent'
    servers = list(seed(videos, torrent, 'X44 CC0 三集动画-'+mode, gates, trace,
        initial_partial=mode in ('deepseek-partial', 'deepseek-end-at-submit')))
    (harness/'CONTENT_LICENSE.txt').write_text('All three animated test-pattern videos were created by the experimenter using FFmpeg lavfi, with no third-party assets. Dedicated to the public domain under CC0-1.0. Redistribution explicitly permitted.\n')
    record('legal-content', {'license': 'CC0-1.0', 'sizes': [v.stat().st_size for v in videos]})
    with (root/'app.log').open('w') as output:
        app = subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            cwd=workspace, env=env, stdout=output, stderr=subprocess.STDOUT)
    until(ready, 120)
    assert vm.rpc('getVM')['pid'] == app.pid
    original = vm.chat('status')['header']['threadId']
    record('launch', {'pid': app.pid, 'profile': profile, 'header': vm.chat('status')['header']})
    if mode == 'body':
        record('busy-turn', vm.chat('turn', text='PROBE:busy'))
        jid = call('download.add', {'source': str(torrent), 'downloadDirectory': str(downloads)}, chat=True)['job']['jobId']
        gates[0].set()
        until(lambda: auto())
        record('first-queued-while-busy', {'followups': returns(), 'status': vm.chat('status'), 'download': call('download.read', {'jobId': jid})})
        assert auto()[0]['threadId'] == original and auto()[0]['state'] == 'ready'
        Provider.parent_release.set()
        until(lambda: auto()[0]['state'] == 'completed')
        record('first-delivered', auto())
        gates[1].set()
        until(lambda: len(auto()) == 2)
        record('second-queued-in-window', auto())
        assert auto()[1]['state'] == 'ready'
        until(lambda: auto()[1]['state'] == 'completed', 90)
        record('second-window-delivered', auto())
        first_at = datetime.datetime.fromisoformat(auto()[0]['dispatchedAt'])
        second_at = datetime.datetime.fromisoformat(auto()[1]['dispatchedAt'])
        assert (second_at-first_at).total_seconds() >= 60
        gates[2].set()
        until(lambda: call('task.get', {'jobId': jid})['job']['state'] == 'succeeded')
        until(lambda: any(f['event'] == 'task.terminal' for row in auto()
            for f in row['trigger']['facts']) and all(row['state'] == 'completed' for row in auto()))
        record('terminal-flush', auto())
        facts = [f for row in auto() for f in row['trigger']['facts']]
        assert len([f for f in facts if f['event'] == 'download.file_completed']) == 3
        assert len({f['objectId'] for f in facts}) == 4
        assert len(facts) == 4
        # Same task/hash and all completed files observed again: no extra turn.
        call('download.add', {'source': str(torrent)}, chat=True)
        before = len(auto()); until(idle)
        record('duplicate-add-readback', {'followups': auto(), 'download': call('download.read', {'jobId': jid})})
        assert len(auto()) == before
    else:
        prompt = f'把这套合集下下来，第一集好了就告诉我。种子在 {torrent}，许可证在同目录 CONTENT_LICENSE.txt。\n这是隔离实验，只使用当前 harness 和连接的实例；外部文件只读，不启动或查找其他应用，不访问钥匙串或真实应用数据，不激活窗口、不点击、不重启。'
        record('user-prompt', prompt)
        turn = vm.chat('turn', text=prompt); record('original-turn', turn)
        until(lambda: call('task.list', {'type': 'download'})['jobs'], 240)
        jid = call('task.list', {'type': 'download'})['jobs'][0]['jobId']
        record('download-submitted', call('download.read', {'jobId': jid}))
        if mode in ('deepseek-partial', 'deepseek-end-at-submit'):
            try: until(idle, 0 if mode == 'deepseek-end-at-submit' else 90)
            except RuntimeError:
                record('controlled-original-interrupt', {'status': vm.chat('status'),
                    'interrupt': vm.chat('interrupt')})
                until(idle, 30)
        else: until(idle, 300)
        record('original-turn-ended-before-first', {'status': vm.chat('status'), 'download': call('download.read', {'jobId': jid}), 'followups': returns()})
        gates[0].set(); record('first-seed-released', True)
        until(lambda: auto(), 180)
        record('first-file-followup', {'followups': returns(), 'download': call('download.read', {'jobId': jid})})
        def notified():
            rows = returns()
            for row in rows:
                if row.get('turnId') is None: continue
                thread = vm.chat('read', threadId=original)
                for completed in thread['turns']:
                    if completed['id'] == row['turnId'] and any(i.get('type') == 'agentMessage'
                        and '第一集' in i.get('text', '') for i in completed['items']): return True
            return False
        until(notified, 240)
        record('first-awakened-notification', {'followups': returns(), 'thread': vm.chat('read', threadId=original)})
        gates[1].set(); gates[2].set(); record('remaining-seed-released', True)
        until(lambda: call('task.get', {'jobId': jid})['job']['state'] == 'succeeded', 180)
        until(lambda: all(r['state'] in ('completed', 'cancelled') for r in auto()), 240)
        record('final-thread', vm.chat('read', threadId=original))
        record('final-followups', returns())
    record('library-files', call('state.query', {'view': 'library.files'}))
    record('agent-thread', vm.chat('read', threadId=original))
finally:
    for gate in gates: gate.set()
    Provider.parent_release.set()
    if app is not None and app.poll() is None:
        if vm:
            try: vm.chat('close')
            except (RuntimeError, OSError): pass
        app.terminate()
        try: app.wait(timeout=30)
        except subprocess.TimeoutExpired: app.kill(); app.wait(timeout=10)
    for server in servers+([provider] if provider else []): server.shutdown(); server.server_close()
    for name in ['chat-events.jsonl', 'app.log', 'journal.jsonl']:
        path = root/name
        if path.exists():
            with gzip.open(evidence/(name+'.gz'), 'wt') as output:
                output.write(sanitize(path.read_text(errors='replace')))
    (evidence/'peer-trace.json').write_text(json.dumps(trace))
    scan_text = json.dumps(records)+json.dumps(trace)
    record('secret-check', {'knownValues': len(secrets), 'matches': sum(s in scan_text for s in secrets)})
    shutil.rmtree(root)
    record('cleanup', {'pid': app.pid if app else None, 'exited': app.poll() if app else None, 'profileRemoved': not root.exists()})
