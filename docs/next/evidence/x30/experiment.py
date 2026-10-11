"""Exercise this worktree's executable, APIs and actual dialog handlers in lab profiles."""
import base64
import concurrent.futures
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

workspace = Path(__file__).resolve().parents[4]
sys.dont_write_bytecode = True
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM

evidence = Path(__file__).parent
executable = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
env = os.environ.copy()
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
    env.pop(key, None)
env.update(NO_PROXY='127.0.0.1,localhost,::1', no_proxy='127.0.0.1,localhost,::1')
records, instances, servers, extra_processes, temporary_roots = [], [], [], [], []
pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)


def record(label, value):
    records.append({'label': label, 'value': value})
    (evidence / 'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    return value


def until(callback, seconds=45):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = callback()
        if value:
            return value
        time.sleep(.2)
    raise TimeoutError('Experiment observation deadline exceeded')


class Instance:
    def __init__(self, suffix, preferences=None):
        self.profile = f'x30-{suffix}-{os.getpid()}'
        self.root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / self.profile
        assert not self.root.exists()
        self.media = self.root / 'data/fixture'
        self.media.mkdir(parents=True, mode=0o700)
        self.environment = dict(env, NIPAPLAY_PROFILE=self.profile,
            CODEX_HOME=str(self.root / 'codex-home'), NIPAPLAY_ENDPOINT_FILE=str(self.root / 'endpoint.json'))
        self.preferences = {
            'flutter.labs_enable_agent_endpoint': True,
            'flutter.nipaplay_scanned_folders': [str(self.media)],
            'flutter.skip_danmaku_matching': True,
            'flutter.danmaku_auto_load_strategy': 'disabled',
            'flutter.downloader_enabled': True,
            'flutter.downloader_auto_scan_completed_tasks': False,
            'flutter.web_server_auto_start': False,
            'flutter.remote_control_receiver_enabled': False,
            'flutter.auto_check_update': False,
        }
        self.preferences.update(preferences or {})
        self.app = None
        instances.append(self)

    def start(self):
        (self.root / 'preferences.json').write_text(json.dumps(self.preferences))
        self.log = evidence / f'{self.profile.split("-")[1]}-app.log'
        self.stream = self.log.open('w')
        self.app = subprocess.Popen([str(executable)], env=self.environment,
            cwd=workspace, stdout=self.stream, stderr=subprocess.STDOUT)
        until(lambda: (self.root / 'endpoint.json').exists(), seconds=90)
        self.vm = LabVM(self.log)
        assert self.vm.rpc('getVM')['pid'] == self.app.pid
        self.libraries = self.vm.rpc('getIsolate', isolateId=self.vm.isolate)['libraries']
        record('instance', {'profile': self.profile, 'pid': self.app.pid, 'executable': str(executable)})

    def call(self, action, inputs=None, query=False, describe=False):
        command = [str(self.root / 'harness/nipa'),
            'describe' if describe else 'query' if query else 'call', action]
        if not describe:
            command.append(json.dumps(inputs or {}, ensure_ascii=False))
        result = subprocess.run(command, cwd=self.root / 'harness', env=self.environment,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
        if not result.stdout:
            raise RuntimeError(result.stderr)
        return record(f'{self.profile.split("-")[1]} nipa {command[1]} {action}', json.loads(result.stdout))

    def library(self, suffix):
        return next(item['id'] for item in self.libraries if item['uri'].endswith(suffix))

    def evaluate(self, target, expression):
        result = self.vm.rpc('evaluate', isolateId=self.vm.isolate, targetId=target,
            expression=expression, disableBreakpoints='true')
        if result.get('kind') == 'PlainInstance' and result.get('class', {}).get('name') == 'Error':
            raise RuntimeError(result)
        return result

    def consent_state(self):
        library = self.vm.rpc('getObject', isolateId=self.vm.isolate,
            objectId=self.library('/next/tasks/user_consent.dart'))
        cls = next(c['id'] for c in library['classes'] if c['name'] == '_ConsentDialogState')
        values = self.vm.rpc('getInstances', isolateId=self.vm.isolate, objectId=cls, limit=50)['instances']
        for state in values:
            obj = self.vm.rpc('getObject', isolateId=self.vm.isolate, objectId=state['id'])
            fields = {item['decl']['name']: item['value'] for item in obj.get('fields', [])}
            if fields.get('answered', {}).get('valueAsString') == 'false' and fields.get('_element', {}).get('kind') != 'Null':
                return state['id']
        return None

    def fields(self, object_id):
        obj = self.vm.rpc('getObject', isolateId=self.vm.isolate, objectId=object_id)
        return {item['decl']['name']: item['value'] for item in obj.get('fields', [])}

    def singleton(self, library_suffix, name):
        library = self.vm.rpc('getObject', isolateId=self.vm.isolate,
            objectId=self.library(library_suffix))
        cls = next(c['id'] for c in library['classes'] if c['name'] == name)
        values = self.vm.rpc('getInstances', isolateId=self.vm.isolate, objectId=cls, limit=10)['instances']
        assert len(values) == 1, (name, len(values))
        return values[0]['id']

    def invoke(self, target, selector, arguments=()):
        return self.vm.rpc('invoke', isolateId=self.vm.isolate, targetId=target,
            selector=selector, argumentIds='[' + ','.join(arguments) + ']', disableBreakpoints='true')

    def answer(self, approved):
        state = until(self.consent_state)
        self.vm.rpc('invoke', isolateId=self.vm.isolate, targetId=state,
            selector='answer', argumentIds='[objects/bool-' + str(approved).lower() + ']', disableBreakpoints='true')
        record('simulate UI button handler', {'instance': self.profile, 'approved': approved,
            'method': 'VM invokes mounted dialog answer(), the same callback used by its button; no Agent action'})
        time.sleep(.25)

    def capture(self, label):
        response = self.call('ui.capture')
        target = evidence / f'{label}.png'
        shutil.copyfile(response['result']['path'], target)
        record('capture copied', {'file': target.name})

    def task(self, job_id):
        return self.call('task.get', {'jobId': job_id})['result']['job']

    def wait_state(self, job_id, states):
        def read():
            job = self.task(job_id)
            return job if job['state'] in states else None
        return until(read)

    def prefs(self, keys):
        values = json.loads((self.root / 'preferences.json').read_text())
        return record('Classic disk preferences', {key: values.get('flutter.' + key) for key in keys})

    def mcp(self, action, inputs):
        # Connection credentials are used in memory and never printed.
        connection = json.loads((self.root / 'endpoint.json').read_text())
        url = connection['url'].rsplit('/', 1)[0] + '/mcp'
        request = urllib.request.Request(url, data=json.dumps({'jsonrpc': '2.0', 'id': 30,
            'method': 'tools/call', 'params': {'name': action.replace('.', '_'), 'arguments': inputs}}).encode(),
            headers={'Authorization': 'Bearer ' + connection['token'], 'Content-Type': 'application/json',
                'Accept': 'application/json, text/event-stream'})
        with opener.open(request, timeout=65) as response:
            result = json.load(response)
        return record('MCP ' + action, result)['result']['structuredContent']


def bencode(value):
    if isinstance(value, bytes): return str(len(value)).encode() + b':' + value
    if isinstance(value, int): return b'i' + str(value).encode() + b'e'
    if isinstance(value, dict): return b'd' + b''.join(bencode(k) + bencode(v) for k, v in sorted(value.items())) + b'e'
    raise TypeError(value)


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        accepted = not self.path.startswith('/bad/')
        self.send_response(200 if accepted else 503)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"success":true}')

    def log_message(self, *_):
        pass


def fixture_server():
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FixtureHandler)
    servers.append(server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f'http://127.0.0.1:{server.server_port}'


try:
    main = Instance('main')
    movie = main.media / '删除实验.mp4'
    subprocess.run(['ffmpeg', '-y', '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:r=24:d=30',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(movie)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    plugin = main.media / 'fixture.js'
    plugin.write_text('var pluginManifest=' + json.dumps({'id': 'x30.fixture', 'name': '删除实验插件',
        'version': '1.0.0', 'minHostVersion': '1.0.0', 'permissions': ['danmaku.modify']}, ensure_ascii=False) +
        ';var pluginUIEntries=[{id:"count",title:"查看记录"}];var loadedCount=0;'
        'function pluginOnEvent(event){if(event.name==="danmakuLoaded")loadedCount++;}'
        'function pluginHandleUIAction(id){return {type:"text",title:"弹幕加载记录",content:String(loadedCount)};}')
    backup = main.media / 'forbidden.npb'
    backup.write_text(json.dumps({'version': 2, 'timestamp': '2026-10-12T00:00:00Z',
        'preferences': {'settings': {'labs_enable_agent_endpoint': False,
        'remote_control_receiver_enabled': True, 'web_server_port': 65534, 'show_system_resources': True}}}))
    comments = main.media / 'comments.json'
    comments.write_text(json.dumps({'comments': [{'sourceTimeMs': 1000, 'text': '保留这条弹幕', 'mode': 1, 'colorRgb': 16777215}]}))
    main.start()
    for action in ('download.delete', 'plugins.delete', 'media.sources.remove', 'backup.restore', 'danmaku.import', 'accounts.episodes.update'):
        main.call(action, describe=True)
    main.call('settings.set', {'changes': [{'key': 'danmaku.skipMatching', 'value': True},
        {'key': 'danmaku.autoLoadStrategy', 'value': 'local'}]})
    main.call('plugins.install', {'path': str(plugin)})
    main.call('plugins.set_enabled', {'id': 'x30.fixture', 'enabled': True})
    main.call('playback.open', {'path': str(movie)})
    main.call('playback.set_paused', {'paused': True})
    before_events = int(main.call('plugins.invoke', {'id': 'x30.fixture', 'actionId': 'count'})['result']['result']['content'])
    imported = main.call('danmaku.import', {'filePath': str(comments), 'platform': 'x30',
        'platformVideoId': 'fixture', 'path': str(movie)})['result']
    main.call('danmaku.tracks')
    after_events = int(main.call('plugins.invoke', {'id': 'x30.fixture', 'actionId': 'count'})['result']['result']['content'])
    assert after_events > before_events
    record('plugin danmakuLoaded observations', {'before': before_events, 'after': after_events})
    main.capture('danmaku-pool')
    comments.write_text('[]')
    empty = main.call('danmaku.import', {'filePath': str(comments), 'platform': 'x30',
        'platformVideoId': 'fixture', 'path': str(movie)})
    assert empty['status'] == 'failed'
    main.call('danmaku.tracks')
    main.call('danmaku.update', {'changes': [{'bindingId': imported['bindingId'],
        'expectedRevision': imported['revision'], 'offsetMs': 7200001}]})
    main.call('settings.set', {'key': 'danmaku.manualOffset', 'value': 45})
    for key, value in [('danmaku.fontSize', 100), ('player.minimalProgressBarColor', 1),
        ('appearance.blurPower', 7), ('plugins.githubProxyUrl', 'ftp://invalid/')]:
        assert main.call('settings.set', {'key': key, 'value': value})['status'] == 'failed'
    main.call('settings.set', {'key': 'danmaku.fontSize', 'value': 24})
    comments.write_text(json.dumps({'comments': [{'sourceTimeMs': 1000, 'text': '保留弹弹play轨道', 'mode': 1, 'colorRgb': 16777215}]}))
    protected = main.call('danmaku.import', {'filePath': str(comments), 'platform': 'dandanplay',
        'platformVideoId': '424242', 'path': str(movie)})['result']
    main.call('danmaku.detach', {'bindingId': protected['bindingId'], 'revision': protected['revision']})
    protected_tracks = main.call('danmaku.tracks')['result']['tracks']
    assert any(track['trackId'] == 'dandanplay' and track['count'] == 1 and track['bindingId'] is None for track in protected_tracks)
    record('Classic Dandanplay track after detach', {'preserved': True, 'bindingDetached': True})
    assert main.call('accounts.episodes.update', {'provider': 'bangumi', 'items': [{'episodeId': 1, 'state': 0}]})['status'] == 'failed'
    main.call('playback.close')

    # Performance warning and shortcut conflict are the actual application dialogs.
    main.call('settings.set', {'key': 'player.kernel', 'value': 'mdk'})
    pending = pool.submit(main.call, 'settings.set', {'key': 'player.timelinePreviewEnabled', 'value': True})
    until(main.consent_state)
    main.capture('timeline-warning')
    main.answer(False)
    assert pending.result()['status'] == 'failed'
    main.call('settings.get', {'key': 'player.timelinePreviewEnabled'})
    pending = pool.submit(main.call, 'settings.set', {'key': 'player.timelinePreviewEnabled', 'value': True})
    main.answer(True)
    assert pending.result()['status'] == 'completed'
    main.call('settings.set', {'key': 'player.timelinePreviewEnabled', 'value': False})
    shortcut = main.call('settings.describe', {'domain': 'shortcuts'})['result']['settings']
    first, second = shortcut[:2]
    pending = pool.submit(main.call, 'settings.set', {'key': first['key'], 'value': second['value']})
    until(main.consent_state)
    main.capture('shortcut-conflict')
    main.answer(False)
    assert pending.result()['status'] == 'failed'
    main.call('settings.get', {'key': first['key']})

    fixture_url = fixture_server()
    main.call('settings.set', {'key': 'plugins.githubProxyUrl', 'value': fixture_url + '/good/'})
    assert main.call('settings.set', {'key': 'plugins.githubProxyUrl', 'value': fixture_url + '/bad/'})['status'] == 'failed'
    main.call('settings.get', {'key': 'plugins.githubProxyUrl'})
    assert main.prefs(['github_proxy_url'])['github_proxy_url'] == fixture_url + '/good/'
    main.call('settings.set', {'key': 'plugins.githubProxyUrl', 'value': ''})
    source = main.call('media.sources.add', {'type': 'webdav', 'name': '移除实验来源', 'url': fixture_url, 'username': 'fixture'})['result']['source']
    assert main.call('media.sources.remove', {'sourceId': source['sourceId']})['result']['removed'] is True
    main.call('media.sources.list')
    # Native picker cancellation is posted only to this experiment's exact PID.
    pending = pool.submit(main.call, 'settings.set', {'key': 'player.externalEnabled', 'value': True})
    time.sleep(2)
    if not pending.done():
        subprocess.run(['swift', '-e', 'import CoreGraphics; let pid: pid_t = ' + str(main.app.pid) +
            '; CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true)?.postToPid(pid);'
            ' CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:false)?.postToPid(pid)'],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    external = pending.result(timeout=45)
    external_state = main.call('settings.get', {'keys': ['player.externalEnabled', 'player.externalPath']})
    record('external player initialization', {'outcome': external['status'], 'state': external_state['result']})
    main.call('settings.set', {'key': 'player.externalEnabled', 'value': False})

    main.call('backup.restore', {'path': str(backup), 'categories': ['preferences'], 'reason': 'X30 forbidden-key experiment'})
    prefs = main.prefs(['labs_enable_agent_endpoint', 'remote_control_receiver_enabled', 'web_server_port', 'show_system_resources'])
    assert prefs['labs_enable_agent_endpoint'] is True and prefs['remote_control_receiver_enabled'] is False
    assert prefs['web_server_port'] != 65534 and prefs['show_system_resources'] is True
    # Valid Classic binary history record with an extra preferences object.
    history_backup = main.media / 'injected-history.nph'
    exported_history = main.call('backup.history_export', {'path': str(history_backup)})
    assert exported_history['status'] == 'completed'
    blob = history_backup.read_bytes()
    version, count = struct.unpack_from('<ii', blob)
    records_blob, offset = [], 8
    for index in range(count):
        length, = struct.unpack_from('<i', blob, offset)
        offset += 4
        history_record = json.loads(blob[offset:offset + length])
        offset += length
        history_record['preferences'] = {'labs_enable_agent_endpoint': False, 'remote_control_receiver_enabled': True}
        encoded = json.dumps(history_record, ensure_ascii=False).encode()
        records_blob.append(struct.pack('<i', len(encoded)) + encoded)
    history_backup.write_bytes(struct.pack('<ii', version, count) + b''.join(records_blob))
    main.call('backup.history_restore', {'path': str(history_backup)})
    main.prefs(['labs_enable_agent_endpoint', 'remote_control_receiver_enabled', 'web_server_port'])
    invalid_backup = main.media / 'invalid-values.npb'
    invalid_backup.write_text(json.dumps({'version': 2, 'preferences': {'settings': {'danmaku_font_size': 100}}}))
    main.call('backup.restore', {'path': str(invalid_backup), 'categories': ['preferences']})
    main.call('settings.get', {'key': 'danmaku.fontSize'})
    gate_backup = main.media / 'performance-warning.npb'
    timeline_setting = main.call('settings.describe', {'keys': ['player.timelinePreviewEnabled']})['result']['settings'][0]
    gate_backup.write_text(json.dumps({'version': 2, 'preferences': {'settings': {timeline_setting['storage']['key']: True}}}))
    pending = pool.submit(main.call, 'backup.restore', {'path': str(gate_backup), 'categories': ['preferences']})
    main.answer(False)
    main.capture('backup-warning-refused')
    pending.result()
    main.call('settings.get', {'key': 'player.timelinePreviewEnabled'})
    credential_backup = main.media / 'inline-credentials.npb'
    credential_backup.write_text(json.dumps({'version': 2, 'accounts': {'dandanplay': {'isLoggedIn': True, 'token': 'x30-fixture-token'}}}))
    main.call('backup.restore', {'path': str(credential_backup), 'categories': ['accounts']})
    main.call('accounts.status')

    installed = next(path for path in (main.root / 'data').rglob('x30.fixture.js'))
    changed_plugin = main.media / 'replacement.js'
    changed_plugin.write_text(plugin.read_text().replace('x30.fixture', 'x30.replacement').replace('1.0.0', '2.0.0'))
    assert main.call('plugins.install', {'path': str(changed_plugin), 'updateForId': 'x30.fixture'})['status'] == 'failed'
    assert installed.exists()
    deleted = main.call('plugins.delete', {'id': 'x30.fixture'})['result']['job']['jobId']
    main.wait_state(deleted, {'waiting_user'})
    main.call('task.wait', {'jobId': deleted, 'timeoutMs': 0})
    main.call('followup.register', {'when': {'jobId': deleted}, 'instruction': '读取删除回执', 'title': '等你决定'})
    main.capture('delete-plugin-waiting')
    assert installed.exists()
    main.answer(False)
    refused = main.wait_state(deleted, {'failed'})
    assert refused['error']['message'] == '用户没有同意删除' and installed.exists()
    record('plugin file after refusal', {'exists': installed.exists()})
    mcp_job = main.mcp('plugins.delete', {'id': 'x30.fixture'})['result']['job']['jobId']
    main.wait_state(mcp_job, {'waiting_user'})
    assert installed.exists()
    main.answer(True)
    main.wait_state(mcp_job, {'succeeded', 'failed'})
    record('plugin file after UI Delete', {'exists': installed.exists()})
    assert not installed.exists()

    data = movie.read_bytes()
    torrent = main.media / 'fixture.torrent'
    torrent.write_bytes(bencode({b'info': {b'name': movie.name.encode(), b'length': len(data),
        b'piece length': 16384, b'pieces': b''.join(hashlib.sha1(data[i:i+16384]).digest() for i in range(0, len(data), 16384))}}))
    download = main.call('download.add', {'source': str(torrent), 'downloadDirectory': str(main.media),
        'createFolderForTask': False})['result']['job']['jobId']
    until(lambda: main.call('download.read', {'jobId': download})['result']['task'])
    deletion = main.call('download.delete', {'jobId': download})['result']['job']['jobId']
    main.wait_state(deletion, {'waiting_user'})
    main.capture('delete-download-waiting')
    main.answer(False)
    main.wait_state(deletion, {'failed'})
    assert movie.exists()
    main.call('download.read', {'jobId': download})
    deletion = main.call('download.delete', {'jobId': download})['result']['job']['jobId']
    main.wait_state(deletion, {'waiting_user'})
    main.answer(True)
    main.wait_state(deletion, {'succeeded', 'failed'})
    assert not movie.exists()
    record('download file after UI Delete', {'exists': movie.exists()})
    main.call('download.read', {'jobId': download})
    main.call('state.query', {'view': 'activity', 'limit': 100})
    main.call('state.query', {'view': 'followups', 'limit': 10})

    # A local coordinator, a synthetic account and two isolated real instances.
    mesh_root = Path(tempfile.mkdtemp(prefix='x30-mesh-', dir='/tmp/nipa-next'))
    temporary_roots.append(mesh_root)
    coordinator_binary = workspace / 'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator'
    subprocess.run([str(coordinator_binary), '--generate-dev-ca', str(mesh_root / 'ca.pem'), str(mesh_root / 'ca.key')],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    upstream = fixture_server()
    with socket.socket() as reserved:
        reserved.bind(('127.0.0.1', 0))
        port = reserved.getsockname()[1]
    mesh_url = f'http://127.0.0.1:{port}'
    coord_environment = dict(env, MESH_LISTEN_ADDR=f'127.0.0.1:{port}',
        MESH_DATABASE_PATH=str(mesh_root / 'coordinator.db'), MESH_CA_CERT_FILE=str(mesh_root / 'ca.pem'),
        MESH_CA_KEY_FILE=str(mesh_root / 'ca.key'), DANDANPLAY_GATEWAY_BASE=upstream + '/dandanplay/',
        MESH_ACCOUNT_CLAIM_POINTER='/userId')
    coordinator_log = (evidence / 'mesh-coordinator.log').open('w')
    coordinator = subprocess.Popen([str(coordinator_binary)], env=coord_environment,
        stdout=coordinator_log, stderr=subprocess.STDOUT)
    extra_processes.append(coordinator)
    def healthy():
        try:
            with opener.open(mesh_url + '/healthz', timeout=2) as response:
                return response.status == 200
        except OSError: return False
    until(healthy)
    synthetic_token = '.'.join(base64.urlsafe_b64encode(s.encode()).decode().rstrip('=')
        for s in ('{"alg":"EdDSA"}', '{"userId":424242,"testOnly":true}')) + '.synthetic-test-signature'
    def configure_mesh(instance):
        instance.preferences['flutter.dandanplay_token'] = synthetic_token
        instance.preferences['flutter.last_token_renew_time'] = int(time.time() * 1000)
        instance.environment['NIPAPLAY_MESH_DEV_CA'] = str(mesh_root / 'ca.pem')
        directory = instance.root / 'data/next'
        directory.mkdir(parents=True)
        (directory / 'mesh.json').write_text(json.dumps({'coordinator': mesh_url, 'name':
            '实验发送端' if instance.profile.split('-')[1] == 'sender' else '实验接收端'}))
    sender = Instance('sender')
    configure_mesh(sender)
    sender.start()
    until(lambda: (sender.root / 'data/next/mesh-identity.json').exists())
    sender_id = json.loads((sender.root / 'data/next/mesh-identity.json').read_text())['deviceId']
    receiver = Instance('receiver', {'flutter.remote_control_trusted_devices': json.dumps([
        {'clientKey': 'id:' + sender_id, 'clientId': sender_id, 'clientName': '实验发送端'}])})
    configure_mesh(receiver)
    receiver.start()
    until(lambda: (receiver.root / 'data/next/mesh-identity.json').exists())
    receiver_id = json.loads((receiver.root / 'data/next/mesh-identity.json').read_text())['deviceId']
    for node in (sender, receiver):
        runtime = node.singleton('/next/mesh/runtime.dart', 'MeshRuntime')
        discovery = until(lambda: node.fields(runtime).get('_discovery') if
            node.fields(runtime).get('_discovery', {}).get('kind') != 'Null' else None)
        listen_port = int(node.fields(discovery['id'])['port']['valueAsString'])
        node.call('settings.set', {'key': 'mesh.addressCandidates', 'value': [
            {'kind': 'manual', 'host': '127.0.0.1', 'port': listen_port}]})
        node.invoke(runtime, 'heartbeat')
        time.sleep(1)
    sender.call('mesh.devices')
    request = {'deviceId': receiver_id, 'action': 'playback.state', 'input': {}}
    off = sender.call('mesh.invoke', request)
    assert off['status'] == 'failed' and 'receiver is disabled' in off['error']['message']
    library = receiver.vm.rpc('getObject', isolateId=receiver.vm.isolate,
        objectId=receiver.library('/services/remote_control_settings.dart'))
    settings_class = next(c['id'] for c in library['classes'] if c['name'] == 'RemoteControlSettings')
    receiver.invoke(settings_class, 'setReceiverEnabled', ['objects/bool-true'])
    until(lambda: receiver.prefs(['remote_control_receiver_enabled'])['remote_control_receiver_enabled'])
    trusted = sender.call('mesh.invoke', request)
    assert trusted['status'] == 'completed'
    guard = receiver.singleton('/services/remote_control_access_guard_service.dart', 'RemoteControlAccessGuardService')
    trusted_map = receiver.vm.rpc('getObject', isolateId=receiver.vm.isolate,
        objectId=receiver.fields(guard)['_trustedDevices']['id'])
    client_key = next(a['key']['id'] for a in trusted_map['associations']
        if a['key'].get('valueAsString') == 'id:' + sender_id)
    receiver.invoke(guard, 'removeTrustedDevice', [client_key])
    time.sleep(.5)
    revoked = sender.call('mesh.invoke', request)
    assert revoked['status'] == 'failed'
    receiver.prefs(['remote_control_receiver_enabled', 'remote_control_trusted_devices'])
    receiver.call('state.query', {'view': 'activity', 'limit': 10})
    record('Mesh authorization observations', {'receiverOff': off, 'trusted': trusted, 'revoked': revoked})

finally:
    pool.shutdown(wait=False, cancel_futures=True)
    for instance in reversed(instances):
        if instance.app is not None and instance.app.poll() is None:
            instance.app.terminate()
            try: instance.app.wait(timeout=10)
            except subprocess.TimeoutExpired:
                instance.app.kill(); instance.app.wait(timeout=10)
        if hasattr(instance, 'stream'): instance.stream.close()
        if instance.root.exists(): shutil.rmtree(instance.root)
        record('cleanup', {'profile': instance.profile, 'rootAbsent': not instance.root.exists(),
            'processExited': instance.app is None or instance.app.poll() is not None})
    for process in extra_processes:
        process.terminate(); process.wait(timeout=10)
    for server in servers:
        server.shutdown(); server.server_close()
    for root in temporary_roots:
        shutil.rmtree(root)
        record('coordinator cleanup', {'rootAbsent': not root.exists()})
