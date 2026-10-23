"""一次性 S 线服务器；凭据只写 .dart_tool，绝不读取用户服务器。"""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import time
import urllib.request

workspace = Path(__file__).resolve().parents[4]
root = workspace / '.dart_tool/pc-sources-lab'
root.mkdir(parents=True, exist_ok=True, mode=0o700)
media = root / 'media' / 'Sintel Lab' / 'Season 01'
media.mkdir(parents=True, exist_ok=True)
source = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles/e2e42b/data/downloads/b924c09bfcf016a7fb96e3ff9b392d570e4f971b/Sintel.mp4'
for number in (1, 2):
    output = media / f'Sintel Lab S01E{number:02}.mkv'
    if not output.exists():
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-ss', str((number - 1) * 90),
            '-i', str(source), '-t', '90', '-map', '0:v:0', '-map', '0:a:0', '-map', '0:a:0',
            '-c', 'copy', '-metadata:s:a:0', 'title=Original A', '-metadata:s:a:1', 'title=Original B',
            str(output)], check=True)

docker = ['docker', '--context', 'colima-nipa-test']
fixtures = {}
for kind, port, image, prefix in [
    ('jellyfin', 28861, 'jellyfin/jellyfin:10.10.7', ''),
    ('emby', 28862, 'emby/embyserver:latest', '/emby'),
]:
    name = f'nipa-pcs-{kind}'
    config = root / kind
    config.mkdir(exist_ok=True)
    result = subprocess.run(docker + ['inspect', name], capture_output=True)
    if result.returncode:
        subprocess.run(docker + ['run', '-d', '--name', name,
            '-p', f'127.0.0.1:{port}:8096', '-v', f'{config}:/config',
            '-v', f'{root / "media"}:/media:ro', image],
            check=True, stdout=subprocess.DEVNULL)
    else:
        subprocess.run(docker + ['start', name], check=True, stdout=subprocess.DEVNULL)
    base = f'http://127.0.0.1:{port}'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    auth = 'MediaBrowser Client="NipaPlay S Lab", Device="S Lab", DeviceId="pc-sources", Version="1"'
    token = None

    def call(path, body=None, method=None):
        headers = {'Authorization': auth, 'Content-Type': 'application/json'}
        if token:
            headers['X-Emby-Token'] = token
        data = None if body is None else json.dumps(body).encode()
        with opener.open(urllib.request.Request(base + prefix + path,
                data=data, headers=headers, method=method), timeout=30) as response:
            value = response.read()
            return json.loads(value) if value else None

    for attempt in range(60):
        try:
            info = call('/System/Info/Public')
            break
        except OSError:
            time.sleep(1)
    else:
        raise RuntimeError(f'{kind} did not start')
    secret_file = config / 'session.json'
    if secret_file.exists():
        fixture = json.loads(secret_file.read_text())
        token = fixture['token']
    else:
        password = secrets.token_urlsafe(24)
        call('/Startup/Configuration', {'UICulture': 'en-US', 'MetadataCountryCode': 'US',
            'PreferredMetadataLanguage': 'en', 'ServerName': 'S disposable ' + kind})
        call('/Startup/User')
        call('/Startup/User', {'Name': 's-lab', 'Password': password})
        call('/Startup/RemoteAccess', {'EnableRemoteAccess': True, 'EnableAutomaticPortMapping': False})
        call('/Startup/Complete', {}, 'POST')
        session = call('/Users/AuthenticateByName', {'Username': 's-lab', 'Pw': password})
        token = session['AccessToken']
        fixture = {'baseUrl': base, 'username': 's-lab', 'password': password,
            'token': token, 'userId': session['User']['Id'], 'serverId': session['ServerId']}
        call('/Library/VirtualFolders?name=SintelLab&collectionType=tvshows&refreshLibrary=true',
            {'LibraryOptions': {'PathInfos': [{'Path': '/media'}],
                'EnableInternetProviders': False, 'EnableRealtimeMonitor': False,
                'EnableChapterImageExtraction': False}})
        secret_file.write_text(json.dumps(fixture))
        secret_file.chmod(0o600)
    for attempt in range(90):
        items = call(f'/Items?UserId={fixture["userId"]}&Recursive=true&IncludeItemTypes=Episode&Fields=MediaSources')['Items']
        if len(items) >= 2:
            break
        time.sleep(1)
    else:
        raise RuntimeError(f'{kind} did not index the fixtures')
    fixture['episodeIds'] = [item['Id'] for item in sorted(items, key=lambda item: item.get('IndexNumber', 0))]
    fixture['version'] = info['Version']
    fixtures[kind] = fixture
    print(json.dumps({'server': kind, 'version': info['Version'], 'episodes': len(items),
        'container': name}), flush=True)

password = secrets.token_urlsafe(18)
webdav = root / 'webdav.json'
webdav.write_text(json.dumps({'address': '0.0.0.0', 'port': 6065, 'directory': '/media',
    'permissions': 'R', 'users': [{'username': 's-lab', 'password': password}]}))
webdav.chmod(0o600)
for kind, args in [
    ('webdav', ['-p', '127.0.0.1:28863:6065', '-v', f'{webdav}:/config.json:ro',
        '-v', f'{root / "media"}:/media:ro', 'hacdias/webdav:latest', '-c', '/config.json']),
    ('smb', ['-p', '127.0.0.1:28864:445', '-v', f'{root / "media"}:/media:ro',
        'dperson/samba:latest', '-u', f's-lab;{password}', '-s', 'media;/media;yes;yes;no;s-lab']),
]:
    name = 'nipa-pcs-' + kind
    subprocess.run(docker + ['rm', '-f', name], capture_output=True)
    subprocess.run(docker + ['run', '-d', '--name', name] + args,
        check=True, stdout=subprocess.DEVNULL)
    fixtures[kind] = {'username': 's-lab', 'password': password,
        'url': 'http://127.0.0.1:28863' if kind == 'webdav' else None,
        'host': '127.0.0.1', 'port': 28864}
    print(json.dumps({'server': kind, 'container': name}), flush=True)
secret_file = root / 'fixtures.json'
secret_file.write_text(json.dumps(fixtures))
secret_file.chmod(0o600)
print('Fixture secrets saved under .dart_tool/pc-sources-lab (not evidence).', flush=True)
