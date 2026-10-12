"""Isolated X40 body / real DeepSeek run. Never launches the installed app."""
import datetime, json, os, re, shutil, subprocess, sys, threading, time
from pathlib import Path
import urllib.parse, urllib.request
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'scripts/next'))
from x23_vm import LabVM
from local_seed import seed

workspace=Path(__file__).resolve().parents[4]
mode=sys.argv[1]; assert mode in ('body','delivery','agent')
evidence=Path(__file__).parent/mode; evidence.mkdir(parents=True,exist_ok=True)
profile=f'x40-{mode}-{os.getpid()}'
root=Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/profile
root.mkdir(mode=0o700); data=root/'data'; data.mkdir()
downloads=data/'downloads'; downloads.mkdir()
harness=root/'harness'; harness.mkdir()
shutil.copytree(workspace/'assets/next/harness',harness,dirs_exist_ok=True)
(harness/'nipa').chmod(0o755)
subprocess.run(['git','-C',str(harness),'init','-q'],check=True)
home=root/'codex-home'; home.mkdir(mode=0o700)
config=(Path.home()/'.codex/config.toml').read_text()
config=re.sub(r'(?m)^model\s*=.*$','model = "deepseek-v4.1-flash"',config,count=1)
(home/'config.toml').write_text(config); (home/'config.toml').chmod(0o600)
shutil.copy2(Path.home()/'.codex/auth.json',home/'auth.json')
(home/'skills').symlink_to(Path.home()/'.codex/skills',target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem',root/'system-ca.pem')
(root/'preferences.json').write_text(json.dumps({'flutter.labs_enable_agent_endpoint':True,
    'flutter.labs_use_next_interface':True,'flutter.next_harness_path':str(harness),
    'flutter.downloader_enabled':True,'flutter.torrent_download_directory':str(downloads),
    'flutter.downloader_auto_scan_completed_tasks':False,'flutter.auto_sync_enabled':False}))
env=os.environ.copy(); env.pop('NIPAPLAY_LAB_QUIET',None)
hosts=['127.0.0.1','localhost']+[urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"',config)]
env.update(NIPAPLAY_PROFILE=profile,CODEX_HOME=str(home),CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'),
    SSL_CERT_FILE=str(root/'system-ca.pem'),NO_PROXY=','.join(hosts),no_proxy=','.join(hosts))
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
records=[]; app=vm=None; servers=[]; trace=[]; gate=threading.Event()
def strings(value):
    if isinstance(value,dict):
        for v in value.values(): yield from strings(v)
    elif isinstance(value,list):
        for v in value: yield from strings(v)
    elif isinstance(value,str): yield value
secrets=set(v for v in strings(json.loads((home/'auth.json').read_text())) if len(v)>15)
secrets.update(v for k,v in env.items() if re.search(r'token|secret|password|api.?key',k,re.I) and len(v)>8)
def sanitized(text):
    if (root/'endpoint.json').exists(): secrets.add(json.loads((root/'endpoint.json').read_text())['token'])
    for secret in sorted(secrets,key=len,reverse=True): text=text.replace(secret,'[REDACTED]')
    return text
def record(label,value):
    value=json.loads(sanitized(json.dumps(value,ensure_ascii=False)))
    records.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'label':label,'value':value})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label,json.dumps(value,ensure_ascii=False),flush=True)
def call(action,inputs,save=True):
    endpoint=json.loads((root/'endpoint.json').read_text())
    req=urllib.request.Request(endpoint['url'],data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),
        headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    with opener.open(req,timeout=180) as response: value=json.load(response)
    if save: record(action,value)
    assert value['status'] in ('completed','accepted'),value
    return value.get('result',value)
def wait_file(jobid,seconds=120):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        v=call('download.read',{'jobId':jobid},save=False)
        if v['task'] and v['task']['files'][0]['complete']:
            rows=call('followup.list',{},save=False).get('followups',[])
            if rows and rows[0]['state']!='waiting': record('first-file-event-readback',v); return v
        time.sleep(1)
    raise RuntimeError('first-file deadline')
try:
    videos=[]
    for i in range(3):
        video=data/f'source-{i}.mp4'; videos.append(video)
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i',f'testsrc2=size=640x360:rate=24:duration={8+i}',
            '-c:v','libx264','-preset','fast','-crf','24',str(video)],check=True)
    torrent=harness/'collection.torrent'
    servers=list(seed(videos,torrent,f'X40 CC0 三集动画-{mode}',8 if mode!='agent' else 90,gate,trace))
    (harness/'CONTENT_LICENSE.txt').write_text('All three animated test-pattern videos were created by the experimenter with FFmpeg lavfi, with no third-party assets. The experimenter dedicates them to the public domain under CC0-1.0 and explicitly permits redistribution. Synthetic collection: not a named commercial anime.\n')
    record('legal-content',{'license':'CC0-1.0','producer':'experimenter','files':[{'name':f'第{i+1:02d}集.mp4','bytes':v.stat().st_size} for i,v in enumerate(videos)]})
    log=root/'app.log'
    with log.open('w') as stream:
        app=subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            cwd=workspace,env=env,stdout=stream,stderr=subprocess.STDOUT)
    until=time.monotonic()+120
    while time.monotonic()<until:
        assert app.poll() is None,'app exited'
        if (root/'endpoint.json').exists():
            try: vm=LabVM(log); break
            except (RuntimeError,OSError): pass
        time.sleep(.25)
    else: raise RuntimeError('startup deadline')
    assert vm.rpc('getVM')['pid']==app.pid
    call('app.instance',{})
    if mode!='agent':
        vm.chat('close')
        hook=harness/'hooks/download.file_completed'; hook.parent.mkdir(exist_ok=True)
        hook.write_text('#!/usr/bin/env python3\nimport json,sys\nv=json.load(sys.stdin)\nprint(json.dumps(v,ensure_ascii=False))\n')
        hook.chmod(0o755)
        job=call('download.add',{'source':str(torrent),'downloadDirectory':str(downloads),
            'createFolderForTask':False,'fileIndices':[0,2] if mode=='body' else [0,1]})['job']; jid=job['jobId']
        call('followup.register',{'when':{'event':'download.file_completed','objectId':jid+':0'},
            'instruction':'报告这个文件的实际完成事实。','title':'等第一集'})
        until=time.monotonic()+30
        while time.monotonic()<until:
            facts=call('download.read',{'jobId':jid},save=False)
            if facts['task'] and facts['task']['state']!='initializing': break
            time.sleep(.25)
        record('initial-selection',facts)
        if mode=='body':
            call('download.select_files',{'jobId':jid,'fileIndices':[0,1]})
            time.sleep(9); call('download.read',{'jobId':jid})
        first=wait_file(jid)
        assert first['job']['state']!='succeeded' and first['task']['files'][0]['complete']
        call('followup.list',{}); call('task.list',{'type':'harness.hook'})
        call('state.query',{'view':'library.files'})
        gate.set(); record('remaining-seed-released',True)
        until=time.monotonic()+120
        while time.monotonic()<until:
            done=call('task.get',{'jobId':jid},save=False)['job']
            if done['state'] in ('succeeded','failed','cancelled'): break
            time.sleep(1)
        record('selected-task-terminal',done); assert done['state']=='succeeded'
        previous=json.dumps(done['receipt'],sort_keys=True)
        expanded=call('download.select_files',{'jobId':jid,'fileIndices':[0,1,2]})
        replacement=expanded['job']['jobId']; assert replacement!=jid
        until=time.monotonic()+120
        while time.monotonic()<until:
            nextjob=call('task.get',{'jobId':replacement},save=False)['job']
            if nextjob['state'] in ('succeeded','failed','cancelled'): break
            time.sleep(1)
        record('expanded-task-terminal',nextjob); assert nextjob['state']=='succeeded'
        assert json.dumps(call('task.get',{'jobId':jid})['job']['receipt'],sort_keys=True)==previous
        call('download.read',{'jobId':replacement}); call('task.list',{'type':'harness.hook'})
    else:
        record('chat-header',vm.chat('status')['header'])
        prompt=f'把这套 CC0 三集动画合集下下来，第一集好了就告诉我。种子在 {torrent}，许可证在同目录 CONTENT_LICENSE.txt。\n这是隔离实验，只使用当前 harness 和连接的实例；外部文件只读，不启动或查找其他应用，不访问钥匙串或真实应用数据，不激活窗口、不点击、不重启。'
        record('user-prompt',prompt); record('turn',vm.chat('turn',text=prompt))
        until=time.monotonic()+600; signatures={}; phase=None; first_seen=None; final_seen=None
        while time.monotonic()<until:
            status=vm.chat('status'); live=status['liveness']; key=(live['status'],live.get('turnId'))
            if key!=phase: record('liveness',status); phase=key
            jobs=call('task.list',{'type':'download'},save=False).get('jobs',[])
            for job in jobs:
                jid=job['jobId']; facts=call('download.read',{'jobId':jid},save=False)
                task=facts['task']; sig=None if task is None else (task['finished'],tuple((f['included'],f['complete']) for f in task['files']))
                if sig!=signatures.get(jid): record('download-timeline',facts); signatures[jid]=sig
                if task and task['files'][0]['complete'] and first_seen is None:
                    first_seen=time.monotonic(); record('first-event-followups',call('followup.list',{},save=False))
                    record('first-event-hooks',call('task.list',{'type':'harness.hook'},save=False))
                    # Keep the rest unavailable for 45 seconds after first delivery to observe the awakened turn.
                if first_seen and time.monotonic()-first_seen>45 and not gate.is_set():
                    gate.set(); record('remaining-seed-released',True)
                if task and task['finished'] and all(f['included'] for f in task['files']):
                    final_seen=final_seen or time.monotonic()
            if final_seen and time.monotonic()-final_seen>60 and live['status'] not in ('starting','inProgress'): break
            time.sleep(1)
        else: record('watchdog-interrupt',vm.chat('interrupt'))
        header=vm.chat('status')['header']
        record('agent-thread',vm.chat('read',threadId=header['threadId']))
        call('followup.list',{}); call('task.list',{'type':'download'})
        call('state.query',{'view':'library.files'}); call('state.query',{'view':'library.works'})
        captured=call('ui.capture',{})
        subprocess.run(['sips','-s','format','jpeg',captured['path'],'--out',str(evidence/'result.jpg')],capture_output=True,check=True)
finally:
    if app is not None and app.poll() is None:
        if vm:
            try: vm.chat('close')
            except (RuntimeError,OSError): pass
        app.terminate()
        try: app.wait(timeout=30)
        except subprocess.TimeoutExpired: app.kill(); app.wait(timeout=10)
    for server in servers: server.shutdown(); server.server_close()
    (evidence/'peer-trace.json').write_text(json.dumps(trace,indent=2))
    if (root/'chat-events.jsonl').exists(): (evidence/'chat-events.jsonl').write_text(sanitized((root/'chat-events.jsonl').read_text()))
    if (root/'app.log').exists(): (evidence/'app.log').write_text(sanitized((root/'app.log').read_text(errors='replace')))
    shutil.rmtree(root)
    record('cleanup',{'pid':app.pid if app else None,'profileRemoved':not root.exists()})
