"""Non-Blender plan/AST check. Does not prove generated mesh or appearance."""
from pathlib import Path
import ast, hashlib, json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
cfg = json.loads((HERE/'contract.json').read_text(encoding='utf-8'))
checks = []
def check(name, ok, details=None):
    checks.append({'name':name,'passed':bool(ok),'details':details})

for name in ('build_paving.py', 'run_preview.py', 'check_plan.py'):
    ast.parse((HERE/name).read_text(encoding='utf-8'), filename=name)
    check(name+' Python AST', True)
for rel, info in cfg['frozen_inputs'].items():
    p=ROOT/rel
    check('read-only source '+rel, p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256'])
rows=cfg['tiles']
check('eight unique exact centres, no scale or rotation', {tuple(r['center_xz']) for r in rows}=={(x,z) for x in (17,22) for z in (-12,-8,-4,0)} and len(rows)==8)
seams=[]
for a in rows:
    for b in rows:
        dx=b['center_xz'][0]-a['center_xz'][0]; dz=b['center_xz'][1]-a['center_xz'][1]
        sides=('east','west') if dx==5 and dz==0 else (('south','north') if dx==0 and dz==4 else None)
        if sides:
            modes=[a['edges'][sides[0]],b['edges'][sides[1]]]
            check(a['id']+' to '+b['id']+' paired half seams',modes==['pair_half','pair_half'],modes)
            seams.append([a['id'],b['id']])
check('ten internal shared edges',len(seams)==10)
full=0
for row in rows:
    x,z=row['center_xz']
    wanted={'west':x==17,'east':x==22,'north':z==-12,'south':z==0}
    for side, exterior in wanted.items():
        check(row['id']+' '+side+' exterior ownership',(row['edges'][side]=='outer_full')==exterior)
        full+=int(exterior)
check('twelve external segments with 20mm owned entirely inside module',full==12)
check('one west inspection spine, east route has none',[r['id'] for r in rows if r['inspection_band']]==['W0','W1','W2','W3'])
check('one entrance marker, never eight yellow frames',[r['id'] for r in rows if r['entry_mark']]==['E3'])
check('only two explicit repair and salt placements',sum(r['repair'] for r in rows)==2 and sum(r['local_salt'] for r in rows)==2)
check('conservative clearance to lowest real pipe .06m',cfg['y_bounds'][1]==0 and .06-cfg['y_bounds'][1]>=.06)
check('fixed world cover and uninterrupted east three metre strip',cfg['size_xz']==[5,4] and 24.5-21.5==3 and max(r['center_xz'][0]+2.47 for r in rows if r['inspection_band'])<21.5)
check('two deliberately different T rhythms',set(cfg['joint_patterns'])=={'A','B'} and len({(p['spine_x'],p['west_t_z'],p['east_t_z']) for p in cfg['joint_patterns'].values()})==2)
for a in rows:
    for b in rows:
        dx=b['center_xz'][0]-a['center_xz'][0]; dz=b['center_xz'][1]-a['center_xz'][1]
        pa=cfg['joint_patterns'][a['joint_pattern']]; pb=cfg['joint_patterns'][b['joint_pattern']]
        if dx==5 and dz==0:check(a['id']+'/'+b['id']+' horizontal T ends offset >=.3m',abs(pa['east_t_z']-pb['west_t_z'])>=.2999)
        if dx==0 and dz==4:check(a['id']+'/'+b['id']+' longitudinal spine offset >=.9m',abs(pa['spine_x']-pb['spine_x'])>=.9)
repairs=[]
for row in rows:
    if not row['repair_spec']:continue
    repair=row['repair_spec']; x0,x1,z0,z1=repair['rect']; pat=cfg['joint_patterns'][row['joint_pattern']]
    check(row['id']+' sawcut strictly inside NW bearing field',-2.48<x0<x1<pat['spine_x']-.02 and -1.98<z0<z1<pat['west_t_z']-.02)
    check(row['id']+' repair stays below original Y0',repair['top_y']==-.001)
    repairs.append({'tone':repair['tone'],'area':(x1-x0)*(z1-z0)})
check('two repair tones and materially different areas',{r['tone'] for r in repairs}=={'dark','light'} and max(r['area'] for r in repairs)>2*min(r['area'] for r in repairs),repairs)
check('candidate physical4m repeat, no colour-derived fake normal',cfg['candidate_basecolor']['coverage_m']==4 and 'neutral' in cfg['candidate_basecolor']['normal_policy'])
report={'status':'STATIC_PREPARED_NOT_BLENDER','checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'scope':'AST, frozen source bytes and proposed tile seam ownership only; no actual mesh, Blender API, render, physics or import evidence.'}
(HERE/'static_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':report['status'],'checks':len(checks),'failures':report['failed']}))
raise SystemExit(1 if report['failed'] else 0)
