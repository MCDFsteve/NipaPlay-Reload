"""Exercise the headless body; media are only enumerated/read, never modified."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--dart', type=Path, required=True)
parser.add_argument('--data', type=Path, required=True)
parser.add_argument('--media', type=Path, required=True)
parser.add_argument('--evidence', type=Path, required=True)
parser.add_argument('--label', required=True)
parser.add_argument('--connect', action='store_true')
parser.add_argument('--resume', action='store_true')
args = parser.parse_args()
source, data = args.source.resolve(), args.data.resolve()
env = dict(os.environ, NIPAPLAY_ENDPOINT_FILE=str(data / 'endpoint.json'))
for key in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
    env.pop(key, None)
os.environ['NIPAPLAY_ENDPOINT_FILE'] = env['NIPAPLAY_ENDPOINT_FILE']
command = [str(args.dart), '--packages=.dart_tool/package_config.json',
           'bin/nipaplay_headless.dart', '--data', str(data)]
process = None
evidence = json.loads(args.evidence.read_text(encoding='utf-8')) if args.resume else {
    'label': args.label, 'mediaReadOnly': True, 'conversations': False}
if args.resume:
    old_schedule = data / 'harness/hooks/schedules.json'
    if old_schedule.exists(): old_schedule.unlink()
host_log = args.evidence.with_suffix('.host.log')
try:
    if not args.connect:
        with host_log.open('w') as log:
            process = subprocess.Popen(command + ['--media-root', str(args.media)],
                cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
        evidence['spawnedPid'] = process.pid
        deadline = time.monotonic() + 30
        while not (data / 'endpoint.json').exists():
            if process.poll() is not None:
                raise RuntimeError('Host exited before endpoint creation: ' + host_log.read_text())
            if time.monotonic() > deadline:
                raise TimeoutError('Host startup exceeded 30 seconds')
            time.sleep(0.1)
    client = runpy.run_path(str(source / 'assets/next/harness/nipa'))['Client']()

    def call(action, values):
        result = client.call(action, values)
        if result.get('status') != 'completed':
            raise RuntimeError(json.dumps(result, ensure_ascii=False))
        return result['result']

    def wait_job(job_id):
        result = client.watch(job_id, 60)
        if result.get('status') != 'completed':
            raise RuntimeError(json.dumps(result))
        return result['result']['job']

    cli = subprocess.run([sys.executable, str(source / 'assets/next/harness/nipa'), 'status'],
        cwd=source, env=env, check=True, capture_output=True, text=True, encoding='utf-8')
    evidence['status'] = json.loads(cli.stdout)
    evidence['pythonNipa'] = True
    evidence['catalog'] = client.request('list', full=False)
    if not args.resume:
        scan = call('media.library.scan', {'root': str(args.media), 'requestId': args.label + '-scan'})['job']
        evidence['scan'] = wait_job(scan['jobId'])
        assert evidence['scan']['state'] == 'succeeded', evidence['scan']
        files = call('media.files.list', {'root': str(args.media)})['files']
        evidence['files'] = files
        ref = {'provider': 'bangumi', 'objectType': 'subject', 'externalId': '571784', 'scope': ''}
        record = call('media.metadata.get', {'ref': ref})['record']
        evidence['providerRecord'] = record
        episodes = {str(e['number']): e['ref'] for e in record['episodes']}
        bindings = []
        for file in files:
            number = re.search(r'\[(\d{2})(?:V\d+)?\]', Path(file['path']).name)
            assert number is not None, file['path']
            key = str(int(number.group(1)))
            assert key in episodes, key
            bindings.append({'kind': 'file', 'entityId': file['fileId'], 'workRef': ref,
                'episodeRefs': [episodes[key]], 'reason': 'X43: title and episode labels match the verified Bangumi catalogue',
                'evidence': [{'source': 'filename and Bangumi catalogue', 'detail': Path(file['path']).name}]})
        bound = call('media.identity.bind_batch', {'requestId': args.label + '-bind', 'entries': bindings})
        evidence['bindings'] = bound
        work_id = bound['entries'][0]['workId']
        evidence['library'] = call('media.library.works', {})
        evidence['uiFacts'] = call('media.metadata.ui_facts', {'workId': work_id})
    else:
        files = evidence['files']
        bound = evidence['bindings']
    fixture = data / 'downloads/x43-fixture'
    video = fixture / 'same-name.mp4'
    repository = data / 'harness'
    if 'fixtureScan' not in evidence:
        # Fixtures are created only under this host's isolated data directory.
        fixture = data / 'downloads/x43-fixture'
        fixture.mkdir(parents=True, exist_ok=True)
        video = fixture / 'same-name.mp4'
        xml = fixture / 'same-name.xml'
        video.write_bytes(b'X43 index-only fixture\n')
        xml.write_text('<i><chatserver>comment.bilibili.com</chatserver><chatid>4243</chatid>'
            '<d p="1,1,25,16777215,1700000000,0,x43,1">X43 same-name</d></i>', encoding='utf-8')
        repository = data / 'harness'
        hook = repository / 'hooks' / ('library.file_added.py' if os.name == 'nt' else 'library.file_added')
        hook.write_text('#!/usr/bin/env python3\nimport json,sys\n'
            'e=json.load(sys.stdin)\nprint(json.dumps({"event":e["event"],"observed":True}))\n')
        if os.name != 'nt': hook.chmod(0o755)
        followup = call('followup.register', {'when': {'event': 'library.file_added', 'objectId': str(video)},
            'instruction': 'X43 experiment: record the indexing event; no model turn is authorized.', 'title': 'X43 indexing'})
        evidence['followupRegistered'] = followup
        fixture_scan = call('media.library.scan', {'root': str(fixture), 'requestId': args.label + '-fixture'})['job']
        evidence['fixtureScan'] = wait_job(fixture_scan['jobId'])
    deadline = time.monotonic() + 10
    while True:
        tracks = call('danmaku.tracks', {'path': str(video)})
        if tracks.get('tracks'): break
        if time.monotonic() > deadline: raise TimeoutError('Same-name sidecar was not indexed')
        time.sleep(0.1)
    evidence['sameNameDanmaku'] = tracks
    hooks = call('task.list', {'type': 'harness.hook'})['jobs']
    if not any(j['state'] == 'succeeded' and j['title'] == '定时脚本 x43-tick' for j in hooks):
        tick = repository / 'hooks' / ('x43_tick.py' if os.name == 'nt' else 'x43_tick')
        tick.write_text('#!/usr/bin/env python3\nimport json,sys\n'
            'e=json.load(sys.stdin)\nprint(json.dumps({"event":e["event"],"tick":True}))\n')
        if os.name != 'nt': tick.chmod(0o755)
        schedule = repository / 'hooks/schedules.json'
        schedule.write_text(json.dumps([{'id': 'x43-tick', 'everySeconds': 1,
            'program': str(tick.relative_to(repository)).replace(os.sep, '/')}]))
        deadline = time.monotonic() + 15
        while True:
            hooks = call('task.list', {'type': 'harness.hook'})['jobs']
            if any(j['state'] == 'succeeded' and j['title'] == '定时脚本 x43-tick' for j in hooks):
                break
            if time.monotonic() > deadline: raise TimeoutError('Scheduled hook did not succeed: ' + json.dumps(hooks))
            time.sleep(0.2)
        schedule.unlink()
    evidence['hookTasks'] = hooks
    evidence['followups'] = call('followup.list', {})
    evidence['checks'] = {'scannedFiles': len(files), 'boundFiles': len(bound['entries']),
        'uiFactsRead': True, 'sameNameIndexed': True, 'scheduledHookSucceeded': True}
    print(json.dumps(evidence['checks'], ensure_ascii=False), flush=True)
finally:
    if process is not None:
        subprocess.run(command + ['--stop'], cwd=source, env=env, check=True)
        try:
            evidence['exitCode'] = process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            evidence['forcedStopPid'] = process.pid
        evidence['stoppedPid'] = process.pid
    args.evidence.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
