"""X28 real worktree instances and loopback test servers. Secrets stay in this script."""
import hashlib, http.server, json, os, re, shutil, socket, socketserver, sqlite3
import struct, subprocess, sys, threading, time, urllib.parse, urllib.request
import tempfile
from pathlib import Path
workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).parent
sys.path.insert(0, str(workspace / 'scripts/next'))
from x23_vm import LabVM
configs = json.loads(Path('/tmp/nipa-next/testservers.json').read_text())
secrets = [str(v) for c in configs.values() if isinstance(c,dict) for k,v in c.items()
           if any(s in k.lower() for s in ('password','token','auth')) and isinstance(v,str) and v]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
run_id = str(os.getpid())
profiles = {}
processes = []
servers = []
records = []
remote_path = '/NipaPlay/x28-' + run_id
sync_url = None
dav_container = None
dav_root = None
exe = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
def scrub(value):
    if isinstance(value,str):
        for secret in secrets: value = value.replace(secret, '<redacted>')
        return value
    if isinstance(value,list): return [scrub(v) for v in value]
    if isinstance(value,dict): return {k:scrub(v) for k,v in value.items()}
    return value
def record(label,value):
    value = scrub(value)
    records.append({'label':label,'value':value})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label, json.dumps(value,ensure_ascii=False),flush=True)
def make_profile(label):
    name = 'x28-' + label + '-' + run_id
    root = Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/name
    assert not root.exists()
    root.mkdir(mode=0o700)
    media=root/'data/fixture'; media.mkdir(parents=True)
    subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-f','lavfi','-i','color=c=blue:s=320x180:d=8',
                    '-c:v','libx264','-pix_fmt','yuv420p',str(media/'X28.mp4')],check=True)
    schema=(workspace/'lib/models/watch_history_database.dart').read_text().split('CREATE TABLE watch_history(',1)[1].split("''');",1)[0]
    db=sqlite3.connect(root/'data/watch_history.db')
    db.execute('CREATE TABLE watch_history('+schema)
    db.execute('PRAGMA user_version=2')
    db.execute('INSERT INTO watch_history(file_path,anime_name,episode_title,anime_id,episode_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,?,?,?,?,?)',
               (str(media/'X28.mp4'),'测试影片','蓝色画面',28,2801,0.25,2000,8000,'2026-10-12T00:00:00.000Z',0))
    if label=='main':
        shutil.copy2(media/'X28.mp4',media/'X28-sync.mp4')
        db.execute('INSERT INTO watch_history(file_path,anime_name,episode_title,anime_id,episode_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (str(media/'X28-sync.mp4'),'同步测试','同步进度',280,2802,0.5,4000,8000,'2026-10-12T00:00:00.000Z',0))
    db.commit(); db.close()
    prefs={'flutter.labs_enable_agent_endpoint':True,'flutter.downloader_enabled':label=='main',
           'flutter.downloader_auto_scan_completed':False,'flutter.skip_danmaku_matching':True,
           'flutter.nipaplay_scanned_folders':[str(media)],'flutter.auto_sync_enabled':False}
    if label=='peer': prefs['flutter.web_server_auto_start']=True
    else:
        ps=[]
        for kind in ('jellyfin','emby'):
            c=configs[kind]
            ps.append({'id':'x28-'+kind,'serverName':kind.title(),'serverType':kind,'username':c['user_name'],
                'serverId':c['server_id'],'userId':c['user_id'],'accessToken':c['access_token'],
                'lastSuccessfulAddressId':'x28-'+kind+'-a',
                'addresses':[{'id':'x28-'+kind+'-a','url':c['base_url'],'name':'本机','priority':0,'isEnabled':True}]})
        prefs.update({'flutter.server_profiles':json.dumps(ps),
            'flutter.webdav_connections':json.dumps([{'id':'x28-dav','name':'测试 WebDAV','url':configs['webdav']['url'],
                'username':configs['webdav']['user_name'],'password':configs['webdav']['password'],'isConnected':True}]),
            'flutter.smb_connections':json.dumps([{'id':'x28-smb','name':'测试 SMB','host':configs['smb']['host'],
                'port':configs['smb']['port'],'username':configs['smb']['user_name'],'password':configs['smb']['password'],'domain':'','isConnected':True}]),
            'flutter.incremental_sync_webdav_url':sync_url,
            'flutter.incremental_sync_webdav_username':configs['webdav']['user_name'],
            'flutter.incremental_sync_webdav_password':configs['webdav']['password'],
            'flutter.incremental_sync_remote_path':remote_path,
            'flutter.incremental_sync_categories':json.dumps(['watchHistory','episodeMatches']),
            'flutter.incremental_sync_interval_minutes':30})
    prefs.update({
        'flutter.incremental_sync_webdav_url':sync_url,
        'flutter.incremental_sync_webdav_username':configs['webdav']['user_name'],
        'flutter.incremental_sync_webdav_password':configs['webdav']['password'],
        'flutter.incremental_sync_remote_path':remote_path,
        'flutter.incremental_sync_categories':json.dumps(['watchHistory','episodeMatches'])})
    if label=='peer':
        prefs['flutter.smb_connections']=json.dumps([{'id':'x28-peer-smb','name':'共享端测试 SMB',
            'host':configs['smb']['host'],'port':configs['smb']['port'],
            'username':configs['smb']['user_name'],'password':configs['smb']['password'],
            'domain':'','isConnected':True}])
    (root/'preferences.json').write_text(json.dumps(prefs)); (root/'preferences.json').chmod(0o600)
    env=os.environ.copy()
    for n in ('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'): env.pop(n,None)
    env.update(NIPAPLAY_PROFILE=name,NO_PROXY='127.0.0.1,localhost',no_proxy='127.0.0.1,localhost',CODEX_HOME=str(root/'codex-home'))
    log_path=Path('/tmp/nipa-next')/('x28-'+label+'-'+run_id+'.log')
    log=log_path.open('w')
    proc=subprocess.Popen([str(exe)],cwd=workspace,env=env,stdout=log,stderr=subprocess.STDOUT)
    processes.append((proc,log))
    profiles[label]={'name':name,'root':root,'env':env,'log':log_path,'process':proc}
    for _ in range(360):
        if proc.poll() is not None: raise RuntimeError('Worktree '+label+' process exited.')
        if (root/'endpoint.json').exists() and (root/'harness/nipa').exists():
            try:
                vm=LabVM(log_path)
                profiles[label]['vm']=vm
                assert vm.rpc('getVM')['pid']==proc.pid
                break
            except (RuntimeError,OSError,KeyError): pass
        time.sleep(.25)
    else: raise RuntimeError('Worktree endpoint did not start.')
    record('instance '+label,{'profile':name,'pid':proc.pid})
    return profiles[label]
def cli(label,operation,action=None,inputs=None,allow_failure=False):
    p=profiles[label]; env=p['env'].copy()
    env['NIPAPLAY_ENDPOINT_FILE']=str(p['root']/'endpoint.json')
    cmd=['./nipa',operation]
    if action is not None: cmd.append(action)
    if inputs is not None: cmd.append(json.dumps(inputs,ensure_ascii=False))
    r=subprocess.run(cmd,cwd=p['root']/'harness',env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=180)
    try: value=json.loads(r.stdout)
    except ValueError: raise RuntimeError(scrub(r.stderr))
    record(label+' '+operation+' '+(action or ''),value)
    if not allow_failure and r.returncode: raise RuntimeError('nipa failed: '+str(action))
    return value.get('result',value)
def call(action,inputs={},allow_failure=False): return cli('main','call',action,inputs,allow_failure)
def wait(job,label='main',terminal=True):
    for _ in range(160):
        value=cli(label,'call','task.get',{'jobId':job})
        state=value['job']['state']
        if state in ('succeeded','failed','cancelled'): return value['job']
        time.sleep(.2)
    raise RuntimeError('Task did not finish.')
def capture(name,label='main'):
    result=cli(label,'call','ui.capture',{})
    shutil.copy2(result['path'],evidence/(name+'.png'))
def prefs_public(label,keys):
    saved=json.loads((profiles[label]['root']/'preferences.json').read_text())
    return {k:saved.get('flutter.'+k) for k in keys}
try:
    # The shared :8098 fixture is read-only. Use an isolated real WebDAV server
    # from the already installed test image; never modify another test server.
    dav_root=Path(tempfile.mkdtemp(prefix='x28-dav-',dir='/tmp/nipa-next'))
    (dav_root/'data').mkdir(mode=0o777)
    (dav_root/'data').chmod(0o777)
    configuration={'address':'0.0.0.0','port':6065,'auth':True,'tls':False,
        'directory':'/data','users':[{'username':configs['webdav']['user_name'],
        'password':configs['webdav']['password'],'permissions':'CRUD'}]}
    config_file=dav_root/'config.json'
    config_file.write_text(json.dumps(configuration)); config_file.chmod(0o600)
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); dav_port=s.getsockname()[1]
    started=subprocess.run(['docker','--context','colima-nipa-test','create','--pull=never',
        '--name','x28-dav-'+run_id,'-p',f'127.0.0.1:{dav_port}:6065',
        'hacdias/webdav:latest','--config','/config.json'],capture_output=True,text=True,check=True)
    dav_container=started.stdout.strip()
    for local,target in [(config_file,'/config.json'),(dav_root/'data','/data')]:
        subprocess.run(['docker','--context','colima-nipa-test','cp',str(local),dav_container+':'+target],capture_output=True,check=True)
    subprocess.run(['docker','--context','colima-nipa-test','start',dav_container],capture_output=True,check=True)
    sync_url='http://127.0.0.1:'+str(dav_port)
    for _ in range(60):
        try:
            with socket.create_connection(('127.0.0.1',dav_port),timeout=1): break
        except OSError: time.sleep(.2)
    record('isolated writable WebDAV',{'url':sync_url,'image':'hacdias/webdav:latest'})
    main=make_profile('main')
    data=(main['root']/'data/fixture/X28.mp4').read_bytes()
    
    
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
    info = {b'name': b'X28.mp4', b'length': len(data), b'piece length': piece_length,
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
                sock.sendall(hello[:20] + b'\0\0\0\0\0\x10\0\0' + infohash + b'-X2800-'.ljust(20, b'0'))
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
                       b'comment': b'X28 generated blue video, local TCP experiment',
                       b'info': info})
    for server in (peer_server, tracker):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    
    servers.extend([peer_server,tracker])
    hash_text=hashlib.md5(data).hexdigest()
    class Remote(http.server.BaseHTTPRequestHandler):
        def log_message(self,*_): pass
        def do_GET(self):
            path=urllib.parse.urlparse(self.path).path
            if path=='/api/v1/welcome': body=json.dumps({'version':'X28-fixture','tokenRequired':False}).encode(); mime='application/json'
            elif path=='/api/v1/library':
                body=json.dumps([{'Id':'x28-entry','Hash':hash_text,'Name':'X28.mp4','AnimeTitle':'测试影片','EpisodeTitle':'蓝色画面','Path':'/X28.mp4','Size':len(data),'Duration':8000}]).encode(); mime='application/json'
            elif '/api/v1/stream/' in path or path.endswith('X28.mp4'):
                start,end=0,len(data)-1
                if self.headers.get('Range'):
                    m=re.match(r'bytes=(\d+)-(\d*)',self.headers['Range'])
                    if m: start=int(m[1]); end=int(m[2]) if m[2] else end
                end=min(end,len(data)-1); body=data[start:end+1]; mime='video/mp4'
                self.send_response(206 if self.headers.get('Range') else 200)
                self.send_header('Content-Type',mime); self.send_header('Accept-Ranges','bytes')
                self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
            else: self.send_error(404); return
            self.send_response(200); self.send_header('Content-Type',mime); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        def do_PROPFIND(self):
            directory=self.path.split('?')[0].rstrip('/')+'/'
            if '/offline/' in directory:
                self.send_error(503); return
            href=directory
            resources=[(href,True)]
            if 'empty' not in directory: resources.append((directory+'X28.mp4',False))
            parts=[]
            for href,folder in resources:
                parts.append(f'<d:response><d:href>{href}</d:href><d:propstat><d:prop><d:displayname>{"影片" if not folder else "文件夹"}</d:displayname><d:resourcetype>{"<d:collection/>" if folder else ""}</d:resourcetype><d:getcontentlength>{0 if folder else len(data)}</d:getcontentlength><d:getlastmodified>Mon, 12 Oct 2026 00:00:00 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>')
            body=('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'+''.join(parts)+'</d:multistatus>').encode()
            self.send_response(207); self.send_header('Content-Type','application/xml'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        def do_OPTIONS(self):
            self.send_response(200); self.send_header('DAV','1,2'); self.send_header('Allow','GET,HEAD,OPTIONS,PROPFIND'); self.end_headers()
        def do_HEAD(self):
            self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers()
    remote=http.server.ThreadingHTTPServer(('127.0.0.1',0),Remote)
    servers.append(remote); threading.Thread(target=remote.serve_forever,daemon=True).start()
    remote_url='http://127.0.0.1:'+str(remote.server_address[1])
    peer=make_profile('peer')
    peer_text=peer['log'].read_text(errors='replace')
    port=int(re.search(r'Remote access server started on port (\d+)',peer_text)[1])
    peer_url='http://127.0.0.1:'+str(port)
    for action in ['sync.configure','sync.enable','sync.login','media.sources.addresses','media.sources.remote_admin.folders','media.sources.remote_admin.connections','media.sources.play','media.sources.scrape']:
        cli('main','describe',action)
    # Real WebDAV sync, with a previously saved Classic session fixture.
    call('sync.status')
    call('sync.configure',{'intervalMinutes':5,'syncOnRecordChange':True,'categories':['watchHistory','episodeMatches']})
    saved=json.loads((main['root']/'preferences.json').read_text())
    raw=saved.get('flutter.incremental_sync_webdav_password','')
    if isinstance(raw,str) and raw.startswith('{'):
        ref=json.loads(raw)['credentialRef']
        vault=json.loads((main['root']/'credential-vault.json').read_text())
        actual=vault.get(str(len(ref['namespace'].encode()))+':'+ref['namespace']+ref['key'])
    else: actual=raw
    record('sync fixture credential check',{'present':bool(actual),'matchesFixture':actual==configs['webdav']['password']})
    call('sync.test')
    login=call('sync.login')
    time.sleep(.4); capture('sync-login'); call('task.cancel',{'jobId':login['jobId']}); wait(login['jobId'])
    enabled=call('sync.enable',{'enabled':True}); assert wait(enabled['jobId'])['state']=='succeeded'
    run=call('sync.run'); assert wait(run['jobId'])['state']=='succeeded'
    call('sync.status')
    peer_enable=cli('peer','call','sync.enable',{'enabled':True})
    assert wait(peer_enable['jobId'],'peer')['state']=='succeeded'
    peer_run=cli('peer','call','sync.run',{})
    assert wait(peer_run['jobId'],'peer')['state']=='succeeded'
    with sqlite3.connect(peer['root']/'data/watch_history.db') as db:
        rows=db.execute('SELECT anime_name,last_position,duration FROM watch_history WHERE anime_id=280').fetchall()
    assert rows and rows[0][1]==4000
    record('Classic peer restored history',{'rows':rows})
    peer_disable=cli('peer','call','sync.enable',{'enabled':False})
    assert wait(peer_disable['jobId'],'peer')['state']=='succeeded'
    disabled=call('sync.enable',{'enabled':False}); assert wait(disabled['jobId'])['state']=='succeeded'
    record('Classic sync preferences',prefs_public('main',['auto_sync_enabled','incremental_sync_interval_minutes','incremental_sync_categories','incremental_sync_last_sync_at','incremental_sync_last_error']))
    call('settings.history',{'keys':['sync.configuration','sync.enabled']})
    call('state.query',{'view':'activity','limit':100,'select':['type','title','actor','origin','subjectId','jobId','facts']})
    # Both real local Jellyfin and Emby servers, with pre-existing test sessions.
    for kind in ('jellyfin','emby'):
        source=kind+':x28-'+kind
        call('media.sources.check',{'type':kind,'url':configs[kind]['base_url']})
        call('media.sources.check',{'sourceId':source})
        libraries=call('media.sources.libraries',{'sourceId':source})['libraries']
        library=libraries[0]['id']
        entries=call('media.sources.browse',{'sourceId':source,'parentId':library,'recursive':True,'sortBy':'DateCreated,SortName','sortOrder':'Descending'})['entries']
        if entries:
            call('media.sources.query',{'sourceId':source,'itemIds':[e['id'] for e in entries[:2]]})
            call('media.sources.browse',{'sourceId':source,'searchTerm':entries[0]['name'],'recursive':True})
        call('media.sources.sort',{'sourceId':source,'sorts':[{'libraryId':library,'sortBy':'SortName','sortOrder':'Ascending'}]})
        alternate=configs[kind]['base_url'].replace('127.0.0.1','localhost')
        result=call('media.sources.addresses',{'sourceId':source,'operations':[{'operation':'add','url':alternate,'name':'备用连接'}]})
        addresses=result['source']['addresses']; extra=next(a['id'] for a in addresses if a['name']=='备用连接')
        call('media.sources.addresses',{'sourceId':source,'operations':[{'operation':'priority','addressId':extra,'priority':1},{'operation':'check','addressId':extra},{'operation':'switch','addressId':extra}]})
        call('media.sources.addresses',{'sourceId':source,'operations':[{'operation':'switch','addressId':'x28-'+kind+'-a'},{'operation':'remove','addressId':extra}]})
        call('media.sources.addresses',{'sourceId':source,'operations':[{'operation':'remove','addressId':'x28-'+kind+'-a'}]},True)
    record('Classic library sorting',prefs_public('main',['jellyfin_library_sort_settings','emby_library_sort_settings']))
    call('state.query',{'view':'activity','limit':100,'select':['type','title','actor','origin','subjectId','jobId','facts']})
    # Dandanplay remote protocol fixture: no login secrets.
    source=call('media.sources.add',{'type':'dandanplay_remote','name':'弹弹play','url':remote_url})['source']['sourceId']
    login=call('media.sources.login',{'sourceId':source,'method':'window'})
    time.sleep(.4); capture('dandan-login'); call('task.cancel',{'jobId':login['jobId']}); wait(login['jobId'])
    call('media.sources.check',{'type':'dandanplay_remote','url':remote_url})
    call('media.sources.check',{'sourceId':source})
    call('media.sources.libraries',{'sourceId':source})
    call('media.sources.browse',{'sourceId':source})
    call('media.sources.browse',{'sourceId':source,'parentId':'unmatched','searchTerm':'蓝色'})
    call('media.sources.query',{'sourceId':source,'itemIds':['x28-entry','missing']})
    call('media.sources.play',{'sourceId':source,'itemId':'x28-entry'})
    time.sleep(1.5); call('playback.state'); capture('dandan-playing'); call('playback.close')
    # Upload the newly created remote playback history as an actual diff,
    # then verify that the other instance restored it into Classic SQLite.
    for label in ('main','peer'):
        job=cli(label,'call','sync.enable',{'enabled':True})
        assert wait(job['jobId'],label)['state']=='succeeded'
    with sqlite3.connect(peer['root']/'data/watch_history.db') as db:
        remote_rows=db.execute("SELECT anime_name,last_position,duration FROM watch_history WHERE file_path LIKE '%/api/v1/stream/%'").fetchall()
    assert remote_rows
    import base64
    auth=base64.b64encode((configs['webdav']['user_name']+':'+configs['webdav']['password']).encode()).decode()
    req=urllib.request.Request(sync_url+remote_path+'/manifest.version',headers={'Authorization':'Basic '+auth})
    with opener.open(req,timeout=15) as response: manifest=json.load(response)
    record('Classic peer incremental history',{'rows':remote_rows,'patchCount':len(manifest['patches'])})
    assert manifest['patches']
    for label in ('main','peer'):
        job=cli(label,'call','sync.enable',{'enabled':False})
        assert wait(job['jobId'],label)['state']=='succeeded'
    record('Classic Dandanplay remote',prefs_public('main',['dandanplay_remote_base_url','dandanplay_remote_token_required']))
    call('media.sources.update',{'sourceId':source,'url':remote_url})
    call('media.sources.remove',{'sourceId':source})
    # A real second worktree instance serves NipaPlay's Classic management API.
    cli('peer','call','media.sources.list',{})
    shared=call('media.sources.add',{'type':'nipaplay','name':'共享测试端','url':peer_url})['source']['sourceId']
    call('media.sources.login',{'sourceId':shared})
    call('media.sources.check',{'sourceId':shared})
    call('media.sources.remote_admin.status',{'sourceId':shared})
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'test','type':'smb','names':['共享端测试 SMB']})
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'browse','type':'smb','name':'共享端测试 SMB','paths':['/'+configs['smb']['share']]})
    roots=peer['root']/'data/fixture'
    call('media.sources.browse',{'sourceId':shared})
    episodes=call('media.sources.browse',{'sourceId':shared,'parentId':'28'})['entries']
    if episodes:
        call('media.sources.query',{'sourceId':shared,'itemIds':[episodes[0]['id']]})
        call('media.sources.play',{'sourceId':shared,'itemId':episodes[0]['id'],'startPositionMs':2000})
        time.sleep(.7); call('playback.state',allow_failure=True); capture('shared-playing'); call('playback.close')
    spare=peer['root']/'data/extra'; spare.mkdir()
    call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'add','folders':[{'path':str(spare),'scan':False}]})
    call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'scan','folders':[{'path':str(spare)}]})
    call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'rescan','skipPreviouslyMatchedUnwatched':True})
    time.sleep(.4)
    call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'remove','paths':[str(spare)]})
    spare.mkdir(exist_ok=True)
    call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'add','folders':[{'path':str(spare),'scan':False}]})
    spare.rmdir()
    cleanup_folders=call('media.sources.remote_admin.folders',{'sourceId':shared,'operation':'cleanup'})
    assert cleanup_folders['results'][0]['removed']==1
    assert all(f['path']!=str(spare) for f in cleanup_folders['state']['folders'])
    setup=call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'configure','connections':[{'type':'webdav','name':'匿名影片','url':remote_url+'/dav','username':''}]})
    assert wait(setup['jobId'])['state']=='succeeded'
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'test','type':'webdav','names':['匿名影片']})
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'browse','type':'webdav','name':'匿名影片','paths':['/']})
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'scan','type':'webdav','name':'匿名影片','paths':['/empty','/']})
    login=call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'configure','connections':[{'type':'smb','name':'交给用户登录','host':'127.0.0.1','port':1445,'username':configs['smb']['user_name']}]})
    time.sleep(.3); capture('peer-login'); call('task.cancel',{'jobId':login['jobId']}); wait(login['jobId'])
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'remove','type':'webdav','names':['匿名影片']})
    call('media.sources.remote_admin.connections',{'sourceId':shared,'operation':'remove','type':'smb','names':['共享端测试 SMB']})
    record('Classic peer folders',prefs_public('peer',['nipaplay_scanned_folders']))
    # Real saved WebDAV/SMB discovery and explicit starting paths.
    for kind,sid in [('webdav','webdav:x28-dav'),('smb','smb:x28-smb')]:
        call('media.sources.check',{'sourceId':sid})
        entries=call('media.sources.browse',{'sourceId':sid})['entries']
        parent=next((e['id'] for e in entries if e['isDirectory']),'/')
        if kind=='smb' and parent=='/': parent='/'+configs['smb']['share']
        sync=call('media.sources.sync',{'sourceId':sid,'parentIds':[parent]})
        wait(sync['jobId'])
    anon=call('media.sources.add',{'type':'webdav','name':'匿名测试','url':remote_url+'/dav'})['source']['sourceId']
    call('media.sources.check',{'type':'webdav','url':remote_url+'/dav'})
    scrape=call('media.sources.scrape',{'sourceId':anon,'paths':['/empty','/']}); wait(scrape['jobId'])
    failed_source=call('media.sources.add',{'type':'webdav','name':'断开测试','url':remote_url+'/offline'})['source']['sourceId']
    call('media.sources.check',{'sourceId':failed_source},True)
    failure_state=next(s for s in call('media.sources.list')['sources'] if s['sourceId']==failed_source)
    assert failure_state['connectionState']=='failed' and failure_state.get('error')
    record('saved source connection failure',failure_state)
    call('media.sources.remove',{'sourceId':failed_source})
    # Download success -> session removal -> fixture file removal -> same content again.
    source_url=f'http://127.0.0.1:{http_port}/sintel.torrent'
    first=call('download.add',{'source':source_url,'downloadDirectory':str(main['root']/'data/downloads/x28'),'createFolderForTask':False})['job']['jobId']
    assert wait(first)['state']=='succeeded'
    read=call('download.read',{'jobId':first}); wire_before=wire['servedBytes']
    receipt=read['job']['receipt']
    call('download.remove',{'jobId':first})
    files=read['task']['files']
    for f in files:
        p=Path(f['path']); assert p.is_relative_to(main['root']); p.unlink()
    second=call('download.add',{'source':source_url,'downloadDirectory':str(main['root']/'data/downloads/x28'),'createFolderForTask':False})['job']['jobId']
    assert second!=first
    assert wait(second)['state']=='succeeded'
    old=call('task.get',{'jobId':first})
    assert old['job']['receipt']==receipt
    record('redownload wire',{'oldJobId':first,'newJobId':second,'oldReceiptPreserved':True,'bytesBefore':wire_before,'bytesAfter':wire['servedBytes'],'downloadedAgain':wire['servedBytes']>wire_before})
    call('media.sources.list')
    call('state.query',{'view':'activity','limit':100,'select':['type','title','actor','origin','subjectId','jobId','facts']})
    capture('complete')
    call('media.sources.remove',{'sourceId':shared})
    record('experiment result',{'completed':True})
except Exception as error:
    record('experiment failure',{'error':str(error),'type':type(error).__name__})
    raise
finally:
    for proc,log in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=10)
        log.close()
    for server in servers:
        server.shutdown(); server.server_close()
    if 'main' in profiles:
        # Only the uniquely named directory created by this experiment.
        assert remote_path.startswith('/NipaPlay/x28-')
        url=sync_url.rstrip('/')+remote_path
        req=urllib.request.Request(url,method='DELETE')
        import base64
        auth=base64.b64encode((configs['webdav']['user_name']+':'+configs['webdav']['password']).encode()).decode()
        req.add_header('Authorization','Basic '+auth)
        try:
            with opener.open(req,timeout=15): pass
        except urllib.error.HTTPError as e:
            if e.code!=404: record('remote cleanup',{'httpStatus':e.code})
        except urllib.error.URLError:
            record('remote cleanup',{'serverUnavailable':True})
    for p in profiles.values(): shutil.rmtree(p['root'])
    if dav_container:
        subprocess.run(['docker','--context','colima-nipa-test','rm','-f',dav_container],capture_output=True,check=True)
    if dav_root: shutil.rmtree(dav_root)
    record('cleanup',{'pids':[p.pid for p,_ in processes],'processesExited':all(p.poll() is not None for p,_ in processes),'profilesRemoved':all(not p['root'].exists() for p in profiles.values())})
