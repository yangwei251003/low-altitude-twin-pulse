"""One bounded Dev94 presentation check in an isolated profile/owned Job."""
from datetime import datetime
import json
import secrets
import dev

stamp=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)
label='front94-'+stamp
dev.POLICY.preflight('evidence',16*1024**2)
folder=dev.POLICY.path('evidence',label)
folder.mkdir()
output=folder/'result.json'
print('FRONT94_REPORT',output,flush=True)
run=dev.execute(['--script','res://scripts_tools/v3/acceptance_front94.gd','--','--qa-profile=qa_front94_'+stamp,'--output='+str(output)],label,timeout=180)
report=json.loads(output.read_text(encoding='utf-8')) if output.exists() else {}
print(json.dumps({'run':run,'report':str(output),'passed':report.get('passed',False)},ensure_ascii=False),flush=True)
raise SystemExit(0 if run.get('passed',False) and report.get('passed',False) else 1)
