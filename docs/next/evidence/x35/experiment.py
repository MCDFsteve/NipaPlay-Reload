"""Disposable X35 host. Synthetic Classic fixture is explicitly labelled."""
import hashlib, json, os, re, shutil, socket, sqlite3, subprocess, sys, threading, time
from pathlib import Path
import urllib.parse, urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'scripts/next'))
from x23_vm import LabVM
from local_seed import seed

workspace = Path(__file__).resolve().parents[4]
mode = sys.argv[1]
evidence = Path(__file__).parent / mode
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x35-' + mode + '-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
root.mkdir(mode=0o700)
data = root / 'data'; data.mkdir()
downloads = data / 'downloads'; downloads.mkdir()
video = downloads / 'x35-cc0.mp4'
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=160x90:d=2', '-c:v', 'libx264', str(video)], check=True)
db = sqlite3.connect(data / 'watch_history.db')
db.execute('CREATE TABLE watch_history(id INTEGER PRIMARY KEY AUTOINCREMENT,file_path TEXT UNIQUE NOT NULL,media_key TEXT,anime_name TEXT NOT NULL,episode_title TEXT,episode_id INTEGER,anime_id INTEGER,watch_progress REAL NOT NULL,last_position INTEGER NOT NULL,duration INTEGER NOT NULL,last_watch_time TEXT NOT NULL,thumbnail_path TEXT,is_from_scan INTEGER NOT NULL)')
db.execute("INSERT INTO watch_history(file_path,anime_name,episode_title,episode_id,anime_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,0,0,2000,?,1)", (str(video), 'X35 CC0 色卡（合成 Classic 对照）', '第1集', 90000101, 900001, '2026-10-12T10:00:00'))
db.execute('PRAGMA user_version=5'); db.commit(); db.close()
cache = {'id':900001, 'name':'X35 CC0 色卡（合成 Classic 对照）', 'name_cn':'X35 CC0 色卡（合成 Classic 对照）', 'summary':'实验者生成并以 CC0 提供的两秒蓝色色卡。', 'imageUrl':'https://lycoris-recoil.com/shortmovie/assets/img/main.jpg', 'language':'zh', 'totalEpisodes':1}
prefs = {'flutter.labs_enable_agent_endpoint':True, 'flutter.labs_use_next_interface':True,
         'flutter.next_harness_path':str(root / 'harness'), 'flutter.downloader_enabled':mode!='before',
         'flutter.auto_sync_enabled':False, 'flutter.bangumi_detail_900001':json.dumps({'timestamp':int(time.time()*1000),'animeDetail':cache}),
         'flutter.downloader_auto_scan_completed_tasks':False}
(root / 'preferences.json').write_text(json.dumps(prefs, ensure_ascii=False))
home = root / 'codex-home'; home.mkdir(mode=0o700)
config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
(home / 'config.toml').write_text(config); (home / 'config.toml').chmod(0o600)
shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
(home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
env = os.environ.copy(); env.pop('NIPAPLAY_LAB_QUIET', None)
hosts = ['127.0.0.1','localhost'] + [urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"',config)]
env.update(NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home), CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'), SSL_CERT_FILE=str(root/'system-ca.pem'), NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
records=[]; app=vm=None; servers=[]
def record(label,value):
    records.append({'at':time.time(),'label':label,'value':value})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label, json.dumps(value,ensure_ascii=False),flush=True)
def call(action,inputs):
    endpoint=json.loads((root/'endpoint.json').read_text())
    req=urllib.request.Request(endpoint['url'],data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    with opener.open(req,timeout=240) as response: value=json.load(response)
    record(action,value)
    assert value['status'] in ('completed','accepted'),value
    return value.get('result',value)
def capture(name):
    v=call('ui.capture',{})
    subprocess.run(['sips','-s','format','jpeg',v['path'],'--out',str(evidence/(name+'.jpg'))],capture_output=True,check=True)
def wait(job):
    record('job-return',job)
    jobid=job.get('jobId') or job.get('job',{}).get('jobId')
    assert jobid,job
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        v=call('task.get',{'jobId':jobid})['job']
        if v.get('state') in ('succeeded','failed','cancelled'): return v
        time.sleep(2)
    raise RuntimeError('job deadline')
try:
    log=root/'app.log'
    with log.open('w') as stream:
        app=subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],cwd=workspace,env=env,stdout=stream,stderr=subprocess.STDOUT)
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        assert app.poll() is None,'app exited'
        if (root/'endpoint.json').exists():
            try:
                vm=LabVM(log)
                if vm.chat('status')['header'].get('model'): break
            except (RuntimeError,OSError): pass
        time.sleep(.25)
    else: raise RuntimeError('startup timeout')
    record('instance',call('app.instance',{})); assert vm.rpc('getVM')['pid']==app.pid
    record('chat-header',vm.chat('status')['header'])
    works=call('state.query',{'view':'library.works'})['rows']; work=works[0]; wid=work['workId']
    if mode in ('before','after'):
        call('state.query',{'view':'library.files'})
        call('media.metadata.ui_facts',{'workId':wid})
        call('media.identity.bind_batch',{'requestId':profile+'-tmdb','entries':[{'kind':'work','entityId':wid,'reason':'合成图片身份对照，不代表真实作品匹配','ref':{'provider':'tmdb','objectType':'tv','externalId':'202555','scope':''}}]})
        call('media.metadata.import_batch',{'requestId':profile+'-image','entries':[{'ref':{'provider':'dandanplay','objectType':'anime','externalId':'900001','scope':''},'language':'zh-CN','fields':{'imageUrl':cache['imageUrl']}}]})
        call('media.metadata.ui_facts',{'workId':wid})
        record('ui-work',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='work',workId=wid))
    if mode not in ('before','agent'):
        torrent=data/'cc0.torrent'; servers=list(seed(video,torrent))
        outcome=call('download.add',{'source':str(torrent),'downloadDirectory':str(downloads),'createFolderForTask':False})
        record('download-return',outcome)
        job=outcome['jobs'][0] if 'jobs' in outcome else outcome['job']
        done=wait({'jobId':job['jobId']})
        assert done['state']=='succeeded',done
        receipt=done['receipt']['details']
        record('download-completed',receipt)
        fid=receipt['fileIds'][0]
        episodes=call('state.query',{'view':'library.episodes'})['rows']
        episode=next(e for e in episodes if e['parentId'])
        call('media.identity.bind_batch',{'requestId':profile+'-download-bind','entries':[{
            'kind':'file','entityId':fid,'ref':{'provider':'dandanplay','objectType':'episode','externalId':'90000101','scope':'anime/900001'},
            'localEpisodeIds':[episode['id']],'reason':'合成 CC0 下载播放对照'}]})
        call('state.query',{'view':'library.files'})
        record('download-ui-work',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='work',workId=wid))
        record('download-ui-home',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='home'))
    if mode!='before':
        associated=data/'associated.torrent'; servers.extend(seed(video,associated,video.name))
        associated_job=call('download.add',{'source':str(associated),'downloadDirectory':str(downloads),'createFolderForTask':False})['job']
        associated_done=wait({'jobId':associated_job['jobId']})
        record('known-work-download-completed',associated_done)
        assert wid in associated_done['receipt']['details']['workIds']
        record('known-work-ui-home',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='home'))
        capture('download-ready')
    incoming=data/'incoming'; incoming.mkdir()
    candidates=sorted(Path('/Volumes/Anime/长安十二时辰').rglob('*.mkv')) + sorted(Path('/Volumes/Anime/长安十二时辰').rglob('*.mp4'))
    assert len(candidates)>=3
    (incoming/candidates[0].name).symlink_to(candidates[0])
    call('media.library.roots.add',{'paths':['/Volumes/Anime/长安十二时辰',str(incoming)]})
    wait(call('media.library.scan',{'root':str(incoming),'requestId':profile+'-scan-1'}))
    call('state.query',{'view':'library.files'})
    if mode!='before':
        time.sleep(3)
        for f in candidates[1:3]: (incoming/f.name).symlink_to(f)
        wait(call('media.library.scan',{'root':str(incoming),'requestId':profile+'-scan-2'}))
        call('state.query',{'view':'library.files'})
        prompt='《长安十二时辰》放进来了，帮我整理一下，弄好看点。\n这是隔离实验，仅当前 harness 与连接实例；外部文件只读；不要启动或查找其他应用、访问钥匙串、读取真实应用数据、激活窗口、点击、重启或下载。'
        record('user-prompt',prompt); started=time.monotonic(); record('turn',vm.chat('turn',text=prompt))
        deadline=started+600; phase=None
        while time.monotonic()<deadline:
            status=vm.chat('status')['liveness']
            if status['status']!=phase: record('liveness',status); phase=status['status']
            if phase not in ('starting','inProgress'): break
            time.sleep(1)
        else: record('watchdog-interrupt',vm.chat('interrupt'))
        record('turn-seconds',time.monotonic()-started)
        header=vm.chat('status')['header']; record('agent-thread',vm.chat('read',threadId=header['threadId']))
        call('state.query',{'view':'library.works'})
        for w in call('state.query',{'view':'library.works'})['rows']: call('media.metadata.ui_facts',{'workId':w['workId']})
        record('ui-home',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='home'))
    capture('result')
finally:
    if app is not None and app.poll() is None:
        if vm:
            try: vm.chat('close')
            except (RuntimeError,OSError): pass
        app.terminate(); app.wait(timeout=30)
    if (root/'chat-events.jsonl').exists(): shutil.copy2(root/'chat-events.jsonl',evidence/'chat-events.jsonl')
    shutil.rmtree(root)
    for server in servers: server.shutdown(); server.server_close()
    record('cleanup',{'pid':app.pid if app else None,'profileRemoved':not root.exists()})
