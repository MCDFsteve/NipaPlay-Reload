"""Remove only X43 experiment data after checking the recorded PIDs exited."""
from pathlib import Path
import csv
import io
import json
import os
import shutil
import stat
import subprocess

windows = os.name == 'nt'
root = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
label = 'windows' if windows else 'wsl'
body = json.loads((root / f'x43-{label}.json').read_text(encoding='utf-8'))
final = json.loads((root / f'x43-{label}-final.json').read_text(encoding='utf-8'))
pids = [body['stoppedPid'], *[i['pid'] for i in final['iterations']]]
directories = [root / f'x43-{label}-data']
if windows:
    chat = json.loads((root / 'x43-windows-chat.json').read_text())
    pids.append(chat['probe'][-1]['closedPid'])
    pids.append(28228)  # The UTF-8 evidence reader failed after this host started; finally stopped it.
    directories.append(root / 'x43-chat-data')
for process_id in pids:
    if windows:
        output = subprocess.run(['tasklist', '/FI', f'PID eq {process_id}', '/FO', 'CSV', '/NH'],
            check=True, capture_output=True, text=True).stdout
        for row in csv.reader(io.StringIO(output)):
            if len(row) > 1 and row[1] == str(process_id):
                raise RuntimeError(f'Recorded PID {process_id} still exists; no cleanup performed.')
    else:
        try: os.kill(process_id, 0)
        except ProcessLookupError: pass
        else: raise RuntimeError(f'Recorded PID {process_id} still exists; no cleanup performed.')
def remove_readonly(function, path, error):
    if not windows or not isinstance(error, PermissionError): raise error
    os.chmod(path, stat.S_IWRITE)
    function(path)
for directory in directories:
    shutil.rmtree(directory, onexc=remove_readonly)
evidence = {'platform': label, 'exitedPids': pids,
    'removedDataDirectories': [str(d) for d in directories],
    'sourceAndLocalToolsRetained': True, 'persistentServiceCreated': False}
(root / f'x43-{label}-cleanup.json').write_text(json.dumps(evidence, indent=2))
print(json.dumps(evidence))
