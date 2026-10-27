"""Read-only inputs and bounded candidate helpers; no implicit engine operation."""
from pathlib import Path
import hashlib, json, os, sys, time
sys.dont_write_bytecode = True
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
OUT = Path(os.environ['RECOVERY_BOUNDARY_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CONTRACT = json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def verify_inputs():
    rows = []
    for rel, expected in CONTRACT['inputs'].items():
        p = ROOT/rel; actual = {'bytes':p.stat().st_size, 'sha256':sha(p)}
        assert actual == expected, (rel, actual, expected)
        rows.append({'path':rel, **actual})
    return rows


def read(ob):
    me = ob.data
    assert not ob.modifiers and not me.shape_keys, ob.name
    me.calc_loop_triangles()
    co = np.asarray([tuple(v.co) for v in me.vertices], np.float64)
    vi = np.asarray([tuple(t.vertices) for t in me.loop_triangles], np.int32)
    li = np.asarray([tuple(t.loops) for t in me.loop_triangles], np.int32)
    return {'object':ob, 'mesh':me, 'co':co, 'vi':vi, 'li':li, 'tri':co[vi],
            'normals':np.asarray([tuple(n.vector) for n in me.corner_normals],np.float64)[li],
            'vertex_normals':np.asarray([tuple(v.normal) for v in me.vertices],np.float64),
            'uv':{u.name:np.asarray([tuple(x.uv) for x in u.data],np.float64)[li] for u in me.uv_layers},
            'materials':np.asarray([me.polygons[t.polygon_index].material_index for t in me.loop_triangles],np.int32),
            'smooth':np.asarray([me.polygons[t.polygon_index].use_smooth for t in me.loop_triangles],bool)}


def key(points): return tuple(sorted(tuple(float(v) for v in p) for p in points))


def labels(high, plan):
    lookup = {}
    for g in plan['groups']:
        data = read(bpy.data.objects[g['source']])
        for p in data['tri']:
            lookup.setdefault(key(p), set()).add(g['name'])
    result = []
    for p in high['tri']:
        found = lookup[key(p)]
        assert len(found) == 1, ('Ambiguous actual high identity', found)
        result.append(next(iter(found)))
    return result


def tree(data, ids=None):
    if ids is None:
        ids = np.arange(len(data['tri']),dtype=np.int32)
    points = data['tri'][ids].reshape((-1,3))
    return BVHTree.FromPolygons([Vector(p) for p in points], [(3*i,3*i+1,3*i+2) for i in range(len(ids))], all_triangles=True), ids


def bary2(p, tri):
    a,b,c = tri; e=b-a; f=c-a; q=p-a
    den=float(e[0]*f[1]-e[1]*f[0]); assert abs(den)>1e-16
    v=float(q[0]*f[1]-q[1]*f[0])/den
    w=float(e[0]*q[1]-e[1]*q[0])/den
    return np.asarray([1-v-w,v,w])


def bary3(p, tri):
    a,b,c=tri; n=np.cross(b-a,c-a); den=float(n@n); assert den>1e-28
    v=float(np.cross(p-a,c-a)@n)/den; w=float(np.cross(b-a,p-a)@n)/den
    return np.asarray([1-v-w,v,w])


def images_before_save():
    rows=[]
    for im in bpy.data.images:
        if im.source != 'FILE': continue
        p=Path(bpy.path.abspath(im.filepath)).resolve(); assert p.is_file(),(im.name,str(p))
        px=tuple(im.pixels[:4]); assert px and im.has_data and all(np.isfinite(px)),im.name
        rows.append({'image':im.name,'path':str(p),'sha256':sha(p),'size':list(im.size),'space':im.colorspace_settings.name})
        im.filepath=str(p) # Candidate memory only; original file bytes never saved.
    return rows
