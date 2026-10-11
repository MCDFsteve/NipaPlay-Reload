"""Recheck only the UI projection changed after the initial experiment."""
from pathlib import Path
source=Path(__file__).with_name('experiment.py').read_text()
exec(source.split("try:\n    main=start('main')",1)[0])
evidence=evidence/'home-final'
evidence.mkdir(exist_ok=True)
output_file='operations.json'
try:
    start('main')
    home=ui('home')
    continuing=next(s for s in home['shelves'] if s['kind']=='continueWatching')
    assert all('第 0 集' not in i['caption'] for i in continuing['items'])
    airing=next(s for s in home['shelves'] if s['kind']=='airing')
    assert airing['items'][0]['caption']=='第 14 集 · 今天 23:30'
    work=ui('work',workId=airing['items'][0]['work']['workId'])
    assert work['danmaku']==[]
    cli('settings.set',{'key':'labs_use_next_interface','value':True})
    time.sleep(.7)
    capture('next-home-final')
    record('complete',{'runtimeCalendar':True,'episodeNumber':work['next']['number'],'emptyDanmaku':True})
finally:
    for proc,log in processes:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=30)
        log.close()
    for p in profiles.values():shutil.rmtree(p['root'])
    record('cleanup',{'pids':[p.pid for p,_ in processes],
        'processesExited':all(p.poll() is not None for p,_ in processes),
        'profilesRemoved':all(not p['root'].exists() for p in profiles.values())})
