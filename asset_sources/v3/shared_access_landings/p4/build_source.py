"""Editable fixed landings, source previews only. CPU2; launcher owns 240s timeout."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import bpy
from mathutils import Vector
from geometry import build_parts,source_layout,audit,ORIGIN,ROOT,LAYOUT_SHA,MATERIALS,FLOOR_IDS
from materials import create_materials,audit_materials
from normal_tile import bake_tread_tile


def bp(p):return (p[0],-p[2],p[1])
def gp(p):return (p[0],p[2],-p[1])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def empty(name,parent,col):
    o=bpy.data.objects.new(name,None);col.objects.link(o);o.parent=parent
    o.empty_display_type='PLAIN_AXES';o.empty_display_size=.2
    return o


def make_mesh(p,parent,col,mats):
    mesh=bpy.data.meshes.new(p.name+'_EditableMesh')
    mesh.from_pydata([bp(tuple(v[i]-p.center[i] for i in range(3))) for v in p.vertices],[],p.faces)
    mesh.update()
    if mesh.validate(verbose=True):raise RuntimeError('unexpected repaired input '+p.name)
    obj=bpy.data.objects.new(p.name,mesh);col.objects.link(obj);obj.parent=parent;obj.location=bp(p.center)
    names=[m for m in MATERIALS if m in p.face_materials]
    for name in names:mesh.materials.append(mats[name])
    for poly,name in zip(mesh.polygons,p.face_materials):poly.material_index=names.index(name)
    for name in ('SurfaceUV','SourceXZ','SourceY','PaintPanelUV','TreadUV','PlateMetres','PlateSize'):mesh.uv_layers.new(name=name)
    mesh.color_attributes.new(name='WeatherUse',type='FLOAT_COLOR',domain='CORNER')
    # Allocate all layers first, then reacquire RNA handles (Blender 5.2 safety).
    surface=mesh.uv_layers['SurfaceUV'];xz=mesh.uv_layers['SourceXZ']
    yy=mesh.uv_layers['SourceY'];paint=mesh.uv_layers['PaintPanelUV'];role=mesh.color_attributes['WeatherUse']
    tread=mesh.uv_layers['TreadUV'];plate_uv=mesh.uv_layers['PlateMetres'];plate_size=mesh.uv_layers['PlateSize']
    plate_bounds={}
    for q in p.pieces:
        if q['name'].startswith('walking_plate_'):
            points=p.vertices[q['vertex_start']:q['vertex_start']+q['vertex_count']]
            bounds=([min(v[i] for v in points) for i in (0,2)],[max(v[i] for v in points) for i in (0,2)])
            for fi in range(q['face_start'],q['face_start']+q['face_count']):plate_bounds[fi]=bounds
    walking_faces={i for q in p.pieces if q['name'].startswith('walking_plate_') for i in range(q['face_start'],q['face_start']+q['face_count'])}
    along_axis=0 if p.group in ('SouthBypass','SouthOuterRail') else 2
    cross_axis=2 if along_axis==0 else 0
    minimum=p.center[along_axis]-p.size[along_axis]/2
    for face in mesh.polygons:
        normal=gp(face.normal);dominant=max(range(3),key=lambda i:abs(normal[i]))
        axes=((2,1),(0,2),(0,1))[dominant]
        material=p.face_materials[face.index]
        for li in face.loop_indices:
            v=p.vertices[mesh.loops[li].vertex_index]
            surface.data[li].uv=(v[axes[0]],v[axes[1]])
            # Semantic metre coordinates: walking line follows this region,
            # not object Generated bounds; no scale-dependent weather patches.
            xz.data[li].uv=(v[along_axis],v[cross_axis]-p.center[cross_axis])
            yy.data[li].uv=(v[1],0)
            tread.data[li].uv=(v[0]/.38,v[2]/.38)
            if face.index in plate_bounds:
                lo,hi=plate_bounds[face.index];plate_uv.data[li].uv=(v[0]-lo[0],v[2]-lo[1]);plate_size.data[li].uv=(hi[0]-lo[0],hi[1]-lo[1])
            else:plate_uv.data[li].uv=(.5,.5);plate_size.data[li].uv=(1,1)
            top=face.index in walking_faces and normal[1]>.7
            role.data[li].color=(float(material=='IB_BlueSteel'),float(top),0,0)
            if p.group not in FLOOR_IDS:
                if dominant==cross_axis:
                    u=(v[along_axis]-minimum)/6
                    paint.data[li].uv=(u,v[1])
                else:
                    # End caps / top hems use a real metric intact-paint crop;
                    # no degenerate length-axis projection on the short ends.
                    a,b=axes
                    paint.data[li].uv=(.40+(v[a]-p.center[a])/6,.72+(v[b]-p.center[b])*.12)
            else:
                # Keep lower box edge coating quiet; 6m U scale is unchanged.
                a=along_axis if dominant!=along_axis else cross_axis
                paint.data[li].uv=(.05+(v[a]-p.center[a]+p.size[a]/2)/6,.60+(v[1]+.4)*.30)
    mesh.uv_layers.active_index=0
    for uv in mesh.uv_layers:uv.active_render=uv.name=='SurfaceUV'
    attr=mesh.attributes.new(name='construction_piece',type='INT',domain='FACE')
    selected=set()
    for index,piece in enumerate(p.pieces):
        for fi in range(piece['face_start'],piece['face_start']+piece['face_count']):
            attr.data[fi].value=index
            mesh.polygons[fi].use_smooth=piece['smooth_sides'] and len(mesh.polygons[fi].vertices)==4
        if piece['name'] in ('structural_slab','continuous_folded_guard'):
            selected.update(range(piece['vertex_start'],piece['vertex_start']+piece['vertex_count']))
    normals={}
    for face in mesh.polygons:
        for key in face.edge_keys:normals.setdefault(tuple(sorted(key)),[]).append(face.normal.copy())
    weights=mesh.attributes.new(name='bevel_weight_edge',type='FLOAT',domain='EDGE')
    for edge in mesh.edges:
        ns=normals.get(tuple(sorted(edge.vertices)),[])
        eligible=all(i in selected for i in edge.vertices) and len(ns)==2 and ns[0].dot(ns[1])<math.cos(.70)
        weights.data[edge.index].value=float(eligible)
    bevel=obj.modifiers.new('EditableRestrainedEdge','BEVEL');bevel.width=.0015;bevel.segments=1
    bevel.limit_method='WEIGHT';bevel.edge_weight='bevel_weight_edge';bevel.use_clamp_overlap=True;bevel.harden_normals=True
    normal=obj.modifiers.new('EditableWeightedNormals','WEIGHTED_NORMAL');normal.keep_sharp=True
    obj['source_body_id']=p.group;obj['module_center_local_godot']=list(p.center);obj['module_size_xyz']=list(p.size)
    obj['construction_piece_names']=json.dumps([q['name'] for q in p.pieces])
    obj['scope']='fixed visual source; no production collision or targets changed'
    return obj


def measured(objects,parts):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();rows=[]
    for obj,p in zip(objects,parts):
        eo=obj.evaluated_get(deps);m=eo.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
        try:
            m.calc_loop_triangles();coords=[gp(eo.matrix_world@v.co) for v in m.vertices]
            lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)]
            excess=max([p.center[i]-p.size[i]/2-lo[i] for i in range(3)]+[hi[i]-p.center[i]-p.size[i]/2 for i in range(3)]+[0])
            assert excess<3e-6,(obj.name,'evaluated envelope drift',excess)
            assert [u.name for u in m.uv_layers]==['SurfaceUV','SourceXZ','SourceY','PaintPanelUV','TreadUV','PlateMetres','PlateSize']
            assert [u.name for u in m.uv_layers if u.active_render]==['SurfaceUV']
            assert 'WeatherUse' in m.color_attributes and m.color_attributes['WeatherUse'].domain=='CORNER'
            assert all(math.isfinite(v) for layer in m.uv_layers for loop in layer.data for v in loop.uv)
            rows.append({'name':obj.name,'parent':obj.parent.name,'triangles':len(m.loop_triangles),
                         'materials':[q.name for q in m.materials],'bounds_min_local_godot':lo,'bounds_max_local_godot':hi,
                         'node_center_local_godot':list(gp(obj.location)),'node_scale':list(obj.scale),
                         'uv_layers':[u.name for u in m.uv_layers],'max_overshoot_m':excess})
        finally:eo.to_mesh_clear()
    return {'mesh_count':len(rows),'triangles':sum(r['triangles'] for r in rows),
            'materials':sorted({q for r in rows for q in r['materials']}),'material_surfaces':sum(len(r['materials']) for r in rows),
            'parts':rows,'limits':'Per-source-body bounds and layers; not a Boolean-union or runtime sweep result.'}


def studio(scene,col):
    w=bpy.data.worlds.new('STUDIO_NeutralWorld');w.use_nodes=True;scene.world=w
    w.node_tree.nodes['Background'].inputs['Color'].default_value=(.32,.34,.35,1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
    mesh=bpy.data.meshes.new('STUDIO_FloorMesh')
    mesh.from_pydata([(-100,-100,-.42),(100,-100,-.42),(100,100,-.42),(-100,100,-.42)],[],[(0,1,2,3)])
    floor=bpy.data.objects.new('STUDIO_Floor',mesh);col.objects.link(floor)
    mat=bpy.data.materials.new('STUDIO_FloorMaterial');mat.use_nodes=True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.24,.25,.26,1)
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.8;mesh.materials.append(mat)
    for name,pos,power,size in [('Key',(0,13,-4),2300,10),('Fill',(-9,8,6),1700,10),('Rim',(8,12,17),2700,9)]:
        light=bpy.data.lights.new('STUDIO_'+name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        ob=bpy.data.objects.new('STUDIO_'+name,light);col.objects.link(ob);ob.location=bp(pos)
        ob.rotation_euler=(Vector(bp((0,0,6)))-ob.location).to_track_quat('-Z','Y').to_euler()
    cam=bpy.data.objects.new('STUDIO_Camera',bpy.data.cameras.new('STUDIO_Camera'));col.objects.link(cam)
    cam.data.type='ORTHO';cam.data.clip_start=.01;cam.data.clip_end=300;scene.camera=cam
    return cam


def main():
    started=time.monotonic();ap=argparse.ArgumentParser()
    ap.add_argument('--render',action='store_true');ap.add_argument('--output',default='source_review_01')
    ap.add_argument('--samples',type=int,default=12)
    opts=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    assert opts.output.replace('_','').replace('-','').isalnum() and 4<=opts.samples<=20
    out=HERE/opts.output
    assert not out.exists(),'refuse overwrite of source evidence'
    layout=source_layout();parts=build_parts(layout);pure=audit(parts,layout);assert pure['failed']==0
    inputs=[HERE/'geometry.py',HERE/'materials.py',HERE/'finish_layout.json',HERE/'normal_tile.py',Path(__file__),
            HERE/'source_inputs/painted_steel_material_v1_UNEDITED.png',HERE/'source_inputs/LandingTread_Normal_P3.png',
            ROOT/'data/v3/terrain/i2_shared_access_layout.json',
            ROOT/'references/v3/production/shared_access_landings/shared_access_landing_v1.png']
    before={str(p.relative_to(ROOT)).replace('\\','/'):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in inputs}
    out.mkdir();bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    assets=bpy.data.collections.new('ASSET_SharedAccessLandings');scene.collection.children.link(assets)
    review=bpy.data.collections.new('STUDIO_ReviewOnly');scene.collection.children.link(review)
    root=empty('SharedAccessLandings',None,assets);root['world_origin_godot']=list(ORIGIN)
    root['layout_raw_sha256']=LAYOUT_SHA;root['stage']='editable_source_not_runtime'
    parents={k:empty(k,root,assets) for k in dict.fromkeys(p.group for p in parts)}
    normal_image,surface_mask,normal_report=bake_tread_tile(scene,out)
    mats=create_materials(normal_image,surface_mask);materials=audit_materials(mats)
    objects=[make_mesh(p,parents[p.group],assets,mats) for p in parts];evaluated=measured(objects,parts)
    cam=studio(scene,review)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=opts.samples;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1400;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB'
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=.45
    views=[('01-east-4m-module',(0.0,4.5,-5.5),(4.7,.22,.3),7.5,['EastLanding_01','EastOuterRail_01'])]
    cameras=[]
    # Save the complete editable assembly; hero render's isolation is explicit.
    cam.location=bp((24,21,-18));cam.rotation_euler=(Vector(bp((0,.1,6.4)))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=26
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'shared_access_landings_p4.blend'))
    for name,eye,target,scale,visible in views:
        for ob in objects:ob.hide_render=visible is not None and ob.name not in visible
        cam.location=bp(eye);cam.rotation_euler=(Vector(bp(target))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
        cameras.append({'name':name,'eye_local_godot':eye,'target_local_godot':target,'ortho_scale':scale,
                        'visible_module_filter':visible,'production_screenshot':False})
        if opts.render:
            scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
    for ob in objects:ob.hide_render=False
    unchanged=all(sha(ROOT/k)==v['sha256'] for k,v in before.items());assert unchanged
    report={'stage':'source_preview_only','rendered':opts.render,'blender_version':bpy.app.version_string,
            'threads':2,'samples':opts.samples,'seconds':time.monotonic()-started,'inputs':before,'inputs_unchanged':unchanged,
            'pure_geometry':pure,'evaluated_geometry':evaluated,'material_audit':materials,'cameras':cameras,
            'baked_surface_mask_and_preserved_normal':normal_report,
            'runtime_exported':False,'godot_executed':False,'image_original_pixels_unchanged':True,
            'outputs':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in out.iterdir() if p.is_file()}}
    (out/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('FIXED_LANDING_SOURCE '+json.dumps({'meshes':evaluated['mesh_count'],'triangles':evaluated['triangles'],
                                           'checks':pure['check_count'],'seconds':report['seconds'],'output':str(out)}),flush=True)


if __name__=='__main__':main()
