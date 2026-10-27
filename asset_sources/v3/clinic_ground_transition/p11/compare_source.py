"""Prepared only. Load frozen P10 source; change three stones, render A/B/C.
No mesh reconstruction, no bake, no GLB. Requires a granted CPU2 window.
"""
from pathlib import Path
import sys,json,hashlib,struct,time,math,os
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
import bpy
from mathutils import Vector
import stone_material as M
SOURCE=HERE.parent/'p10/repair_01/editable_source.blend'
FROZEN=HERE.parent/'p10/repair_01'
OUT=HERE/'source_review_01'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

def signature(obj):
    data=bytearray()
    for vertex in obj.data.vertices:data.extend(struct.pack('<3f',*vertex.co))
    for face in obj.data.polygons:
        data.extend(struct.pack('<I',len(face.vertices)))
        data.extend(struct.pack('<'+'I'*len(face.vertices),*face.vertices))
    return hashlib.sha256(data).hexdigest()

def scene_geometry(objects):
    result={}
    for ob in objects:
        ob.data.calc_loop_triangles()
        result[ob.name]={'geometry_sha256':signature(ob),'triangles':len(ob.data.loop_triangles),
                        'matrix_world':[[float(v) for v in row] for row in ob.matrix_world]}
    return result

def main():
    start=time.time();assert not OUT.exists(),'Preserve old source-review output'
    intake=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))
    project=HERE.parents[3]
    for row in intake['files']:
        p=project/row['path'];assert p.exists() and sha(p)==row['sha256'],str(p)
    OUT.mkdir();bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    objects=[ob for ob in bpy.data.objects if ob.type=='MESH' and ob.get('editable_piece',False)]
    assert len(objects)==144
    baseline=scene_geometry(objects);assert sum(r['triangles'] for r in baseline.values())==7456
    expected=json.loads((FROZEN/'minimal_repair.json').read_text(encoding='utf-8'))['geometry_signatures']
    assert all(row['geometry_sha256']==expected[name] for name,row in baseline.items())
    chosen=[bpy.data.objects[name] for name in M.PATCHES]
    assert all(ob.data.users==1 for ob in chosen)
    original_materials={ob.name:[m.name for m in ob.data.materials] for ob in objects}
    images=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        path=Path(bpy.path.abspath(im.filepath));assert path.exists(),str(path)
        im.reload();pixel=list(im.pixels[:4]);assert im.has_data and len(pixel)==4
        images.append({'name':im.name,'path':str(path),'sha256':sha(path),'size':list(im.size),'colorspace':im.colorspace_settings.name,'first_pixel':pixel})
    write('image_readback.json',images)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU'
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.samples=24
    # One fixed detail camera for all cases. P10 orientation/light/exposure stay.
    coords=[ob.matrix_world@v.co for ob in chosen for v in ob.data.vertices]
    center=Vector(tuple((min(v[i] for v in coords)+max(v[i] for v in coords))*.5 for i in range(3)))
    direction=scene.camera.rotation_euler.to_matrix()@Vector((0,0,-1))
    scene.camera.location=center-direction*8;scene.camera.data.ortho_scale=1.25
    scene.render.resolution_x=1440;scene.render.resolution_y=860;scene.render.resolution_percentage=100
    cam={'location':list(scene.camera.location),'rotation':list(scene.camera.rotation_euler),'ortho_scale_m':1.25,'detail_only_not_default_game_camera':True}
    write('baseline_geometry.json',baseline)
    renders=[]
    def render(name):
        assert scene_geometry(objects)==baseline,'Geometry or placement changed'
        assert {ob.name:[m.name for m in ob.data.materials] for ob in objects if ob.name not in M.PATCHES}=={n:m for n,m in original_materials.items() if n not in M.PATCHES}
        scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
        renders.append({'file':name+'.png','sha256':sha(OUT/(name+'.png'))})
        write('render_checkpoint.json',{'completed':renders,'geometry_unchanged':True})
    render('01_A_p10_flat')
    material=M.material()
    concrete=M.concrete_fragment_material(bpy.data.objects['ConcreteResidual_00'].data.materials[0]);uv=[]
    for ob in chosen:
        uv.append(M.assign_uv(ob));ob.data.materials.clear()
        ob.data.materials.append(concrete if ob.name.startswith('FallenConcreteFragment_') else material)
        for face in ob.data.polygons:face.material_index=0;face.use_smooth=False
    write('three_stone_uv.json',uv)
    render('02_B_scanned_flat')
    normals=[M.smooth_by_actual_angle(ob,50) for ob in chosen]
    write('three_stone_normals.json',normals)
    render('03_C_scanned_angle_smooth')
    # Store only the C editable study, with all three actual maps referenced.
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'three_stone_study.blend'),relative_remap=False)
    assert scene_geometry(objects)==baseline
    assert all(sha(project/row['path'])==row['sha256'] for row in intake['files'])
    write('study_report.json',{'status':'SOURCE_COMPARISON_PENDING_ART_REVIEW','pid':os.getpid(),'seconds':time.time()-start,
          'source_inputs_unchanged':True,'all_144_geometry_and_transforms_identical':True,'triangles':7456,
          'changed_objects':list(M.PATCHES),'camera':cam,'images':images,'uv':uv,'angle_shading':normals,'renders':renders,
          'baked':False,'glb_exported':False,'engine_tested':False,
          'limits':['Study applies to three stones only, not the whole module.','No silhouette, trench, stone count or collision change.','Source UV projection may show seams: judge actual images.','Normal from real source NormalGL; albedo is not interpreted as a deep geometric pit.']})
    print(json.dumps({'pid':os.getpid(),'stage':'complete','seconds':time.time()-start,'renders':renders}),flush=True)

if __name__=='__main__':main()
