"""X32 isolated worktree instances. No login secrets or user data are used."""
import json, os, re, shutil, sqlite3, subprocess, sys, time
from datetime import datetime, timedelta
from pathlib import Path

workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).parent
sys.path.insert(0, str(workspace/'scripts/next'))
from x23_vm import LabVM
exe = workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
run_id = str(os.getpid())
shared_only = '--shared-only' in sys.argv
play_only = '--play-only' in sys.argv
shared_only = shared_only or play_only
output_file = 'operations-play.json' if play_only else 'operations-shared.json' if shared_only else 'operations.json'
profiles, processes, records = {}, [], []

def record(label, value):
    records.append({'label':label,'value':value})
    (evidence/output_file).write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label, json.dumps(value,ensure_ascii=False),flush=True)

def start(label, new=True):
    if new:
        name='x32-'+label+'-'+run_id
        root=Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/name
        assert not root.exists()
        root.mkdir(mode=0o700)
        media=root/'data/fixture'; media.mkdir(parents=True)
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-f','lavfi','-i',
            'color=c=blue:s=320x180:r=1','-t','120','-c:v','mpeg4','-q:v','31',str(media/'episode-1.mp4')],check=True)
        shutil.copy2(media/'episode-1.mp4',media/'episode-2.mp4')
        anime_id=32001 if label=='main' else 32002
        title='今晚的蓝色天空' if label=='main' else '共享的蓝色天空'
        schema=(workspace/'lib/models/watch_history_database.dart').read_text().split('CREATE TABLE watch_history(',1)[1].split("''');",1)[0]
        with sqlite3.connect(root/'data/watch_history.db') as db:
            db.execute('CREATE TABLE watch_history('+schema)
            db.execute('PRAGMA user_version=2')
            for number in (1,2):
                db.execute('INSERT INTO watch_history(file_path,anime_name,episode_title,anime_id,episode_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,?,?,?,?,?)',
                    (str(media/f'episode-{number}.mp4'),title,f'第 {number} 集',anime_id,anime_id*100+number,.4,48000,120000,datetime.now().isoformat(),0))
        now=datetime.now(); today=now.replace(hour=23,minute=30,second=0,microsecond=0)
        episodes=[{'episodeId':anime_id*100+i,'episodeTitle':f'第 {i} 集','airDate':(today if i==14 else today-timedelta(days=(14-i)*7)).isoformat()} for i in range(1,15)]
        anime={'id':anime_id,'name':title,'name_cn':title,'imageUrl':'','summary':'一起看一片蓝色的天空。',
            'airDay':now.isoweekday()%7,'isOnAir':True,'isFavorited':True,'totalEpisodes':14,'episodes':episodes,'episodeList':episodes}
        prefs={'flutter.labs_enable_agent_endpoint':True,'flutter.downloader_enabled':False,
            'flutter.labs_use_next_interface':False,'flutter.skip_danmaku_matching':True,
            'flutter.auto_sync_enabled':False,'flutter.nipaplay_scanned_folders':[str(media)],
            'flutter.dandanplay_shin_cache':json.dumps({'timestamp':int(time.time()*1000),'animes':[anime]},ensure_ascii=False),
            f'flutter.bangumi_detail_{anime_id}':json.dumps({'timestamp':int(time.time()*1000),'animeDetail':anime},ensure_ascii=False)}
        if label=='peer':prefs['flutter.web_server_auto_start']=True
        (root/'preferences.json').write_text(json.dumps(prefs,ensure_ascii=False)); (root/'preferences.json').chmod(0o600)
        (root/'codex-home').mkdir(mode=0o700)
        shutil.copy2('/etc/ssl/cert.pem',root/'system-ca.pem')
        env=os.environ.copy()
        for key in ('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'):env.pop(key,None)
        env.update(NIPAPLAY_PROFILE=name,CODEX_HOME=str(root/'codex-home'),
            NO_PROXY='127.0.0.1,localhost',no_proxy='127.0.0.1,localhost',
            CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'),SSL_CERT_FILE=str(root/'system-ca.pem'))
        profiles[label]={'root':root,'env':env,'generation':0}
    p=profiles[label]; p['generation']+=1
    (p['root']/'endpoint.json').unlink(missing_ok=True)
    log_path=evidence/f'{"play-" if play_only else "shared-" if shared_only else ""}{label}-{p["generation"]}.log'
    log=log_path.open('w')
    proc=subprocess.Popen([str(exe)],cwd=workspace,env=p['env'],stdout=log,stderr=subprocess.STDOUT)
    processes.append((proc,log)); p.update(process=proc,log=log_path)
    for _ in range(360):
        if proc.poll() is not None:raise RuntimeError('Worktree process exited: '+label)
        if (p['root']/'endpoint.json').exists() and (p['root']/'harness/nipa').exists():
            try:
                vm=LabVM(log_path)
                vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='observations')
                assert vm.rpc('getVM')['pid']==proc.pid
                p['vm']=vm; break
            except (RuntimeError,OSError,KeyError):pass
        time.sleep(.25)
    else:raise RuntimeError('Endpoint did not start: '+label)
    record('instance '+label,{'profile':p['root'].name,'pid':proc.pid,'vmPid':vm.rpc('getVM')['pid']})
    # The endpoint can be ready before Classic has mounted its Navigator.
    for _ in range(120):
        check_env=p['env'].copy();check_env['NIPAPLAY_ENDPOINT_FILE']=str(p['root']/'endpoint.json')
        check=subprocess.run(['./nipa','call','discover.home','{}'],cwd=p['root']/'harness',env=check_env,capture_output=True,text=True,timeout=30)
        if check.returncode==0:break
        time.sleep(.25)
    else:raise RuntimeError('Classic home did not mount: '+label)
    return p

def stop(label):
    proc=profiles[label]['process']
    if proc.poll() is None:proc.terminate();proc.wait(timeout=30)

def cli(action, inputs=None, label='main', verb='call'):
    p=profiles[label]; env=p['env'].copy();env['NIPAPLAY_ENDPOINT_FILE']=str(p['root']/'endpoint.json')
    cmd=['./nipa',verb,action]
    if inputs is not None:cmd.append(json.dumps(inputs,ensure_ascii=False))
    r=subprocess.run(cmd,cwd=p['root']/'harness',env=env,capture_output=True,text=True,timeout=120)
    value=json.loads(r.stdout);record(label+' '+verb+' '+action,value)
    if r.returncode:raise RuntimeError('nipa failed: '+action)
    return value.get('result',value)

def ui(op, **params):
    vm=profiles['main']['vm']
    value=vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op=op,**params)
    record('ui '+op,value)
    return value

def capture(name):
    value=cli('ui.capture',{})
    shutil.copy2(value['path'],evidence/(name+'.png'))

def history():
    with sqlite3.connect(profiles['main']['root']/'data/watch_history.db') as db:
        return db.execute('SELECT episode_title,watch_progress,last_position,duration,anime_id,episode_id FROM watch_history WHERE anime_id=32001 ORDER BY episode_id').fetchall()

try:
    main=start('main')
    if not shared_only:
        cli('media.library.import_history',{})
        home=ui('home')
        assert any(s['kind']=='airing' and s['items'][0]['caption']=='第 14 集 · 今天 23:30' for s in home['shelves'])
        work_id=next(s['items'][0]['work']['workId'] for s in home['shelves'] if s['kind']=='airing')
        with sqlite3.connect(main['root']/'data/next/next.db') as db:
            episode_ids=[r[0] for r in db.execute("SELECT e.id FROM media_entities e JOIN media_entities r ON r.id=e.parent_id WHERE e.kind='episode' AND r.parent_id=? ORDER BY e.rowid",(work_id,))]
        comments=main['root']/'data/fixture/comments.json'
        texts=['画面好美','音乐好好听','画面好美','太好看了','主角下一集会死','哈哈哈哈哈哈','https://example.test','一起看']
        comments.write_text(json.dumps([{'sourceTimeMs':1000+i*50 if i<7 else 45000,'text':s,'mode':1,'colorRgb':16777215,'sourceEntryId':str(i)} for i,s in enumerate(texts)],ensure_ascii=False))
        cli('danmaku.import',{'filePath':str(comments),'platform':'bilibili','platformVideoId':'x32-fixture','entityId':episode_ids[0]})
        work=ui('work',workId=work_id)
        assert '画面好美' in work['danmaku'] and not any('死' in s for s in work['danmaku'])
        cli('ui.open',{'animeId':32001});time.sleep(.7);capture('classic-before')
        cli('history.mark_watched_batch',{'entries':[{'episodeId':e,'watched':True} for e in episode_ids]})
        record('Classic watched',history());time.sleep(.5);capture('classic-watched')
        assert all(r[1]==1 and r[2]==r[3] for r in history())
        cli('history.mark_watched_batch',{'entries':[{'episodeId':e,'watched':False} for e in episode_ids]})
        record('Classic unwatched',history());time.sleep(.5);capture('classic-unwatched')
        assert all(r[1]==0 and r[2]==0 for r in history())
        cli('ui.close',{});cli('ui.open',{'page':'home'})
        cli('settings.set',{'key':'labs_use_next_interface','value':True})
        time.sleep(.7);capture('next-on')
        cli('settings.get',{'key':'labs_use_next_interface'})
        cli('settings.set',{'key':'labs_use_next_interface','value':False})
        time.sleep(.5);capture('next-off')
        cli('settings.history',{'key':'labs_use_next_interface'})
    peer=start('peer')
    peer_log=peer['log'].read_text(errors='replace')
    port=int(re.search(r'Remote access server started on port (\d+)',peer_log)[1])
    source=cli('media.sources.add',{'type':'nipaplay','name':'共享测试端','url':f'http://127.0.0.1:{port}'})['source']['sourceId']
    cli('media.sources.login',{'sourceId':source})
    cli('media.sources.check',{'sourceId':source})
    cli('media.sources.browse',{'sourceId':source})
    entries=cli('media.sources.browse',{'sourceId':source,'parentId':'32002'})['entries']
    entry=entries[0]
    # Construct the released X28 duplicate shape, then run the real startup migration.
    if not play_only: stop('main')
    next_db=main['root']/'data/next/next.db'
    with sqlite3.connect(next_db) as db:
        location=db.execute("SELECT file_id,locator,owner_device_id FROM media_locations WHERE source=? LIMIT 1",(source,)).fetchone()
        if location is None:location=db.execute("SELECT file_id,locator,owner_device_id FROM media_locations WHERE source LIKE ? LIMIT 1",(source+'%',)).fetchone()
        assert location
        file_id,url,owner=location
        db.execute('INSERT INTO media_entities(id,kind,revision,attributes) VALUES(?,?,?,?)',('x32-legacy-duplicate','file',0,json.dumps({'probe':{'legacy':True},'bindingRevision':0,'legacyNote':'保留这条旧记录'})))
        db.execute('INSERT INTO media_locations(id,file_id,source,owner_device_id,locator,available) VALUES(?,?,?,?,?,?)',('x32-legacy-location','x32-legacy-duplicate','remote',owner,url,1))
        db.execute('INSERT INTO media_legacy_history(location_id,fingerprint,payload) VALUES(?,?,?)',('x32-legacy-location','x32-evidence',json.dumps({'animeName':'共享的蓝色天空','watchProgress':.4})))
        db.execute('INSERT INTO media_overrides(entity_id,field,value,invocation_id) VALUES(?,?,?,?)',('x32-legacy-duplicate','overview',json.dumps('旧记录里的备注。'),'x32-old-edit'))
        count=db.execute('SELECT COUNT(DISTINCT file_id) FROM media_locations WHERE owner_device_id=? AND locator=?',(owner,url)).fetchone()[0]
        record('released duplicate fixture',{'distinctFiles':count,'legacyEvidence':True,'userEdit':True})
        assert count==2
        if not play_only:
            db.execute('DROP TABLE media_file_aliases');db.execute('PRAGMA user_version=11')
    if not play_only: start('main',new=False)
    else: cli('media.identity.get',{'path':url})
    with sqlite3.connect(next_db) as db:
        count=db.execute('SELECT COUNT(DISTINCT file_id) FROM media_locations WHERE owner_device_id=? AND locator=?',(owner,url)).fetchone()[0]
        alias=db.execute('SELECT file_id,archived FROM media_file_aliases WHERE old_id=?',('x32-legacy-duplicate',)).fetchone()
        record('migration readback',{'version':db.execute('PRAGMA user_version').fetchone()[0],'distinctFiles':count,'aliasResolves':alias[0]==file_id,'archivePreserved':json.loads(alias[1])['entity']['attributes'].find('legacyNote')>=0,
            'legacyEvidenceCount':db.execute('SELECT COUNT(*) FROM media_legacy_history WHERE location_id=?',('x32-legacy-location',)).fetchone()[0],
            'editValue':db.execute('SELECT value FROM media_overrides WHERE entity_id=? AND field=?',(file_id,'overview')).fetchone()[0],
            'foreignKeyErrors':db.execute('PRAGMA foreign_key_check').fetchall()})
        assert count==1
    cli('media.sources.check',{'sourceId':source})
    cli('media.sources.play',{'sourceId':source,'itemId':entry['id'],'startPositionMs':2000})
    time.sleep(.7)
    state=cli('playback.state',{})
    capture('shared-playing')
    assert state.get('state',state).get('path') or state.get('state',state).get('hasVideo')
    cli('playback.close',{})
    cli('media.library.import_history',{})
    with sqlite3.connect(next_db) as db:
        record('repeat merge readback',{'distinctFiles':db.execute('SELECT COUNT(DISTINCT file_id) FROM media_locations WHERE owner_device_id=? AND locator=?',(owner,url)).fetchone()[0],
            'aliases':db.execute('SELECT COUNT(*) FROM media_file_aliases').fetchone()[0]})
    cli('state.query',{'view':'activity','limit':20})
    record('complete',{'home':not shared_only,'danmaku':not shared_only,'watched':not shared_only,'nextPreference':not shared_only,'sharedPlayback':True})
finally:
    for proc,log in processes:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=30)
        log.close()
    for p in profiles.values():shutil.rmtree(p['root'])
    record('cleanup',{'pids':[p.pid for p,_ in processes],'processesExited':all(p.poll() is not None for p,_ in processes),
        'profilesRemoved':all(not p['root'].exists() for p in profiles.values())})
