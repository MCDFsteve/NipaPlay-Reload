"""Read-only liveness samples for the corrected Agent run; no prompts/actions."""
import datetime,json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'scripts/next'))
from x23_vm import LabVM
evidence=Path(__file__).parent/'agent'; samples=[]
while True:
    operations=json.loads((evidence/'operations.json').read_text())
    lives=[x for x in operations if x['label']=='liveness']
    if lives: break
    time.sleep(1)
root=Path(lives[0]['value']['environment']['CODEX_HOME']).parent
while root.exists():
    try:
        state=LabVM(root/'app.log').chat('status')
        samples.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'model':state['header']['model'],'threadId':state['header']['threadId'],
            'liveness':state['liveness']})
    except (RuntimeError,OSError) as error:
        samples.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'errorType':type(error).__name__})
    (evidence/'liveness-samples.json').write_text(json.dumps(samples,ensure_ascii=False,indent=2))
    time.sleep(15)
