"""Continue only this turn's known naturally earned assistant profile; never old QA chains."""
from datetime import datetime
import json,secrets
import dev
stamp=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)
label='assist94-journey-'+stamp
dev.POLICY.preflight('evidence',10*1024**2)
folder=dev.POLICY.path('evidence',label)
folder.mkdir()
output=folder/'result.json'
print('ASSIST94_JOURNEY_REPORT',output,flush=True)
run=dev.execute(['--script','res://scripts_tools/v3/observe_assist94_journey.gd','--','--qa-profile=qa_assist94_20261022_233052_57082e','--output='+str(output)],label,timeout=2450)
report=json.loads(output.read_text(encoding='utf-8')) if output.exists() else {}
print(json.dumps({'run':run,'report':str(output),'passed':report.get('passed',False)},ensure_ascii=False),flush=True)
raise SystemExit(0 if run.get('passed',False) and report.get('passed',False) else 1)
