"""Bounded Dev93 UI/lifecycle check, with a new isolated profile and owned Job."""
from datetime import datetime
import argparse
import json
import secrets
from pathlib import Path
import dev

parser=argparse.ArgumentParser()
parser.add_argument('--headless',action='store_true')
parser.add_argument('--scope',choices=['full','pages','connection'],default='full')
args=parser.parse_args()
stamp=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)
label='frontend93-'+stamp
dev.POLICY.preflight('evidence',20*1024**2)
folder=dev.POLICY.path('evidence',label)
folder.mkdir()
output=folder/'result.json'
engine_args=['--script','res://scripts_tools/v3/acceptance_frontend.gd','--','--qa-profile=qa_front93_'+stamp,'--output='+str(output),'--front-scope='+args.scope]
if args.headless: engine_args.insert(0,'--headless')
print('FRONTEND_REPORT',output,flush=True)
run=dev.execute(engine_args,label,timeout=300)
report=json.loads(output.read_text(encoding='utf-8')) if output.exists() else {}
print(json.dumps({'run':run,'report':str(output),'passed':report.get('passed',False)},ensure_ascii=False),flush=True)
raise SystemExit(0 if run.get('passed',False) and report.get('passed',False) else 1)
