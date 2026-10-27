"""Static-only input/contract checks. Does not import bpy or start Blender."""
from pathlib import Path
import ast, hashlib, json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
checks = []


def check(name, passed, detail=None):
    checks.append({'name': name, 'passed': bool(passed), 'detail': detail})


cfg = json.loads((HERE / 'contract.json').read_text(encoding='utf-8'))
for name in ('build_material_p3.py', 'run_preview.py', 'check_prepared.py'):
    ast.parse((HERE / name).read_text(encoding='utf-8'), filename=name)
    check(name + ' Python AST parses', True)
for path, expected in cfg['frozen_inputs'].items():
    actual = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    check(path + ' exact frozen bytes', actual == expected, actual)
check('P2 exact source selected', cfg['source_blend'].endswith('/p2/maintenance_paving_p2.blend') and cfg['source_sha256'] == cfg['frozen_inputs'][cfg['source_blend']])
check('root requested linear concrete adjustment', cfg['concrete']['linear_multiplier'] == .45 and cfg['concrete']['texture_weight'] == .72 and cfg['concrete']['quiet_linear_rgba'] == [.12, .13, .125, 1])
check('upper intact paint window excludes lower peeling', cfg['painted_steel']['uv_window'] == {'u': [.02, .98], 'v': [.60, .92]} and cfg['painted_steel']['image_rows_from_top'] == [.08, .40])
check('paint nonmetal, exposed steel distinct', cfg['painted_steel']['paint_metallic'] == 0 and cfg['painted_steel']['exposed_metallic'] == .65)
tree = ast.parse((HERE / 'build_material_p3.py').read_text(encoding='utf-8'))
calls = {ast.unparse(n.func) for n in ast.walk(tree) if isinstance(n, ast.Call)}
check('source entry does not build mesh, bake, export or replace review studio', not any(s in call for call in calls for s in ('ops.mesh.', 'ops.export_', 'ops.object.bake', 'P2.main', 'P2.build_variant', 'H.studio')))
check('source reopens saved candidate and compares signatures', 'geometry_signature' in calls and 'rig_state' in calls and 'bpy.ops.wm.open_mainfile' in calls)
source = (HERE / 'run_preview.py').read_text(encoding='utf-8')
check('wrapper bounded own process and no overwrite', "timeout=240" in source and "'/PID',str(process.pid),'/T','/F'" in source and "--python-exit-code" in source and 'not out.exists()' in source)
report = {'status': 'STATIC_ONLY_NOT_BLENDER_VALIDATED', 'checks': checks, 'checks_count': len(checks), 'failures': sum(not c['passed'] for c in checks)}
(HERE / 'static_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'checks': len(checks), 'failures': report['failures'], 'scope': report['status']}))
raise SystemExit(1 if report['failures'] else 0)
