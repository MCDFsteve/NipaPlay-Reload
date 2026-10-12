"""Resume the interrupted X35 thread without repeating downloads or scans."""
import json, os, re, shutil, subprocess, sys, time, urllib.parse, urllib.request
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'scripts/next'))
from x23_vm import LabVM

workspace=Path(__file__).resolve().parents[4]
root=Path.home()/'Library/Application Support/NipaPlay/LabProfiles/x35-agent-83287'
evidence=Path(__file__).parent/'agent'
records=json.loads((evidence/'operations.json').read_text())
home=root/'codex-home'; config=(home/'config.toml').read_text()
hosts=['127.0.0.1','localhost']+[urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"',config)]
env=os.environ.copy(); env.pop('NIPAPLAY_LAB_QUIET',None)
env.update(NIPAPLAY_PROFILE=root.name,CODEX_HOME=str(home),CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'),SSL_CERT_FILE=str(root/'system-ca.pem'),NO_PROXY=','.join(hosts),no_proxy=','.join(hosts))
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
app=vm=None
def record(label,value):
    records.append({'at':time.time(),'label':label,'value':value})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label,json.dumps(value,ensure_ascii=False),flush=True)
def call(action,inputs):
    endpoint=json.loads((root/'endpoint.json').read_text())
    req=urllib.request.Request(endpoint['url'],data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    with opener.open(req,timeout=120) as response: value=json.load(response)
    record(action,value); assert value['status']=='completed',value
    return value['result']
def capture(name):
    v=call('ui.capture',{})
    subprocess.run(['sips','-s','format','jpeg',v['path'],'--out',str(evidence/(name+'.jpg'))],capture_output=True,check=True)
try:
    log=root/'resume-app.log'
    (root/'endpoint.json').unlink(missing_ok=True)
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
    record('resume-instance',call('app.instance',{})); assert vm.rpc('getVM')['pid']==app.pid
    header=vm.chat('status')['header']; record('resume-header',header)
    record('interrupted-thread',vm.chat('read',threadId=header['threadId']))
    capture('interrupted')
    record('resume-prompt','继续刚才的整理。')
    started=time.monotonic(); record('resume-turn',vm.chat('turn',text='继续刚才的整理。'))
    deadline=started+600; previous=None
    while time.monotonic()<deadline:
        status=vm.chat('status')['liveness']
        if status['status']!=previous:
            record('resume-liveness',status); previous=status['status']
        if previous not in ('starting','inProgress'): break
        time.sleep(1)
    else: record('resume-watchdog-interrupt',vm.chat('interrupt'))
    record('resume-turn-seconds',time.monotonic()-started)
    header=vm.chat('status')['header']; record('agent-thread',vm.chat('read',threadId=header['threadId']))
    call('state.query',{'view':'library.files','limit':100})
    works=call('state.query',{'view':'library.works','limit':100})['rows']
    for w in works: call('media.metadata.ui_facts',{'workId':w['workId']})
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
    record('cleanup',{'pid':app.pid if app else None,'profileRemoved':not root.exists()})
