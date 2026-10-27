"""Blender 5.2 source builder; three source-review views, no GLB export.

Run only in an explicitly granted CPU2 window. The caller must enforce a wall
clock timeout (recommended 240 seconds); --render alone does not impose one.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

HERE=Path(__file__).resolve().parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE))

import bpy
from mathutils import Vector
from geometry import build_parts,load_layout,measure,MATERIALS,ORIGIN,LAYOUT_SHA
from materials import create_materials,audit_materials


def bp(p):
    return (p[0],-p[2],p[1])


def gp(p):
    return (p[0],p[2],-p[1])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def args():
    parser=argparse.ArgumentParser()
    parser.add_argument('--render',action='store_true')
    parser.add_argument('--output',default='source_review_01')
    parser.add_argument('--samples',type=int,default=16)
    result=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not result.output.replace('_','').replace('-','').isalnum():
        raise ValueError('output must be a single safe source subdirectory name')
    if not 4<=result.samples<=24:raise ValueError('source review samples must be 4..24')
    return result


def empty(name,parent,collection,position=(0,0,0)):
    obj=bpy.data.objects.new(name,None);collection.objects.link(obj)
    obj.parent=parent;obj.location=bp(position)
    obj.empty_display_type='PLAIN_AXES';obj.empty_display_size=.15
    return obj


def make_mesh(part,parent,collection,mats):
    mesh=bpy.data.meshes.new(part.name+'_EditableMesh')
    local_vertices=[bp(tuple(v[i]-part.center[i] for i in range(3))) for v in part.vertices]
    mesh.from_pydata(local_vertices,[],part.faces)
    mesh.update()
    if mesh.validate(verbose=True):raise RuntimeError('Blender repaired unexpected input mesh '+part.name)
    obj=bpy.data.objects.new(part.name,mesh);collection.objects.link(obj)
    obj.parent=parent;obj.location=bp(part.center)
    ordered=[m for m in MATERIALS if m in part.face_materials]
    for name in ordered:mesh.materials.append(mats[name])
    for face,name in zip(mesh.polygons,part.face_materials):face.material_index=ordered.index(name)
    # Explicit source projections. SurfaceUV remains the active preview UV;
    # source shaders name SourceXZ/SourceY and never use the implicit active map.
    uv=mesh.uv_layers.new(name='SurfaceUV')
    mesh.uv_layers.active_index=0;uv.active_render=True
    for face in mesh.polygons:
        normal=gp(face.normal)
        dominant=max(range(3),key=lambda i:abs(normal[i]))
        axes=((2,1),(0,2),(0,1))[dominant]
        for li in face.loop_indices:
            v=part.vertices[mesh.loops[li].vertex_index]
            uv.data[li].uv=(v[axes[0]],v[axes[1]])
    mesh.uv_layers.new(name='SourceXZ');mesh.uv_layers.new(name='SourceY')
    # Reacquire RNA handles after allocating layers, as in the pump bake pipeline.
    mesh.color_attributes.new(name='WeatherUse',type='FLOAT_COLOR',domain='CORNER')
    xz=mesh.uv_layers['SourceXZ'];height=mesh.uv_layers['SourceY']
    use=mesh.color_attributes['WeatherUse']
    for face in mesh.polygons:
        normal=gp(face.normal);material=part.face_materials[face.index]
        values=(float(material=='IB_BlueSteel'),
                float(material=='IB_DeckSteel' and normal[1]>.7),
                float(material=='IB_OchreGrip'),
                float(part.name in ('WestCarriage','EastCarriage')))
        for li in face.loop_indices:
            v=part.vertices[mesh.loops[li].vertex_index]
            xz.data[li].uv=(v[0],v[2]);height.data[li].uv=(v[1],0)
            use.data[li].color=values
    mesh.uv_layers.active_index=mesh.uv_layers.find('SurfaceUV')
    for layer in mesh.uv_layers:layer.active_render=layer.name=='SurfaceUV'
    attr=mesh.attributes.new(name='construction_piece',type='INT',domain='FACE')
    for index,piece in enumerate(part.pieces):
        first,count=piece['face_start'],piece['face_count']
        for fi in range(first,first+count):
            attr.data[fi].value=index
            face=mesh.polygons[fi]
            # Smooth curved side quads; planar caps remain flat.
            face.use_smooth=piece['smooth_sides'] and len(face.vertices)==4
    obj['construction_piece_names']=json.dumps([p['name'] for p in part.pieces])
    obj['source_body_id']=part.name
    obj['source_collision_size']=list(part.size)
    obj['source_local_center_godot']=list(part.center)
    obj['source_group']=part.group
    obj['collision_scope']='source visual only; production body not changed'
    # Do not bevel every 14mm bolt or wheel polygon. Select only structural edges.
    selected=set()
    for piece in part.pieces:
        if piece['name'] in ('continuous_structural_deck','continuous_folded_guard','longitudinal_bogie_frame','guide_frame_segment'):
            selected.update(range(piece['vertex_start'],piece['vertex_start']+piece['vertex_count']))
    by_edge={}
    for face in mesh.polygons:
        for key in face.edge_keys:by_edge.setdefault(tuple(sorted(key)),[]).append(face.normal.copy())
    weight=mesh.attributes.new(name='bevel_weight_edge',type='FLOAT',domain='EDGE')
    for edge in mesh.edges:
        key=tuple(sorted(edge.vertices));normals=by_edge.get(key,[])
        chosen=all(v in selected for v in edge.vertices) and len(normals)==2 and normals[0].dot(normals[1])<math.cos(.70)
        weight.data[edge.index].value=1.0 if chosen else 0.0
    bevel=obj.modifiers.new('EditableManufacturedEdge','BEVEL')
    bevel.width=.003 if part.name in ('BridgeDeck','NorthGuard','SouthGuard') else .0015
    bevel.segments=2
    bevel.limit_method='WEIGHT'
    bevel.edge_weight='bevel_weight_edge'
    bevel.use_clamp_overlap=True
    bevel.harden_normals=True
    normal=obj.modifiers.new('EditableWeightedNormals','WEIGHTED_NORMAL')
    normal.keep_sharp=True
    return obj


def measure_scene(objects):
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get();rows=[]
    for obj in objects:
        evaluated=obj.evaluated_get(deps);mesh=evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            coords=[gp(evaluated.matrix_world@v.co) for v in mesh.vertices]
            lo=[min(v[i] for v in coords) for i in range(3)]
            hi=[max(v[i] for v in coords) for i in range(3)]
            center=obj['source_local_center_godot'];size=obj['source_collision_size']
            overshoot=max([center[i]-size[i]/2-lo[i] for i in range(3)]+
                          [hi[i]-center[i]-size[i]/2 for i in range(3)]+[0])
            if overshoot>2e-6:raise RuntimeError('%s modifier left source envelope: %s'%(obj.name,overshoot))
            if ([u.name for u in mesh.uv_layers]!=['SurfaceUV','SourceXZ','SourceY'] or
                    [u.name for u in mesh.uv_layers if u.active_render]!=['SurfaceUV']):
                raise RuntimeError('ambiguous UV layer '+obj.name)
            if 'WeatherUse' not in mesh.color_attributes or mesh.color_attributes['WeatherUse'].domain!='CORNER':
                raise RuntimeError('lost causal material role '+obj.name)
            coordinate_error=0.
            for li,loop in enumerate(mesh.loops):
                p=gp(evaluated.matrix_world@mesh.vertices[loop.vertex_index].co)
                xz=mesh.uv_layers['SourceXZ'].data[li].uv
                source_y=mesh.uv_layers['SourceY'].data[li].uv.x
                # Bevel interpolation can differ from the displaced bevel by its
                # 3mm width, but source masks must remain in asset metre space.
                coordinate_error=max(coordinate_error,abs(p[0]-xz.x),abs(p[2]-xz.y),abs(p[1]-source_y))
            if coordinate_error>.006:raise RuntimeError('source coordinate mapping drift '+obj.name)
            uv_coords=[tuple(loop.uv) for loop in mesh.uv_layers[0].data]
            uv_min=[min(v[i] for v in uv_coords) for i in range(2)]
            uv_max=[max(v[i] for v in uv_coords) for i in range(2)]
            if obj.name=='BridgeDeck' and (uv_max[0]-uv_min[0]<5.9 or uv_max[1]-uv_min[1]<3.3):
                raise RuntimeError('deck source UV range collapsed')
            rows.append({'name':obj.name,'parent':obj.parent.name,'local_translation_godot':list(gp(obj.location)),
                         'local_rotation_blender':list(obj.rotation_euler),'local_scale':list(obj.scale),
                         'bounds_min_godot':lo,'bounds_max_godot':hi,'triangles':len(mesh.loop_triangles),
                         'surface_materials':[m.name for m in mesh.materials],
                         'uv_layers':[l.name for l in mesh.uv_layers],'uv_min':uv_min,'uv_max':uv_max,
                         'source_coordinate_max_delta_m':coordinate_error,
                         'weather_role_corner_attribute':True,
                         'max_overshoot_m':overshoot})
        finally:evaluated.to_mesh_clear()
    return {'mesh_count':len(rows),'triangles_evaluated':sum(x['triangles'] for x in rows),
            'material_count':len({m for row in rows for m in row['surface_materials']}),
            'material_surfaces':sum(len(row['surface_materials']) for row in rows),
            'bounds_min_godot':[min(r['bounds_min_godot'][i] for r in rows) for i in range(3)],
            'bounds_max_godot':[max(r['bounds_max_godot'][i] for r in rows) for i in range(3)],'parts':rows}


def create_studio(scene,collection):
    world=bpy.data.worlds.new('SourceReviewNeutralWorld');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.32,.34,.35,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.55
    scene.world=world
    # A removable studio floor below the full inserted pin, never a model node.
    mesh=bpy.data.meshes.new('StudioFloorMesh')
    mesh.from_pydata([(-200,-200,-1.35),(200,-200,-1.35),(200,200,-1.35),(-200,200,-1.35)],[],[(0,1,2,3)])
    floor=bpy.data.objects.new('STUDIO_Floor',mesh);collection.objects.link(floor)
    m=bpy.data.materials.new('STUDIO_Neutral');m.use_nodes=True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.26,.27,.28,1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.8
    floor.data.materials.append(m)
    for name,position,power,size in [('Key',(0,-4,7),1250,5.5),('Fill',(-5,-1,3),850,5),
                                     ('Rim',(3,4,5),1400,4),('UndersideFill',(1,1,-3),350,4)]:
        light=bpy.data.lights.new('STUDIO_'+name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        obj=bpy.data.objects.new('STUDIO_'+name,light);collection.objects.link(obj);obj.location=position
        obj.rotation_euler=(Vector((0,0,.1))-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('STUDIO_ReviewCamera');data.type='ORTHO';data.clip_start=.01;data.clip_end=400
    cam=bpy.data.objects.new('STUDIO_ReviewCamera',data);collection.objects.link(cam);scene.camera=cam
    return cam,floor


def main():
    started=time.monotonic();options=args()
    out=HERE/options.output
    if out.exists():raise RuntimeError('refusing to overwrite previous source evidence: '+str(out))
    layout=load_layout();parts=build_parts(layout);pure_report=measure(parts)
    root_path=HERE.parents[3]
    production=root_path/'data/v3/terrain/i2_shared_access_layout.json'
    reference=root_path/'references/v3/production/shared_access_bridge_deck/shared_access_bridge_deck_v2.png'
    if sha(production)!=LAYOUT_SHA:raise RuntimeError('production layout changed since p3 intake; re-read before modeling')
    if sha(reference)!='bc0086a0c348e5a214109f86596293df223c7ec19458ffe2bdb3a6eb02058cb4':
        raise RuntimeError('approved V2 input changed')
    inputs={str(p.relative_to(root_path)).replace('\\','/'):{'sha256':sha(p),'bytes':p.stat().st_size}
            for p in [production,reference,HERE/'geometry.py',HERE/'materials.py',Path(__file__),
                      HERE/'layout_intake.json',HERE/'finish_layout.json']}
    out.mkdir()
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    asset_collection=bpy.data.collections.new('ASSET_SharedBridgeDeck');scene.collection.children.link(asset_collection)
    studio_collection=bpy.data.collections.new('STUDIO_SourceReviewOnly');scene.collection.children.link(studio_collection)
    root=empty('SharedBridgeDeck',None,asset_collection)
    root['asset_origin_world_godot']=list(ORIGIN)
    root['layout_raw_sha256']=LAYOUT_SHA
    root['source_stage']='editable-source-review-not-production'
    moving=empty('MovingDeck',root,asset_collection)
    pin=empty('LockPin',root,asset_collection)
    pin['godot_translation_when_inserted']=[0,-.3,0]
    pin['rest_state']='retracted'
    mats=create_materials()
    material_audit=audit_materials(mats)
    objects=[make_mesh(p,pin if p.group=='pin_parts' else moving,asset_collection,mats) for p in parts]
    for name,parent,position in [('GroundOrigin',root,(0,0,0)),('ManualHandleAnchor',moving,(-2.5,1.1,-1.65)),
                                 ('LockGripAnchor',pin,(2.4,.475,-1.9)),('WestTrackAnchor',moving,(-2.83,-.76,0)),
                                 ('EastTrackAnchor',moving,(2.83,-.76,0))]:
        empty(name,parent,asset_collection,position)
    evaluated_report=measure_scene(objects)
    # Check inserted pose without moving/editing any individual mesh, then restore source rest state.
    pin.location=bp((0,-.3,0));bpy.context.view_layer.update()
    inserted_min=min(gp(obj.matrix_world@v.co)[1] for obj in objects if obj.parent==pin for v in obj.data.vertices)
    assert abs(inserted_min+1.0)<2e-6
    pin.location=(0,0,0);bpy.context.view_layer.update()
    cam,floor=create_studio(scene,studio_collection)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=options.samples
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1400;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB'
    scene.render.film_transparent=False
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=.45
    # One unchanged asset in three cameras; no exploded, duplicated or hidden functional pieces.
    views=[('01-oblique', (8.8,6.0,-9.5),(0,.18,-.15),8.7,True),
           ('02-bogies-underneath',(7.5,-2.8,-6.8),(0,-.38,-.05),8.4,False),
           ('03-lock-closeup',(4.2,1.35,-4.5),(2.4,-.03,-1.83),2.25,True)]
    camera_records=[]
    for name,eye,target,scale,floor_visible in views:
        cam.location=bp(eye);cam.rotation_euler=(Vector(bp(target))-cam.location).to_track_quat('-Z','Y').to_euler()
        cam.data.ortho_scale=scale;floor.hide_render=not floor_visible
        camera_records.append({'name':name,'eye_godot':eye,'target_godot':target,'ortho_scale_m':scale,
                               'studio_floor_visible':floor_visible,'asset_geometry_unchanged':True})
        if name=='01-oblique':
            bpy.context.view_layer.objects.active=objects[0]
            bpy.ops.wm.save_as_mainfile(filepath=str(out/'shared_access_bridge_deck_p3.blend'))
        if options.render:
            scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
    inputs_unchanged=all(sha(root_path/path)==row['sha256'] for path,row in inputs.items())
    if not inputs_unchanged:raise RuntimeError('input bytes changed while source was built')
    output_files={p.name:{'sha256':sha(p),'bytes':p.stat().st_size} for p in out.iterdir() if p.is_file()}
    report={'status':'source-review-only','blender_version':bpy.app.version_string,'rendered':options.render,
            'runtime_glb_written':False,'godot_executed':False,'triangles_are_evaluated_not_drawcalls':True,
            'elapsed_seconds':time.monotonic()-started,'threads':2,'samples':options.samples,
            'source_inputs':inputs,'source_inputs_unchanged':inputs_unchanged,'outputs':output_files,
            'pure_geometry':pure_report,'evaluated_geometry':evaluated_report,
            'material_audit':material_audit,
            'p3_only_geometry_change':'Two 6mm bearing shoulders within BridgeDeck under the guard feet; all P2 vertices/faces retained.',
            'lock_inserted_min_godot_y':inserted_min,'cameras':camera_records,
            'limits':['Procedural source materials are not baked game textures.',
                      'No runtime collision or full travel sweep validation.',
                      'No final visual approval; root must inspect all three source images.',
                      'Construction-piece closure does not claim Boolean-union topology or no embedded fasteners.']}
    (out/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SHARED_BRIDGE_SOURCE_REVIEW '+json.dumps({'status':'completed','output':str(out),
           'mesh_count':evaluated_report['mesh_count'],'triangles':evaluated_report['triangles_evaluated'],
           'rendered':options.render,'seconds':report['elapsed_seconds']},ensure_ascii=False),flush=True)


if __name__=='__main__':main()
