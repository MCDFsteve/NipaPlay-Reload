"""One disposable Jellyfin, self-authored CC0 videos; never uses stored accounts."""
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import time
import urllib.request

root = pathlib.Path(tempfile.mkdtemp(prefix='x48-server-', dir=pathlib.Path.cwd()/'.dart_tool'))
os.chmod(root, 0o700)
media = root / 'media' / 'X48 Open Series' / 'Season 01'
media.mkdir(parents=True)
(root / 'config').mkdir()
(root / 'cache').mkdir()
(root / 'media' / 'LICENSE.txt').write_text('These X48 color test videos are authored for this experiment and dedicated to CC0 1.0.\n')
subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-f','lavfi','-i','color=c=blue:s=320x480',
                '-frames:v','1',str(media.parent/'poster.png')],check=True)
for episode, color in [(1, 'blue'), (2, 'green')]:
    subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i',
                    f'color=c={color}:s=320x180:r=24', '-t', '2', '-c:v', 'libx264',
                    str(media / f'X48 Open Series S01E{episode:02}.mkv')], check=True)
name = 'nipa-x48-jellyfin'
subprocess.run(['docker', '--context', 'colima-nipa-test', 'run', '-d', '--name', name,
                '-p', '127.0.0.1:28748:8096', '-v', f'{root}/config:/config',
                '-v', f'{root}/cache:/cache', '-v', f'{root}/media:/media:ro',
                'jellyfin/jellyfin:10.10.7'], check=True, stdout=subprocess.DEVNULL)
base = 'http://127.0.0.1:28748'
client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
auth = 'MediaBrowser Client="NipaPlay X48", Device="experiment", DeviceId="x48", Version="1"'
token = None
def call(path, body=None, method=None):
    headers = {'Authorization': auth, 'Content-Type': 'application/json'}
    if token:
        headers['X-Emby-Token'] = token
    data = None if body is None else json.dumps(body).encode()
    with client.open(urllib.request.Request(base+path, data=data, headers=headers, method=method), timeout=30) as response:
        data = response.read()
        return json.loads(data) if data else None
for _ in range(60):
    try:
        call('/System/Info/Public')
        break
    except (OSError, urllib.error.URLError):
        time.sleep(1)
else:
    raise RuntimeError('Temporary Jellyfin did not start')
password = secrets.token_urlsafe(24)
call('/Startup/Configuration', {'UICulture':'en-US','MetadataCountryCode':'US','PreferredMetadataLanguage':'en','ServerName':'X48 temporary'})
call('/Startup/User')
call('/Startup/User', {'Name':'x48','Password':password})
call('/Startup/RemoteAccess', {'EnableRemoteAccess':True,'EnableAutomaticPortMapping':False})
call('/Startup/Complete', {}, 'POST')
session = call('/Users/AuthenticateByName', {'Username':'x48','Pw':password})
token = session['AccessToken']
user = session['User']['Id']
call('/Library/VirtualFolders?name=X48%20CC0&collectionType=tvshows&refreshLibrary=true',
     {'LibraryOptions': {'PathInfos':[{'Path':'/media'}], 'EnableInternetProviders':False,
                        'EnableRealtimeMonitor':False, 'EnableChapterImageExtraction':False}})
for _ in range(90):
    items = call(f'/Items?userId={user}&Recursive=true&IncludeItemTypes=Episode')['Items']
    if len(items) == 2:
        break
    time.sleep(1)
else:
    raise RuntimeError('Temporary videos were not indexed')
views = call(f'/UserViews?userId={user}')['Items']
payload = {'root':str(root),'baseUrl':base,'token':token,'userId':user,'serverId':session['ServerId'],
           'libraryId':views[0]['Id'],'episodeIds':[i['Id'] for i in items]}
secret_file = root / 'session.json'
with os.fdopen(os.open(secret_file, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600),'w') as f:
    json.dump(payload,f)
print(json.dumps({'sessionFile':str(secret_file),'serverVersion':call('/System/Info/Public')['Version'],
                  'episodes':len(items),'videoLicense':'CC0-1.0','container':name}))
