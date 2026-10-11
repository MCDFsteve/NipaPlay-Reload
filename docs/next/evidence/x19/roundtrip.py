"""Isolated X19 experiment. Supplies a licensed Sintel trailer over real BT TCP.

Run after a worktree Debug build:
  python3 docs/next/evidence/x19/roundtrip.py /tmp/nipa-next/x19/Sintel-trailer.mp4
The source is https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4
(Sintel, Blender Foundation, Creative Commons Attribution 3.0).
"""
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import urllib.request

workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).resolve().parent
data = Path(sys.argv[1]).read_bytes()
assert len(data) == 4372373
assert hashlib.sha256(data).hexdigest() == 'b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254'


def bencode(value):
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, bytes):
        return str(len(value)).encode() + b':' + value
    if isinstance(value, list):
        return b'l' + b''.join(map(bencode, value)) + b'e'
    return b'd' + b''.join(bencode(k) + bencode(value[k]) for k in sorted(value)) + b'e'


def bdecode(raw):
    position = 0

    def read():
        nonlocal position
        token = raw[position:position + 1]
        position += 1
        if token == b'i':
            end = raw.index(b'e', position)
            value = int(raw[position:end])
            position = end + 1
            return value
        if token == b'd':
            value = {}
            while raw[position:position + 1] != b'e':
                key = read()
                value[key] = read()
            position += 1
            return value
        position -= 1
        end = raw.index(b':', position)
        size = int(raw[position:end])
        position = end + 1
        value = raw[position:position + size]
        position += size
        return value

    return read()


piece_length = 131072
pieces = [data[i:i + piece_length] for i in range(0, len(data), piece_length)]
info = {b'name': b'Sintel-trailer.mp4', b'length': len(data), b'piece length': piece_length,
        b'pieces': b''.join(hashlib.sha1(p).digest() for p in pieces)}
infohash = hashlib.sha1(bencode(info)).digest()
wire = {'connections': 0, 'requests': 0, 'servedBytes': 0, 'metadataRequests': 0}


def receive(sock, count):
    buf = b''
    while len(buf) < count:
        part = sock.recv(count - len(buf))
        if not part:
            raise EOFError()
        buf += part
    return buf


def send(sock, body):
    sock.sendall(struct.pack('!I', len(body)) + body)


class Peer(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(30)
        try:
            hello = receive(sock, 68)
            assert hello[:20] == b'\x13BitTorrent protocol' and hello[28:48] == infohash
            wire['connections'] += 1
            sock.sendall(hello[:20] + b'\0\0\0\0\0\x10\0\0' + infohash + b'-X1900-'.ljust(20, b'0'))
            send(sock, b'\x14\0' + bencode({b'm': {b'ut_metadata': 1}, b'metadata_size': len(bencode(info))}))
            metadata_id = 1
            bits = bytearray((len(pieces) + 7) // 8)
            for i in range(len(pieces)):
                bits[i // 8] |= 1 << (7 - i % 8)
            send(sock, b'\x05' + bits)
            send(sock, b'\x01')
            while True:
                size = struct.unpack('!I', receive(sock, 4))[0]
                if size == 0:
                    continue
                body = receive(sock, size)
                if body[0] == 20:
                    message = bdecode(body[2:])
                    if body[1] == 0:
                        metadata_id = message[b'm'].get(b'ut_metadata', 1)
                    elif body[1] == 1 and message[b'msg_type'] == 0:
                        assert message[b'piece'] == 0
                        send(sock, bytes([20, metadata_id]) + bencode({b'msg_type': 1, b'piece': 0,
                             b'total_size': len(bencode(info))}) + bencode(info))
                        wire['metadataRequests'] += 1
                if body[0] == 6:
                    index, offset, length = struct.unpack('!III', body[1:])
                    block = pieces[index][offset:offset + length]
                    assert len(block) == length
                    time.sleep(.04)
                    send(sock, b'\x07' + struct.pack('!II', index, offset) + block)
                    wire['requests'] += 1
                    wire['servedBytes'] += len(block)
        except (EOFError, ConnectionError, OSError):
            pass  # Pause/reconnect closes the peer socket.


class Peers(socketserver.ThreadingTCPServer):
    daemon_threads = True


peer_server = Peers(('127.0.0.1', 0), Peer)
peer_port = peer_server.server_address[1]


class Tracker(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.startswith('/announce'):
            body = bencode({b'interval': 1, b'complete': 1, b'incomplete': 0,
                            b'peers': socket.inet_aton('127.0.0.1') + struct.pack('!H', peer_port)})
        elif self.path == '/sintel.torrent':
            body = torrent
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


tracker = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Tracker)
http_port = tracker.server_address[1]
torrent = bencode({b'announce': f'http://127.0.0.1:{http_port}/announce'.encode(),
                   b'comment': b'Sintel trailer, Blender Foundation, CC BY 3.0; X19 local TCP experiment',
                   b'info': info})
for server in (peer_server, tracker):
    threading.Thread(target=server.serve_forever, daemon=True).start()

profile = 'x19-downloads-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
chosen = root / 'data/task-directory'
default = root / 'data/default-directory'
chosen.mkdir(parents=True)
default.mkdir(parents=True)
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True,
    'flutter.downloader_enabled': False,
    'flutter.downloader_auto_scan_completed_tasks': False,
    'flutter.desktop_startup_window_state': 'maximized',
    'flutter.nipaplay_scanned_folders': [str(chosen)],
    'flutter.skip_danmaku_matching': True,
}))
env = {k: v for k, v in os.environ.items() if k.lower() not in ('http_proxy', 'https_proxy', 'all_proxy')}
env.update(NIPAPLAY_PROFILE=profile, NO_PROXY='127.0.0.1,localhost', no_proxy='127.0.0.1,localhost')
log = open('/tmp/nipa-next/x19-app.log', 'w')
app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                       env=env, stdout=log, stderr=subprocess.STDOUT)
records = []
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def record(label, value):
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    records.append({'label': label, 'value': value})
    (evidence / 'roundtrip.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))


def call(action, inputs, expect='completed', timeout=45):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs,
    }).encode(), headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=timeout) as response:
        result = json.load(response)
    record(action, result)
    assert result['status'] == expect, (action, result)
    return result.get('result', result)


def wait_job(job, seconds=90):
    deadline = time.monotonic() + seconds
    while job['state'] not in ('succeeded', 'failed', 'cancelled'):
        assert time.monotonic() < deadline, job
        time.sleep(.5)
        job = call('task.get', {'jobId': job['jobId']})['job']
    assert job['state'] == 'succeeded', job
    return job


try:
    record('start', {'profile': profile, 'pid': app.pid, 'root': str(root),
                     'bytes': len(data), 'infoHash': infohash.hex(), 'transport': 'native BT TCP via local tracker/seed peer'})
    deadline = time.monotonic() + 60
    while not (root / 'endpoint.json').exists():
        assert app.poll() is None, 'app exited during startup'
        assert time.monotonic() < deadline, 'endpoint startup timeout'
        time.sleep(.5)
    endpoint = json.loads((root / 'endpoint.json').read_text())
    source = f'http://127.0.0.1:{http_port}/sintel.torrent'
    call('download.add', {'source': source}, expect='failed')
    call('settings.set', {'changes': [
        {'key': 'download.directory', 'value': str(default)},
        {'key': 'download.createFolderForTask', 'value': True},
        {'key': 'download.enabled', 'value': True},
    ]})
    call('settings.describe', {'domain': 'download'})
    directories = call('download.directories', {})
    assert directories['defaultDirectory'] == str(default)
    removed = call('download.forget_directories', {'directories': [str(default)]})
    assert str(default) not in removed['recentDirectories'] and removed['defaultDirectory'] == str(default)
    preview = call('download.preview', {'source': f'magnet:?xt=urn:btih:{infohash.hex()}&tr=http://127.0.0.1:{http_port}/announce'})
    assert preview['files'] == [{'index': 0, 'path': 'Sintel-trailer.mp4', 'length': len(data)}]
    record('preview-without-task', call('task.list', {'type': 'download'}))
    batch = call('download.add', {'sources': [source, 'magnet:?xt=urn:btih:invalid'],
                                'downloadDirectory': str(chosen), 'createFolderForTask': False})['results']
    assert [r['status'] for r in batch] == ['completed', 'failed']
    job = batch[0]['job']
    job_id = job['jobId']
    deadline = time.monotonic() + 40
    task = None
    while task is None or task['completedBytes'] == 0:
        assert time.monotonic() < deadline, 'no BT pieces received'
        time.sleep(1)
        task = call('download.read', {'jobId': job_id})['task']
    call('download.pause', {'jobId': job_id})
    paused = call('download.read', {'jobId': job_id})['task']
    assert paused['paused']
    call('download.resume', {'jobId': job_id})
    done = wait_job(call('task.get', {'jobId': job_id})['job'])
    receipt_before = done['receipt']
    path = chosen / 'Sintel-trailer.mp4'
    assert path.read_bytes() == data
    assert not list(default.iterdir())
    record('native-transfer', {'wire': wire.copy(), 'actualBytes': path.stat().st_size,
                                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'defaultDirectoryEmpty': True})
    assert done['receipt']['details']['files'][0]['imported'] is False
    before_library = call('state.query', {'view': 'library.files', 'select': ['fileId', 'locator', 'historyStatus']})
    assert before_library['rows'] == []
    # Optional second experiment exercises Classic's fallback-history path.
    if '--preplay' in sys.argv:
        call('download.play', {'jobId': job_id, 'fileIndex': 0})
        time.sleep(2)
        call('playback.state', {})
        call('playback.close', {})
    imported = call('download.import', {'jobId': job_id}, timeout=60)
    record('classic-scan', imported['task']['files'])
    # Existing Next indexing is separate from Classic identification.
    indexed = wait_job(call('media.library.scan', {'root': str(chosen), 'requestId': 'x19-sintel'})['job'])
    identity = call('media.identity.get', {'path': str(path)})['identity']
    assert identity['kind'] == 'file' and identity['locations'][0]['locator'] == str(path)
    record('registered-file', {'fileId': identity['id'], 'locations': identity['locations'],
                                'bindings': identity['bindings'], 'scanReceipt': indexed['receipt']})
    after_library = call('state.query', {'view': 'library.files', 'select': ['fileId', 'locator', 'historyStatus']})
    assert len(after_library['rows']) == 1 and after_library['rows'][0]['fileId'] == identity['id']
    call('download.play', {'jobId': job_id, 'fileIndex': 0})
    time.sleep(2)
    call('playback.seek', {'positionMs': 20000})
    time.sleep(2)
    call('playback.set_paused', {'paused': True})
    state = call('playback.state', {})['state']
    assert state['durationMs'] > 50000 and state['positionMs'] >= 19000, state
    shot = call('playback.capture', {'kind': 'screenshot', 'outputPath': str(root / 'sintel.jpg'),
                                     'includeDanmaku': False})
    shutil.copy2(root / 'sintel.jpg', evidence / 'sintel.jpg')
    call('playback.close', {})
    assert call('task.get', {'jobId': job_id})['job']['receipt'] == receipt_before
    call('download.set_paused', {'jobIds': [job_id], 'paused': True})
    call('settings.set', {'key': 'download.enabled', 'value': False})
    call('download.read', {'jobId': job_id})
    call('settings.get', {'keys': ['download.enabled', 'download.directory']})
    app.terminate()
    app.wait(timeout=10)
    record('restart-stop', {'pid': app.pid, 'processStopped': True})
    old_token = endpoint['token']
    app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                           env=env, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 60
    while True:
        assert app.poll() is None and time.monotonic() < deadline, 'restart timeout'
        if (root / 'endpoint.json').exists():
            fresh = json.loads((root / 'endpoint.json').read_text())
            if fresh['token'] != old_token:
                endpoint = fresh
                break
        time.sleep(.5)
    restored = call('download.read', {'jobId': job_id})
    assert restored['job']['receipt'] == receipt_before
    assert restored['task']['paused'] and restored['task']['outputDirectory'] == str(chosen)
    call('settings.get', {'keys': ['download.enabled', 'download.directory']})
    record('restart', {'pid': app.pid, 'jobId': restored['job']['jobId'],
                        'receiptPreserved': True, 'nativePaused': True, 'outputDirectory': restored['task']['outputDirectory']})
    record('roundtrip', {'complete': True, 'receiptPreserved': True,
                          'classicIdentified': imported['task']['files'][0]['imported'],
                          'registeredFileId': identity['id'], 'playback': state, 'screenshot': shot})
finally:
    app.terminate()
    try:
        app.wait(timeout=10)
    except subprocess.TimeoutExpired:
        app.kill()
        app.wait(timeout=5)
    log.close()
    for server in (tracker, peer_server):
        server.shutdown()
        server.server_close()
    shutil.rmtree(root)
    record('cleanup', {'pid': app.pid, 'processStopped': app.poll() is not None, 'profileDeleted': not root.exists()})
