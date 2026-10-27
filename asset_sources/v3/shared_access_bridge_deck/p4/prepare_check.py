"""Plain Python preparation; no bpy import or engine process."""
from pathlib import Path
import hashlib
import importlib.util
import json
import struct
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    checks=[]
    def check(name,value):
        checks.append({'name':name,'passed':bool(value)})
        assert value,name
    for p in HERE.glob('*.py'):compile(p.read_text(encoding='utf-8'),str(p),'exec')
    check('source Python compilation only',True)
    check('geometry source exactly frozen P3 including bearing shoulders',
          sha(HERE/'geometry.py')==sha(HERE.parent/'p3/geometry.py')=='6bc93dea3b77922808702957f5438ab74a587de180d5e906cfde4cdc26fcea99')
    spec=importlib.util.spec_from_file_location('p4_bridge_geometry',HERE/'geometry.py')
    geom=importlib.util.module_from_spec(spec);sys.modules[spec.name]=geom;spec.loader.exec_module(geom)
    report=geom.measure(geom.build_parts(geom.load_layout()))
    check('12 original parts and 9664 source triangles',report['mesh_count']==12 and report['triangles_before_bevel']==9664)
    check('current production layout equals intake',sha(ROOT/'data/v3/terrain/i2_shared_access_layout.json')==geom.LAYOUT_SHA)
    image=HERE/'source_inputs/painted_steel_material_v1_UNEDITED.png'
    ref=ROOT/'references/v3/production/shared_access_bridge_deck/painted_steel_material_v1.png'
    check('image remains exact original bytes',image.read_bytes()==ref.read_bytes() and sha(image)=='2ab3fdfab826eddf4736f92c34faeece79ff76278144a0430943a2924d6f50be')
    check('actual image 2172x724 not claimed 6 to 1',struct.unpack('>II',image.read_bytes()[16:24])==(2172,724))
    plan=json.loads((HERE/'finish_layout.json').read_text(encoding='utf-8'))
    check('P3 white ellipse and rivet ellipse input layers removed',not {'salt','rust_fasteners','edge_chips'}.intersection(plan))
    source=json.loads((HERE.parent/'p3/source_review_01/source_report.json').read_text(encoding='utf-8'))
    check('P3 source input hashes remain unchanged',all(sha(ROOT/p)==row['sha256'] for p,row in source['source_inputs'].items()))
    check('P3 output hashes remain unchanged',all(sha(HERE.parent/'p3/source_review_01'/p)==row['sha256'] for p,row in source['outputs'].items()))
    files={str(p.relative_to(HERE)).replace('\\','/'):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(HERE.rglob('*'))
           if p.is_file() and p.name not in {'static_validation.json','geometry_static_report.json'}}
    (HERE/'geometry_static_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    result={'scope':'Static Python / original bytes / mesh construction only, no engine.',
            'checks':checks,'check_count':len(checks),'passed':sum(c['passed'] for c in checks),
            'files':files,'runtime_glb_written':False,'baked':False,'blender_executed':False,'visual_status':'UNTESTED'}
    (HERE/'static_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'checks':len(checks),'passed':result['passed'],'geometry_sha256':sha(HERE/'geometry.py'),
                      'engines_started':0}))


if __name__=='__main__':main()
