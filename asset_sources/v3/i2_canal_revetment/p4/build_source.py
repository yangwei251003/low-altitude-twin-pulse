"""P4 static preparation: two real top channels + metric front texture return.
Run only in root's next serial CPU2 window. No baking, GLB or runtime writes.
"""
from pathlib import Path
import sys, os, time, json, hashlib, importlib.util, math
sys.dont_write_bytecode = True
import bpy, bmesh

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
P3 = HERE.parent / 'p3'
P2 = HERE.parent / 'p2'
SOURCE = P3 / 'i2_canal_revetment_p3.blend'
SOURCE_SHA = '91a4e2340b31d48c7071f140ee185d7a04149b2c053a9f52289d0b0374c9b29b'
OLD_SHA = '11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406'
FRONT_SHA = '32df77336c0abf940f7db69ee85e4f22f9eb64af22dc881d8c2e762b73861cba'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p, value): Path(p).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def exposed_uv(point, normal):
    """Godot local coordinates. One texel scale; return around front edges."""
    x, y, z = point
    if abs(x + 2.) < 1e-5 and normal.x < -.5:
        return ((-2.-z+2.)/4., (y+2.8)/2.8), 'left_end', 1.
    if abs(x - 2.) < 1e-5 and normal.x > .5:
        return ((2.+z+2.)/4., (y+2.8)/2.8), 'right_end', 1.
    if normal.y > .5 and y >= -.05:
        return ((x+2.)/4., (y+z+2.8)/2.8), 'top_return', 1.
    return ((x+2.)/4., (y+2.8)/2.8), 'front' if normal.z > .5 else 'hidden_or_recess_side', max(0., normal.z)

def assign_return_uv(body, support):
    me = body.data
    me.uv_layers.new(name='FrontFaceUV')
    me.attributes.new('ExposedSurface', 'FLOAT', 'CORNER')
    # Allocating either layer can invalidate previous RNA handles.
    uv = me.uv_layers['FrontFaceUV']
    exposure = me.attributes['ExposedSurface']
    metric = me.uv_layers['SurfaceMetric']
    metric.active_render = True
    me.uv_layers.active_index = me.uv_layers.find('SurfaceMetric')
    rows = {}
    for poly in me.polygons:
        normal = support.gp(poly.normal)
        for li in poly.loop_indices:
            point = support.gp(body.matrix_world @ me.vertices[me.loops[li].vertex_index].co)
            value, label, use = exposed_uv(point, normal)
            assert all(math.isfinite(c) and -1e-6 <= c <= 1.000001 for c in value)
            uv.data[li].uv = value
            exposure.data[li].value = use
            rows.setdefault(label, []).append(value)
    for name in ['Revetment_Concrete_0', 'Revetment_Concrete_1', 'Revetment_Concrete_2']:
        mat = bpy.data.materials[name]
        mixes = [n for n in mat.node_tree.nodes if n.type == 'MIX_RGB' and n.label == 'Front: new colour; side/back: frozen P2 source']
        assert len(mixes) == 1
        node = mixes[0].inputs[0].links[0].from_node
        assert node.type == 'ATTRIBUTE' and node.attribute_name == 'WaterFacing'
        node.attribute_name = 'ExposedSurface'
        mixes[0].label = 'P4 front/top/ends: same unedited image; hidden back: P2'
        bs = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        assert not bs.inputs['Normal'].is_linked and bs.inputs['Metallic'].default_value == 0.
        assert bs.inputs['Emission Strength'].default_value == 0.
    return {k: {'corner_count': len(v), 'min_uv': [min(t[i] for t in v) for i in range(2)], 'max_uv': [max(t[i] for t in v) for i in range(2)]} for k, v in rows.items()}

def ray(core, support, origin, direction):
    hit, p, normal, index = core.evaluated_get(bpy.context.evaluated_depsgraph_get()).ray_cast(support.bp(origin), support.bp(direction), distance=1.)
    assert hit, (origin, direction)
    return list(support.gp(p))

def patch_rays(core, support, shape):
    return [ray(core, support, (x,y,.02), (0,0,-1)) for x,y,w,h,a in shape.old.AGGREGATES]

def actual_top_channels(core, support, shape):
    rows = []
    for a, b in shape.SEAMS:
        x = (a+b)/2
        channel = ray(core, support, (x,.05,-.18), (0,-1,0))
        left = ray(core, support, (x-.03,.05,-.18), (0,-1,0))
        right = ray(core, support, (x+.03,.05,-.18), (0,-1,0))
        front = ray(core, support, (x,-.07,.02), (0,0,-1))
        assert abs(channel[1]+.014) < 1e-5 and abs(front[2]+.014) < 1e-5
        assert abs(left[1]) < 1e-6 and abs(right[1]) < 1e-6
        rows.append({'x_interval': [a,b], 'actual_top': channel, 'actual_left_lip': left, 'actual_right_lip': right, 'actual_upper_front_channel': front})
    return rows

def main():
    start = time.time()
    evidence = HERE/'evidence'; evidence.mkdir(exist_ok=True)
    final = HERE/'i2_canal_revetment_p4.blend'
    assert not final.exists() and sha(SOURCE) == SOURCE_SHA
    dump(HERE/'process.json', {'pid': os.getpid(), 'status': 'SOURCE_MATERIAL_RUNNING', 'threads': 2, 'source_only': True})
    print(json.dumps({'stage': 'start', 'pid': os.getpid(), 'threads': 2}), flush=True)
    support = load('p4_readonly_geometry_support', P2/'build_source.py')
    previous = load('p4_readonly_p3_support', P3/'build_source.py')
    shape = load('p4_top_channels', HERE/'shape_profile_v4.py')
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    parts = [o for o in bpy.data.objects if o.get('editable_piece', False)]
    assert len(parts) == 8
    core = bpy.data.objects['ConcreteBody_4m_Closed']
    unchanged = [o for o in parts if o != core]
    before = previous.geometry_digest(unchanged)
    repair_before = patch_rays(core, support, shape)
    for im in bpy.data.images:
        if im.source == 'FILE' and im.filepath:
            original = Path(bpy.path.abspath(im.filepath)).resolve()
            digest = sha(original)
            assert digest in (OLD_SHA, FRONT_SHA)
            new = HERE/'source_inputs'/original.name
            assert sha(new) == digest
            im.filepath = str(new.resolve())
    images = previous.audit_images('P4 before changes')
    mats = list(core.data.materials)
    verts, faces, indices = shape.body_mesh_data()
    mesh = bpy.data.meshes.new('P4_ClosedCore_TopConstructionChannels')
    mesh.from_pydata([support.bp(p) for p in verts], [], faces); mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    core.data = mesh
    # Keep original object's existing 8mm bevel modifier and transform.
    support.PARTS.clear()
    support.finish(core, mats, 0)
    for poly, index in zip(mesh.polygons, indices): poly.material_index = index
    uv = assign_return_uv(core, support)
    support.PARTS.clear(); support.PARTS.extend(parts)
    bpy.context.view_layer.update()
    after = previous.geometry_digest(unchanged); assert before == after
    repair_after = patch_rays(core, support, shape)
    repair_error = max(abs(a-b) for x,y in zip(repair_before,repair_after) for a,b in zip(x,y))
    assert repair_error < 1e-6, repair_error
    channels = actual_top_channels(core, support, shape)
    report = support.inspect(); assert report['passed']
    actual_geometry = previous.geometry_digest(parts)
    report.update(status='SOURCE_GEOMETRY_MATERIAL_PREPARED', source_only=True, no_bake_no_export=True,
                  p3_source_sha256=SOURCE_SHA, original_seven_other_parts_before=before,
                  original_seven_other_parts_after=after, repair_body_surface_max_error_m=repair_error,
                  actual_top_channels=channels, return_uv=uv, input_images=images,
                  geometry_after=actual_geometry, camera_lighting_unchanged=True)
    dump(evidence/'geometry_material_report.json', report)
    for im in bpy.data.images:
        if im.source == 'FILE' and im.filepath: im.filepath = str(Path(bpy.path.abspath(im.filepath)).resolve())
    previous.audit_images('P4 before checkpoint')
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'geometry_material_checkpoint.blend'), relative_remap=False)
    support.camera_view('reference')
    bpy.ops.wm.save_as_mainfile(filepath=str(final), relative_remap=False)
    for im in bpy.data.images:
        if im.source == 'FILE' and im.filepath: im.filepath = bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(final), relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(final))
    support.PARTS.clear(); support.PARTS.extend(o for o in bpy.data.objects if o.get('editable_piece',False))
    report['reopened_images'] = previous.audit_images('P4 reopened final')
    report['reopened_geometry'] = support.inspect(); assert report['reopened_geometry']['passed']
    report['geometry_reopened'] = previous.geometry_digest(support.PARTS)
    assert report['geometry_reopened'] == actual_geometry
    outputs = []
    for kind, name in [('reference','01-reference-oblique.png'),('scale26','02-isolated-26m-readability.png')]:
        view = support.camera_view(kind)
        bpy.context.scene.render.filepath = str(evidence/name)
        bpy.ops.render.render(write_still=True)
        outputs.append({'path': str(evidence/name), 'sha256': sha(evidence/name), 'camera': view})
    assert sha(SOURCE) == SOURCE_SHA
    report.update(status='RENDERED_REQUIRES_HUMAN_REVIEW', outputs=outputs,
                  blend_sha256=sha(final), elapsed_seconds=time.time()-start, p3_source_unchanged=True)
    dump(evidence/'geometry_material_report.json', report)
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':report['triangles']}), flush=True)

if __name__ == '__main__':
    try: main()
    except Exception as error:
        import traceback
        dump(HERE/'failure.json', {'type': type(error).__name__, 'message': str(error), 'traceback': traceback.format_exc()})
        try:
            for im in bpy.data.images:
                if im.source == 'FILE' and im.filepath: im.filepath = str(Path(bpy.path.abspath(im.filepath)).resolve())
            bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'failed_source.blend'), relative_remap=False)
        except Exception as snapshot_error: print('ERROR failure snapshot:', repr(snapshot_error), flush=True)
        raise
