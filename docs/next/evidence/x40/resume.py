"""Repair only the lab seed, preserving the live app, torrent, job and Agent turn.
The first driver delayed every connection longer than librqbit's request timeout.
After terminating that driver by PID, bind the same loopback peer/tracker ports
with responsive data. Do not submit another user turn or restart the application.
"""
import datetime,json,os,re,shutil,signal,sys,threading,time,urllib.request
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'scripts/next'))
from x23_vm import LabVM
from local_seed import seed
evidence=Path(__file__).parent/'agent'
records=json.loads((evidence/'operations.json').read_text())
first=next(x for x in records if x['label']=='liveness')
root=Path(first['value']['environment']['CODEX_HOME']).parent
app_pid=next(x for x in records if x['label']=='app.instance')['value']['result']['pid']
vm=LabVM(root/'app.log'); assert vm.rpc('getVM')['pid']==app_pid
def strings(v):
    if isinstance(v,dict):
        for x in v.values(): yield from strings(x)
    elif isinstance(v,list):
        for x in v: yield from strings(x)
    elif isinstance(v,str): yield v
secrets={x for x in strings(json.loads((root/'codex-home/auth.json').read_text())) if len(x)>15}
endpoint=json.loads((root/'endpoint.json').read_text()); secrets.add(endpoint['token'])
secrets.update(v for k,v in os.environ.items() if re.search(r'token|secret|password|api.?key',k,re.I) and len(v)>8)
def sanitized(s):
    for secret in sorted(secrets,key=len,reverse=True):s=s.replace(secret,'[REDACTED]')
    return s
def record(label,value):
    records.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'label':label,
        'value':json.loads(sanitized(json.dumps(value,ensure_ascii=False)))})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label,flush=True)
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def call(action,inputs,save=True):
    req=urllib.request.Request(endpoint['url'],data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),
        headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    with opener.open(req,timeout=180) as response:v=json.load(response)
    if save:record(action,v)
    assert v['status'] in ('completed','accepted'),v
    return v.get('result',v)
torrent=root/'harness/collection.torrent'; original=torrent.read_bytes()
tracker_port=int(re.search(rb'127.0.0.1:(\d+)/announce',original)[1])
initial=next(x for x in records if x['label']=='download-timeline')['value']['task']
peer_port=int(next(iter(initial['health']['sources']['peers'])).split(':')[1])
gate=threading.Event();trace=[];servers=[]
try:
    servers=list(seed([root/'data'/f'source-{i}.mp4' for i in range(3)],torrent,
        'X40 CC0 三集动画-agent',0,gate,trace,peer_port=peer_port,tracker_port=tracker_port))
    assert torrent.read_bytes()==original,'Repair must preserve exact torrent metadata'
    record('fixture-repair',{'sameAppPid':app_pid,'samePeerPort':peer_port,'sameTrackerPort':tracker_port,
        'sameTorrentBytes':True,'sameThreadId':first['value']['header']['threadId'],
        'reason':'The initial per-connection 90 second delay exceeded engine request timeout; responsive seed now uses same endpoints.'})
    deadline=datetime.datetime.fromisoformat(first['at']).timestamp()+600
    signatures={}; fup_signature=None; phase=None; first_seen=None; final_seen=None
    while time.time()<deadline:
        state=vm.chat('status');live=state['liveness'];key=(live['status'],live.get('turnId'),live.get('latestError'))
        if key!=phase:record('liveness',state);phase=key
        jobs=call('task.list',{'type':'download'},save=False).get('jobs',[])
        for job in jobs:
            facts=call('download.read',{'jobId':job['jobId']},save=False);task=facts['task']
            sig=None if not task else (task['finished'],tuple((f['included'],f['complete']) for f in task['files']))
            if sig!=signatures.get(job['jobId']):record('download-timeline',facts);signatures[job['jobId']]=sig
            if task and task['files'][0]['complete'] and first_seen is None:
                first_seen=time.monotonic();record('first-event-followups',call('followup.list',{},save=False))
                call('state.query',{'view':'library.files'})
            if first_seen and time.monotonic()-first_seen>45 and not gate.is_set():
                gate.set();record('remaining-seed-released',True)
            if task and task['finished'] and all(f['included'] for f in task['files']):final_seen=final_seen or time.monotonic()
        fups=call('followup.list',{},save=False)
        fupkey=json.dumps([(v['id'],v['state'],v.get('turnId')) for v in fups['followups']])
        if fupkey!=fup_signature:record('followup-timeline',fups);fup_signature=fupkey
        if final_seen and time.monotonic()-final_seen>60 and live['status'] not in ('starting','inProgress'):break
        time.sleep(1)
    else:record('watchdog-interrupt',vm.chat('interrupt'))
    state=vm.chat('status');record('final-liveness',state)
    record('agent-thread',vm.chat('read',threadId=state['header']['threadId']))
    call('followup.list',{});call('task.list',{'type':'download'});call('task.list',{'type':'harness.hook'})
    call('state.query',{'view':'library.files'});call('state.query',{'view':'library.works'})
    import subprocess
    v=call('ui.capture',{})
    subprocess.run(['sips','-s','format','jpeg',v['path'],'--out',str(evidence/'result.jpg')],capture_output=True,check=True)
finally:
    try:vm.chat('close')
    except (RuntimeError,OSError):pass
    os.kill(app_pid,signal.SIGTERM)
    until=time.monotonic()+30
    while time.monotonic()<until:
        try:os.kill(app_pid,0)
        except ProcessLookupError:break
        time.sleep(.2)
    else:os.kill(app_pid,signal.SIGKILL)
    for server in servers:server.shutdown();server.server_close()
    (evidence/'peer-trace.json').write_text(json.dumps(trace,indent=2))
    for name in ('chat-events.jsonl','app.log'):
        if (root/name).exists():(evidence/name).write_text(sanitized((root/name).read_text(errors='replace')))
    shutil.rmtree(root)
    record('cleanup',{'pid':app_pid,'profileRemoved':not root.exists()})
