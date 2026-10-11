import json, os, pathlib, runpy, time, urllib.request, sys

workspace = pathlib.Path(__file__).resolve().parents[4]
if not os.environ.get('NIPAPLAY_PROFILE', '').startswith('x15-'):
    raise RuntimeError('X15 probes require an explicitly selected temporary x15- profile')
n = runpy.run_path(str(workspace / 'assets/next/harness/nipa'))
c = n['Client']()
config = json.loads(pathlib.Path('/tmp/nipa-next/testservers.json').read_text())['jellyfin']
secrets = (c.token, config['password'], config['access_token'])
records = []
output = pathlib.Path(sys.argv[1])

def call(action, inputs):
    request = urllib.request.Request(c.url, data=json.dumps(dict(operation='call', action=action, input=inputs)).encode(),
        headers={'Authorization': 'Bearer '+c.token, 'Content-Type':'application/json'})
    started = time.monotonic()
    try:
        with c.opener.open(request, timeout=8) as response:
            result = json.load(response)
    except Exception as e:
        result = {'status':'transport_error', 'error':type(e).__name__}
    elapsed = round((time.monotonic()-started)*1000, 2)
    record = {'action':action, 'elapsedMs':elapsed, 'response': n['redact'](result, secrets)}
    records.append(record)
    output.write_text(json.dumps(records,ensure_ascii=False,indent=2))
    state = result.get('result',{}).get('state',{})
    print(action, elapsed, result.get('status'), {k:state[k] for k in ('status','positionMs','durationMs','paused') if k in state}, flush=True)
    if result.get('status') not in ('completed','accepted'):
        if result.get('status') == 'failed': print(json.dumps(n['redact'](result,secrets)),flush=True)
        raise RuntimeError('probe failed; '+action)
    return result.get('result',result)

if sys.argv[2] == 'local':
    path = next(p for p in sorted((pathlib.Path.home()/'Documents/莉可丽丝：友谊是时间的窃贼').rglob('*')) if p.suffix=='.mp4')
else:
    source = call('media.sources.add', {'type':'jellyfin','name':'X15 temporary Jellyfin','url':config['base_url'],'username':config['user_name']})['source']['sourceId']
    login = call('media.sources.login',{'sourceId':source,'method':'password','password':config['password']})
    if 'jobId' in login:
        for _ in range(30):
            job=call('task.get',{'jobId':login['jobId']})['job']
            if job['state']=='succeeded':break
            if job['state']=='failed':raise RuntimeError('login failed')
            time.sleep(.2)
    entries=call('media.sources.browse',{'sourceId':source,'recursive':True})['entries']
    path=next(e['path'] for e in entries if e.get('path','') and e['path'].startswith('jellyfin://'))

call('playback.open',{'path':str(path)})
time.sleep(2)
call('playback.state',{})
for i in range(int(sys.argv[3]) if len(sys.argv)>3 else 20):
    call('playback.state',{})
    call('playback.set_paused',{'paused':True})
    time.sleep(.15)
    call('playback.state',{})
    call('playback.seek',{'positionMs':10000+i*2000})
    time.sleep(.2)
    call('playback.set_paused',{'paused':False})
    time.sleep(.25)
    call('playback.state',{})
    if i%5==0:call('playback.tracks',{})
call('playback.close',{})
