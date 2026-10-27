"""Plain Python static preparation; does not import bpy or start an engine."""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def load_geometry(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module


def piece_data(part,piece):
    vs=piece['vertex_start'];ve=vs+piece['vertex_count']
    fs=piece['face_start'];fe=fs+piece['face_count']
    return {'vertices':part.vertices[vs:ve],
            'faces':[tuple(i-vs for i in face) for face in part.faces[fs:fe]],
            'materials':part.face_materials[fs:fe],
            'smooth_sides':piece['smooth_sides']}


def main():
    checks=[]
    def check(name,value):
        checks.append({'name':name,'passed':bool(value)})
        if not value:raise AssertionError(name)
    for path in HERE.glob('*.py'):compile(path.read_text(encoding='utf-8'),str(path),'exec')
    check('all source Python compiles without importing Blender',True)
    old=load_geometry(HERE.parent/'p2/geometry.py','bridge_p2_geometry')
    new=load_geometry(HERE/'geometry.py','bridge_p3_geometry')
    oldparts={p.name:p for p in old.build_parts(old.load_layout())}
    newparts={p.name:p for p in new.build_parts(new.load_layout())}
    check('same 12 part IDs',set(oldparts)==set(newparts) and len(newparts)==12)
    additions=[]
    for name,part in newparts.items():
        prior=oldparts[name]
        check(name+' original geometry and materials retained',
              all(piece_data(part,next(p for p in part.pieces if p['name']==q['name']))==piece_data(prior,q)
                  for q in prior.pieces) and (part.group,part.center,part.size)==(prior.group,prior.center,prior.size))
        oldnames={q['name'] for q in prior.pieces}
        additions.extend((name,q['name']) for q in part.pieces if q['name'] not in oldnames)
    expected=[('BridgeDeck','guard_bearing_shoulder_-1.65'),('BridgeDeck','guard_bearing_shoulder_1.65')]
    check('only two approved bearing shoulders added',sorted(additions)==sorted(expected))
    for _,piece_name in expected:
        part=newparts['BridgeDeck'];piece=next(q for q in part.pieces if q['name']==piece_name)
        vertices=piece_data(part,piece)['vertices'];lo=[min(p[i] for p in vertices) for i in range(3)]
        hi=[max(p[i] for p in vertices) for i in range(3)];zc=float(piece_name.rsplit('_',1)[1])
        check(piece_name+' full guard foot rests at Y0 on core top -.006',
              all(abs(a-b)<1e-12 for a,b in zip(lo,[-3,-.006,zc-.05])) and
              all(abs(a-b)<1e-12 for a,b in zip(hi,[3,0,zc+.05])))
    geometry=new.measure(list(newparts.values()))
    check('original global envelope retained',
          geometry['bounds_min']==old.measure(list(oldparts.values()))['bounds_min'] and
          geometry['bounds_max']==old.measure(list(oldparts.values()))['bounds_max'])
    plan=json.loads((HERE/'finish_layout.json').read_text(encoding='utf-8'))
    check('six selected runoff sources are actual existing bolts',all(
        row['x'] in [-2.965,-2,-1,0,1,2,2.965] and row['y'] in [.09,.91] and row['z'] in [-1.65,1.65]
        for row in plan['rust_fasteners']))
    for key in ['salt','edge_chips','grip_wear','deck_scuffs']:
        check(key+' finite authored metric volumes',all(
            len(row['c'])==3 and len(row['r'])==3 and all(math.isfinite(v) for v in row['c']+row['r']) and
            all(v>0 for v in row['r']) and 0<row['strength']<=1 for row in plan[key]))
    code=(HERE/'materials.py').read_text(encoding='utf-8')
    check('source shader does not construct object or world-coordinate nodes',not any(
        "node('"+kind+"'" in code for kind in ['ShaderNodeTexCoord','ShaderNodeNewGeometry','ShaderNodeObjectInfo']))
    check('current production layout matches intake',sha(ROOT/'data/v3/terrain/i2_shared_access_layout.json')==new.LAYOUT_SHA)
    check('approved V2 remains original bytes',sha(ROOT/'references/v3/production/shared_access_bridge_deck/shared_access_bridge_deck_v2.png')=='bc0086a0c348e5a214109f86596293df223c7ec19458ffe2bdb3a6eb02058cb4')
    check('P2 source remains frozen',all(sha(HERE.parent/'p2'/name)==digest for name,digest in {
        'geometry.py':'ec20ce3c10d413469e46acd6493258f86a98232f1f958fd083a1617836fa4a5a',
        'materials.py':'efffb550acaac612f2b5ed5d64872140a53f88bb4536daa1015d7cbd44ee8de5',
        'build_source.py':'9ab09b6d00bb4bf031b6bf10a20b4dcae8dc48427d759e750cb01b217e9025c7'}.items()))
    source_report=json.loads((HERE.parent/'p2/source_review_01/source_report.json').read_text(encoding='utf-8'))
    check('P2 rendered outputs remain frozen',all(sha(HERE.parent/'p2/source_review_01'/name)==row['sha256']
          for name,row in source_report['outputs'].items()))
    files={p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(HERE.iterdir())
           if p.suffix in {'.py','.json'} and p.name not in {'static_validation.json','geometry_static_report.json'}}
    (HERE/'geometry_static_report.json').write_text(json.dumps(geometry,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    report={'scope':'Plain Python compile/mesh data/causal mask input checks only; no Blender or GPU.',
            'check_count':len(checks),'checks':checks,'passed':sum(c['passed'] for c in checks),
            'geometry_additions':additions,'triangles_before_bevel':geometry['triangles_before_bevel'],
            'files':files,'blender_executed':False,'material_visual_result':'UNTESTED',
            'baked_pbr':False,'runtime_glb_written':False}
    (HERE/'static_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'checks':len(checks),'passed':report['passed'],'pre_bevel_triangles':geometry['triangles_before_bevel'],
                      'engines_started':0},ensure_ascii=False))


if __name__=='__main__':main()
