"""Source-only V5: bounded joint repair and authored atlas placement.

Prepared only. Run in a root-approved CPU2 window with --python-exit-code 2.
blender.exe -b -t 2 --python-exit-code 2 --python this_file.py -- --render-pair
No Godot, GPU, GLB, bake, new furniture, layout change, or lower supports.
Frozen V4, the helper and original generated PNG are SHA-checked read-only inputs.
"""
from pathlib import Path
from datetime import datetime
import hashlib
import importlib.util
import itertools
import json
import math
import shutil
import sys

import bpy
from mathutils import Vector

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
INPUT=OUT.parent/'revision_v4/clinic_reception_v4.blend'
INPUT_SHA='e8b0cef2a237413aca67b37775ac57605c2048f5f89179f0828132fe8f243079'
HELPER=OUT.parent/'revision_v4/build_reception_v4.py'
HELPER_SHA='fb922eec11282e96da19de3e7cf673f799edac3f5cac283dab926b18dbe6af62'
ATLAS=ROOT/'references/v3/production/clinic_gravity/material_atlas_v4/clinic_gravity_basecolor_v4.png'
ATLAS_SHA='ada26062121fa77b22ca23a1d9738b684fe9b7490448e99702685b6a566bfd75'
EPS=1e-6
REGIONS={'post':(.5,0,.75,.5),'beam':(.75,0,1,.5),'steel':(.5,.5,.75,.75)}


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


assert sha(HELPER)==HELPER_SHA
spec=importlib.util.spec_from_file_location('frozen_reception_v4',HELPER)
V4=importlib.util.module_from_spec(spec);spec.loader.exec_module(V4)
H=V4.H
p,box,bounds,overlap=H.p,H.box,H.bounds,H.overlap


def geometry_digest(obj):
    return hashlib.sha256(json.dumps({'matrix':[list(row)for row in obj.matrix_world],'vertices':[list(v.co)for v in obj.data.vertices],'polygons':[list(face.vertices)for face in obj.data.polygons]},separators=(',',':')).encode()).hexdigest()


def replace_box(obj,lo,hi,material,bevel):
    name=obj.name;parent=obj.parent
    bpy.data.objects.remove(obj,do_unlink=True)
    new=box(name,lo,hi,material,bevel)
    if parent:
        transform=new.matrix_world.copy();new.parent=parent;new.matrix_world=transform
    return new


def plain(name,color,rough=.72,metal=0):
    material=H.mat(name,color,rough,metal)
    # An explicit constant socket lets the existing paint masks reuse real surfaces.
    nodes=material.node_tree.nodes;links=material.node_tree.links
    rgb=nodes.new('ShaderNodeRGB');rgb.outputs[0].default_value=(*color,1)
    links.new(rgb.outputs[0],nodes['ClinicPrincipled'].inputs['Base Color'])
    return material


def atlas_material(name,image,kind,rough,metal):
    material=plain(name,(.4,.4,.4),rough,metal)
    nodes=material.node_tree.nodes;links=material.node_tree.links
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    texture=nodes.new('ShaderNodeTexImage');texture.image=image;texture.extension='EXTEND'
    texture.label='Unedited native atlas; '+kind+' region only'
    links.new(uv.outputs['UV'],texture.inputs['Vector'])
    links.new(texture.outputs['Color'],nodes['ClinicPrincipled'].inputs['Base Color'])
    material['atlas_region']=kind
    material['pbr_limit']='BaseColor sRGB only; conservative constant roughness/metallic, no inferred normal map'
    return material


def assign(obj,material):
    obj.data.materials.clear();obj.data.materials.append(material)


def map_atlas(obj,kind):
    """Each real face spans its material region; edge wear follows member edges."""
    row=bounds(obj);size=[row['max'][i]-row['min'][i]for i in range(3)]
    longest=max(range(3),key=lambda i:size[i])
    uv=obj.data.uv_layers.get('SurfaceUV')
    if not uv:uv=obj.data.uv_layers.new(name='SurfaceUV')
    for old in list(obj.data.uv_layers):
        if old.name!='SurfaceUV':obj.data.uv_layers.remove(old)
    obj.data.uv_layers.active_index=0;uv.active_render=True
    a,b,c,d=REGIONS[kind];pad=4/1254
    for face in obj.data.polygons:
        normal=obj.matrix_world.to_3x3()@face.normal
        n=Vector((normal.x,normal.z,-normal.y));axis=max(range(3),key=lambda i:abs(n[i]))
        axes=[i for i in range(3)if i!=axis]
        if kind=='post' and 1 in axes:
            axes=[next(i for i in axes if i!=1),1]  # Vertical runoff remains vertical.
        elif kind=='beam' and longest in axes:
            axes=[longest,next(i for i in axes if i!=longest)]
        elif axis==1:axes=[0,2]
        for loop_index in face.loop_indices:
            vertex=obj.matrix_world@obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            q=(vertex.x,vertex.z,-vertex.y)
            u=(q[axes[0]]-row['min'][axes[0]])/max(size[axes[0]],1e-9)
            v=(q[axes[1]]-row['min'][axes[1]])/max(size[axes[1]],1e-9)
            uv.data[loop_index].uv=(a+pad+max(0,min(1,u))*(c-a-2*pad),b+pad+max(0,min(1,v))*(d-b-2*pad))
    obj['atlas_region']=kind


def area2(poly):
    return .5*sum(poly[i][0]*poly[(i+1)%len(poly)][1]-poly[(i+1)%len(poly)][0]*poly[i][1]for i in range(len(poly))) if len(poly)>=3 else 0


def clip_convex(subject,clip):
    """Double precision 2D polygon clipping of actual coplanar triangles."""
    if area2(clip)<0:clip=list(reversed(clip))
    output=list(subject)
    for a,b in zip(clip,clip[1:]+clip[:1]):
        incoming=output;output=[]
        if not incoming:break
        def side(q):return (b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0])
        previous=incoming[-1];before=side(previous)
        for current in incoming:
            now=side(current)
            if (now>=0)!=(before>=0):
                denominator=before-now
                if abs(denominator)>1e-18:
                    t=before/denominator;output.append((previous[0]+t*(current[0]-previous[0]),previous[1]+t*(current[1]-previous[1])))
            if now>=0:output.append(current)
            previous,before=current,now
    return output


def coplanar_diagnosis(meshes):
    """Global same-facing overlap; ordinary opposite-facing end contact is distinct.

    No AABB-only overlap is called a surface defect. Actual world triangles must
    have parallel normals, same plane and positive clipped area. No hidden-pair
    whitelist: remaining positive pairs are reported and prevent a green result.
    """
    buckets={}
    for obj in meshes:
        obj.data.calc_loop_triangles()
        for tri in obj.data.loop_triangles:
            pts=[obj.matrix_world@obj.data.vertices[index].co for index in tri.vertices]
            n=(pts[1]-pts[0]).cross(pts[2]-pts[0]);length=n.length
            if length<1e-12:continue
            n/=length;distance=n.dot(pts[0]);axis=max(range(3),key=lambda i:abs(n[i]));axes=[i for i in range(3)if i!=axis]
            projected=[(float(point[axes[0]]),float(point[axes[1]]))for point in pts]
            row={'object':obj.name,'triangle':tri.index,'n':tuple(n),'d':distance,'axis':axis,'p':projected,'bounds':[(min(x[i]for x in projected),max(x[i]for x in projected))for i in range(2)]}
            buckets.setdefault(tuple(round(float(value),5)for value in n),[]).append(row)
    pairs={}
    for bucket in buckets.values():
        bucket.sort(key=lambda row:row['d'])
        for index,a in enumerate(bucket):
            for b in bucket[index+1:]:
                if b['d']-a['d']>EPS:break
                if a['object']==b['object']:continue
                if any(min(a['bounds'][i][1],b['bounds'][i][1])-max(a['bounds'][i][0],b['bounds'][i][0])<=1e-9 for i in range(2)):continue
                if sum(a['n'][i]*b['n'][i]for i in range(3))<1-1e-8:continue
                area=abs(area2(clip_convex(a['p'],b['p'])))/abs(a['n'][a['axis']])
                if area<=1e-9:continue
                key=tuple(sorted((a['object'],b['object'])))
                hit=pairs.setdefault(key,{'objects':list(key),'overlap_area_m2':0.0,'triangle_pairs':0,'examples':[]})
                hit['overlap_area_m2']+=area;hit['triangle_pairs']+=1
                if len(hit['examples'])<3:hit['examples'].append([a['triangle'],b['triangle'],area])
    return sorted(pairs.values(),key=lambda row:-row['overlap_area_m2'])


def main():
    assert sha(INPUT)==INPUT_SHA and sha(ATLAS)==ATLAS_SHA
    assert not (OUT/'clinic_reception_v5.blend').exists(),'Preserve previous output before retry'
    bpy.ops.wm.open_mainfile(filepath=str(INPUT));scene=bpy.context.scene
    original={obj.name:geometry_digest(obj)for obj in scene.objects if obj.type=='MESH'}
    temp=plain('V5_TemporaryBuild',(.1,.23,.25))
    modified=[]
    # Pillar body, foot and collar meet only at horizontal end planes.
    for name in ['FrontPostLeft','FrontPostRight']:
        obj=bpy.data.objects[name];row=bounds(obj);lo=row['min'][:];hi=row['max'][:]
        lo[1]=.12;hi[1]=2.74;replace_box(obj,lo,hi,temp,.008);modified.append(name)
    # Same demonstrated construction defect in existing front window joints.
    for obj in list(scene.objects):
        if obj.type=='MESH' and obj.name.startswith('WindowJamb'):
            row=bounds(obj);lo=row['min'][:];hi=row['max'][:]
            lo[1]=.94;hi[1]=2.5;name=obj.name;replace_box(obj,lo,hi,temp,.008);modified.append(name)
    # Split the existing longitudinal batten at the cross-batten, not a new detail.
    added=[]
    for obj in list(scene.objects):
        if obj.type!='MESH' or '_SeamBatten_' not in obj.name:continue
        name=obj.name;parent=obj.parent;row=bounds(obj)
        cross=bounds(bpy.data.objects[name.split('_SeamBatten_')[0]+'_CrossBatten'])
        lo=row['min'][:];hi=row['max'][:];bpy.data.objects.remove(obj,do_unlink=True);modified.append(name)
        for suffix,z0,z1 in [('A',lo[2],cross['min'][2]),('B',cross['max'][2],hi[2])]:
            a=lo[:];b=hi[:];a[2]=z0;b[2]=z1
            new=box(name+'_'+suffix,a,b,temp,.004);transform=new.matrix_world.copy();new.parent=parent;new.matrix_world=transform;added.append(new.name)
    bpy.context.view_layer.update()

    inputs=OUT/'source_inputs';inputs.mkdir(exist_ok=True)
    image_path=inputs/'clinic_gravity_basecolor_v4_UNEDITED.png'
    if image_path.exists():assert sha(image_path)==ATLAS_SHA
    else:shutil.copyfile(ATLAS,image_path)
    image=bpy.data.images.load(str(image_path),check_existing=False);image.colorspace_settings.name='sRGB'
    clean=plain('V5_CleanExteriorOffwhite',(.59,.61,.57),.80)
    clean_blue=plain('V5_CleanInteriorBlue',(.10,.24,.26),.60,.14)
    floor=plain('V5_QuietServiceFloor',(.25,.29,.28),.82);V4.paint_mask(floor,'floor_route')
    blue_post=atlas_material('V5_AtlasBluePost',image,'post',.70,.10)
    blue_beam=atlas_material('V5_AtlasBlueBeam',image,'beam',.70,.10)
    gray=atlas_material('V5_AtlasGrayRoof',image,'steel',.69,.24)
    dark_gray=gray.copy();dark_gray.name='V5_AtlasGrayCanopy'
    # Source atlas is not pixel edited. A constant tint keeps the porch subordinate.
    nodes=dark_gray.node_tree.nodes;links=dark_gray.node_tree.links;shader=nodes['ClinicPrincipled']
    source=shader.inputs['Base Color'].links[0].from_socket
    tint=nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1;tint.inputs[2].default_value=(.58,.64,.64,1)
    links.new(source,tint.inputs[1]);links.new(tint.outputs[0],shader.inputs['Base Color'])
    marked=dark_gray.copy();marked.name='V5_AtlasGrayCanopyMedical';V4.paint_mask(marked,'roof_cross')
    roof_plain=plain('V5_RoofGasket',(.10,.14,.15),.68,.3)
    roof_blue_post=blue_post.copy();roof_blue_post.name='V5_RoofBluePost'
    roof_blue_beam=blue_beam.copy();roof_blue_beam.name='V5_RoofBlueBeam'
    roof_mats=[gray,dark_gray,marked,roof_plain,roof_blue_post,roof_blue_beam]
    mapped=[]
    external_prefixes=('FrontPost','CornerPost','FrontHeader','Window','FacadeEdge','DoorJamb','DoorHeader','DoorTrack','EastWindowPost','EastWindowHead','EastWindowSill','EastWallHeader')
    for obj in scene.objects:
        if obj.type!='MESH':continue
        name=obj.name;row=bounds(obj);size=[row['max'][i]-row['min'][i]for i in range(3)]
        in_roof=name.startswith(('RearRoof','Canopy'))
        if in_roof:
            if '_Panel_' in name:
                material=marked if name.startswith('CanopyRight') else dark_gray if name.startswith('CanopyLeft') else gray
                assign(obj,material);map_atlas(obj,'steel');mapped.append(name)
            elif name.endswith('_Subdeck') or '_Bolt' in name:assign(obj,roof_plain)
            else:
                kind='post' if size[1]>=max(size[0],size[2]) else 'beam'
                assign(obj,roof_blue_post if kind=='post' else roof_blue_beam);map_atlas(obj,kind);mapped.append(name)
        elif name.startswith(external_prefixes):
            kind='post' if size[1]>=max(size[0],size[2]) else 'beam'
            assign(obj,blue_post if kind=='post' else blue_beam);map_atlas(obj,kind);mapped.append(name)
        elif name=='FrontDeck_existing_interface':assign(obj,floor)
        elif any(node.type=='TEX_NOISE' for material in obj.data.materials if material and material.use_nodes for node in material.node_tree.nodes):
            # Remove V4 cloud noise entirely; no amplitude tweaking or extra layer.
            assign(obj,clean_blue if name.startswith('InteriorLamp') else clean)
    bpy.context.view_layer.update()
    meshes=[obj for obj in scene.objects if obj.type=='MESH'];rows=[bounds(obj)for obj in meshes]
    unexpected=[obj.name for obj in meshes if obj.name in original and obj.name not in modified and geometry_digest(obj)!=original[obj.name]]
    contacts={name:min(bounds(obj)['min'][1]for obj in V4.descendant_meshes(bpy.data.objects[name]))for name in ['Stretcher','TreatmentBedGroup','ReceptionDeskGroup']}
    rays=[V4.eye_ray(scene,eye,target)for eye,target in [([0,1.65,1.2],[0,.65,-2.64]),([.75,1.65,1.2],[.55,.65,-2.64]),([-.75,1.65,1.2],[-.55,.65,-2.64])]]
    pillar_pairs=[]
    for side in ['Left','Right']:
        names=['FrontPost'+side,'FrontPostFoot'+side,'FrontPostCollar'+side]
        for a,b in itertools.combinations(names,2):
            ba,bb=bounds(bpy.data.objects[a]),bounds(bpy.data.objects[b]);widths=[max(0,min(ba['max'][i],bb['max'][i])-max(ba['min'][i],bb['min'][i]))for i in range(3)]
            pillar_pairs.append({'objects':[a,b],'overlap_volume_m3':math.prod(widths),'positive_overlap':overlap(ba,bb['min'],bb['max'])})
    actual_coplanar=coplanar_diagnosis(meshes)
    corner_overlap=[]
    adjoining=[row for row in rows if row['name'].startswith(('FrontSill','FrontHeader','FacadeEdge','EastWindow','EastWall','WestWall','WestInner'))]
    for name in ['CornerPostLeft','CornerPostRight']:
        corner=bounds(bpy.data.objects[name])
        corner_overlap.extend([{'corner':name,'other':row['name']}for row in adjoining if overlap(row,corner['min'],corner['max'])])
    checks={
        'front_3m_corridor_clear':not any(overlap(row,[-5,0,.5],[5,3,3.5])for row in rows),
        'door_3_4m_by_2_8m_clear':not any(overlap(row,[-1.7,0,-.33],[1.7,2.8,.5])for row in rows),
        'entry_turning_bay_clear':not any(overlap(row,[-1.65,0,-2.5],[1.65,2.75,-.61])for row in rows),
        'unchanged_envelope':all(row['min'][0]>=-5-EPS and row['max'][0]<=5+EPS and row['min'][1]>=-.4-EPS and row['max'][1]<=3.3+EPS and row['min'][2]>=-4-EPS and row['max'][2]<=4+EPS for row in rows),
        'actual_furniture_ground_contact':all(abs(value)<EPS for value in contacts.values()),
        'actual_front_side_corner_volumes_disjoint':not corner_overlap,
        'normal_roof_three_entry_counter_rays':all(row['desk_visible']for row in rays),
        'only_explicit_joint_geometry_changed':not unexpected,
        'pillar_foot_body_cap_six_pairs_no_volume_overlap':not any(row['positive_overlap']for row in pillar_pairs),
        'all_actual_same_facing_coplanar_triangle_areas_zero':not actual_coplanar,
        'no_noise_nodes_on_any_used_material':not any(node.type=='TEX_NOISE'for obj in meshes for material in obj.data.materials if material and material.use_nodes for node in material.node_tree.nodes),
        'atlas_image_correct_srgb_and_source_bytes':image.colorspace_settings.name=='sRGB' and sha(image_path)==ATLAS_SHA,
        'mapped_meshes_have_one_active_surface_uv':all(len(bpy.data.objects[name].data.uv_layers)==1 and bpy.data.objects[name].data.uv_layers.active.name=='SurfaceUV' and bpy.data.objects[name].data.uv_layers.active.active_render for name in mapped),
        'independent_groups_preserved':all(name in bpy.data.objects for name in ['DoorLeft','DoorRight','RearRoof','CanopyLeft','CanopyRight','ReceptionLight','Stretcher','TreatmentBedGroup','ReceptionDeskGroup','ReceptionSign']),
    }
    report={'status':'source_v5_checked_not_runtime_or_final_art','input_sha256':INPUT_SHA,'atlas_sha256':ATLAS_SHA,'checks':checks,'modified_old_meshes':modified,'split_batten_meshes':added,'unexpected_geometry_changes':unexpected,'pillar_actual_3d_pairs':pillar_pairs,'corner_volume_overlap':corner_overlap,'same_facing_coplanar_surface_pairs':actual_coplanar,'counter_rays':rays,'mesh_count':len(meshes),'actual_bounds':rows,'atlas_mapped_meshes':mapped,'atlas_regions':REGIONS,'limits':['No full solid-union or arbitrary self-intersection certification','Actual triangle coplanarity is distinct from AABB overlap','BaseColor only, no fabricated physical normal maps','No game collision/occlusion, no GLB, no lower support']}
    (OUT/'reception_v5_geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    if not all(checks.values()):
        failed=OUT/('clinic_reception_v5_failed_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(failed),relative_remap=False)
        raise AssertionError(checks)
    scene.camera.data.ortho_scale=22;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.filepath=str(OUT/'reception_v5_normal.png')
    image.filepath='//source_inputs/'+image_path.name
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'clinic_reception_v5.blend'),relative_remap=False)
    assert Path(bpy.path.abspath(image.filepath)).resolve()==image_path.resolve()
    if '--render' in sys.argv or '--render-pair' in sys.argv:bpy.ops.render.render(write_still=True)
    if '--render-pair' in sys.argv:
        for material in roof_mats:material.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=.16
        scene.render.filepath=str(OUT/'reception_v5_roof_fade.png');bpy.ops.render.render(write_still=True)
        for material in roof_mats:material.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=1


if __name__=='__main__':main()
