"""Read frozen recovery_sample; write only this independent diagnostic directory."""
from pathlib import Path
import hashlib, json, math, os, struct, sys
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = Path(os.environ['RECOVERY_V2_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CONTRACT = json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')

def check_inputs():
    for rel, row in CONTRACT['inputs'].items():
        p = ROOT/rel
        assert p.is_file() and p.stat().st_size == row['bytes'] and sha(p) == row['sha256'], rel

def open_source():
    check_inputs()
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/CONTRACT['preview_source']))
    rows=[]
    for im in bpy.data.images:
        if im.source != 'FILE': continue
        p=Path(bpy.path.abspath(im.filepath)).resolve()
        assert p.is_file(), (im.name, im.filepath)
        pixel=tuple(im.pixels[:4])
        assert im.has_data and pixel and all(math.isfinite(v) for v in pixel), im.name
        rows.append({'name':im.name, 'path':str(p), 'sha256':sha(p), 'size':list(im.size), 'space':im.colorspace_settings.name, 'first_pixel':pixel})
    write('image_preflight.json',rows)
    return bpy.context.scene

def mesh_digest(ob):
    """Actual positions/topology/smooth flags/UV data; excludes evaluated transient tangents."""
    me=ob.data; h=hashlib.sha256()
    for v in me.vertices: h.update(struct.pack('<3f',*v.co))
    for p in me.polygons:
        h.update(struct.pack('<II?',len(p.vertices),p.material_index,p.use_smooth))
        for i in p.vertices:h.update(struct.pack('<I',i))
    for layer in me.uv_layers:
        h.update(layer.name.encode('utf-8'))
        for d in layer.data:h.update(struct.pack('<2f',*d.uv))
    h.update(struct.pack('<16f',*(x for row in ob.matrix_world for x in row)))
    return h.hexdigest()

def fingerprints():
    return {o.name:mesh_digest(o) for o in bpy.data.objects if o.type=='MESH'}

def scene_lock(scene):
    return {'camera_matrix':[list(r) for r in scene.camera.matrix_world], 'camera_type':scene.camera.data.type,
        'ortho_scale':scene.camera.data.ortho_scale, 'resolution':[scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage],
        'samples':scene.cycles.samples,'view_transform':scene.view_settings.view_transform,'look':scene.view_settings.look,
        'exposure':scene.view_settings.exposure,'gamma':scene.view_settings.gamma,
        'lights':[{'name':o.name,'matrix':[list(r) for r in o.matrix_world],'energy':o.data.energy,'color':list(o.data.color),'size':o.data.size}
                  for o in bpy.data.objects if o.type=='LIGHT']}

def show_low():
    for o in bpy.data.objects:
        if o.type=='MESH' and o.get('study_part'):o.hide_render=o.name!='LowFull'

def angle(a,b):
    if a.length<1e-12 or b.length<1e-12:return None
    return math.degrees(math.acos(max(-1.,min(1.,a.normalized().dot(b.normalized())))))
