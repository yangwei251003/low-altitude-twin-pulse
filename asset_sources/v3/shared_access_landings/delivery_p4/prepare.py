"""Build two explicit PBR bake receivers, preserving the approved evaluated geometry."""
from pathlib import Path
import hashlib
import json
import math
import sys
import time
from collections import defaultdict

sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
SOURCE=OUT.parent/'p4/source_review_20261019_152843_ce6ff1/shared_access_landings_p4.blend'
SOURCE_SHA='726db4e2bc08ce404696c3c959269473a961a6b2e228e210609cb62f0585199d'
UVS=['SourceXZ','SourceY','PaintPanelUV','TreadUV','PlateMetres','PlateSize']
GROUPS=['WestLanding','EastLanding','SouthBypass','WestOuterRail','EastOuterRail','SouthOuterRail']
DENSITY=288.0
PADDING=8
COATING_DOMAIN=((-0.12,-0.02),(1.02,1.03))


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gp(p):return [p[0],p[2],-p[1]]
def write(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def deck_fingerprint(obj):
    """Compare the real bake receiver and its reachable material, not filenames."""
    mesh=obj.data
    data={'vertices':[list(v.co) for v in mesh.vertices],
          'faces':[list(p.vertices) for p in mesh.polygons],
          'material_indices':[p.material_index for p in mesh.polygons],
          'uv':{uv.name:[list(v.uv) for v in uv.data] for uv in mesh.uv_layers},
          'roles':[list(v.color) for v in mesh.color_attributes['WeatherUse'].data]}
    mat=mesh.materials[0];output=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
    pending=[output];visited=set();nodes=[]
    while pending:
        n=pending.pop()
        if n.name in visited:continue
        visited.add(n.name);r={'name':n.name,'type':n.type,'inputs':[]}
        for key in ['operation','blend_type','data_type','use_clamp','clamp_factor','clamp_result','mode',
                    'space','uv_map','layer_name','interpolation','extension','projection','vector_type','distribution']:
            if hasattr(n,key):r[key]=getattr(n,key)
        for sock in n.inputs:
            item={'name':sock.name,'links':[(l.from_node.name,l.from_socket.name) for l in sock.links]}
            if hasattr(sock,'default_value'):
                value=sock.default_value
                item['default']=list(value) if hasattr(value,'__len__') and not isinstance(value,str) else value
            r['inputs'].append(item);pending.extend(l.from_node for l in sock.links)
        if n.type=='TEX_IMAGE':
            img=n.image;_=tuple(img.pixels[:4]);assert img.has_data
            raw=bytes(img.packed_file.data) if img.packed_file else Path(bpy.path.abspath(img.filepath)).read_bytes()
            r['image']={'sha256':hashlib.sha256(raw).hexdigest(),'colorspace':img.colorspace_settings.name,'size':list(img.size)}
        nodes.append(r)
    data['material_graph']=sorted(nodes,key=lambda n:n['name'])
    return {'sha256':hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
            'vertices':len(mesh.vertices),'triangles':len(mesh.polygons),'reachable_nodes':len(nodes)}


def gather():
    deps=bpy.context.evaluated_depsgraph_get();rows=[];plates={};materials={}
    parts=sorted([o for o in bpy.data.objects if o.get('source_body_id')],key=lambda o:o.name)
    assert len(parts)==21
    for obj in parts:
        me=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
        me.calc_loop_triangles();piece_names=json.loads(obj['construction_piece_names'])
        normal_matrix=obj.matrix_world.to_3x3().inverted().transposed()
        for tri in me.loop_triangles:
            poly=me.polygons[tri.polygon_index];mat=me.materials[poly.material_index]
            assert mat.name in ('IB_BlueSteel','IB_DeckSteel');materials[mat.name]=mat
            positions=[tuple(obj.matrix_world@me.vertices[v].co) for v in tri.vertices]
            uv={key:[tuple(me.uv_layers[key].data[li].uv) for li in tri.loops] for key in UVS}
            roles=[tuple(me.color_attributes['WeatherUse'].data[li].color) for li in tri.loops]
            top=all(c[1]>.99 for c in roles)
            piece=int(me.attributes['construction_piece'].data[tri.polygon_index].value)
            row={'body':obj['source_body_id'],'object':obj.name,'piece':piece_names[piece],
                 'positions':positions,'normals':[tuple((normal_matrix@me.corner_normals[li].vector).normalized()) for li in tri.loops],
                 'uvs':uv,'roles':roles,'material':mat.name,'top':top,'delivery_uv':None}
            rows.append(row)
            if top:
                assert row['piece'].startswith('walking_plate_') and mat.name=='IB_DeckSteel'
                key=(obj.name,piece)
                entry=plates.setdefault(key,{'rows':[],'points':[],'body':row['body'],'object':obj.name,'piece':row['piece']})
                entry['rows'].append(len(rows)-1);entry['points'].extend([gp(p) for p in positions])
        bpy.data.meshes.remove(me)
    assert len(rows)==13908 and len(plates)==44
    return parts,rows,plates,materials


def rectangle_plan(plates,rows):
    by_size=defaultdict(dict)
    for key,p in plates.items():
        lo=[min(v[i] for v in p['points']) for i in (0,2)];hi=[max(v[i] for v in p['points']) for i in (0,2)]
        size=tuple(round(hi[i]-lo[i],5) for i in range(2))
        # The two variants correspond to actual left/right (or south/north) traffic sides.
        cross=sum(v[1] for ri in p['rows'] for v in rows[ri]['uvs']['SourceXZ'])/(3*len(p['rows']))
        variant=int(cross>=0)
        p.update(lo=lo,hi=hi,size=size,variant=variant)
        by_size[size].setdefault(variant,key)
    sizes=[(1.788,1.988),(1.788,1.59067),(1.688,1.988),(1.688,1.49067),(1.488,1.688)]
    assert set(by_size)==set(sizes) and all(set(v)=={0,1} for v in by_size.values())
    # Two rows of A/B/C/E, then D/D: 400px lower strip is reserved for quiet steel/fixings.
    order=[[(0,0),(1,0),(2,0),(4,0)],[(0,1),(1,1),(2,1),(4,1)],[(3,0),(3,1)]]
    rects={};y=400
    for line in order:
        x=8;max_height=0
        for index,variant in line:
            size=sizes[index];w=math.ceil(size[0]*DENSITY)+2*PADDING;h=math.ceil(size[1]*DENSITY)+2*PADDING
            rects[(size,variant)]={'x':x,'y':y,'width':w,'height':h,'size_m':list(size),'variant':variant,
                                  'representative':list(by_size[size][variant])}
            x+=w;max_height=max(max_height,h)
        assert x<=2048
        y+=max_height
    assert y<=2048
    representatives=set()
    for key,p in plates.items():
        rect=rects[(p['size'],p['variant'])]
        for ri in p['rows']:
            row=rows[ri]
            row['delivery_uv']=[((rect['x']+PADDING+(v[0]-p['lo'][0])*DENSITY)/2048,
                                 (rect['y']+PADDING+(v[2]-p['lo'][1])*DENSITY)/2048) for v in [gp(a) for a in row['positions']]]
        if tuple(rect['representative'])==key:representatives.update(p['rows'])
    assert len(representatives)==20
    return representatives,{'walking_plate_count':44,'unique_sizes_m':[list(s) for s in sizes],
        'variants_per_size':2,'density_pixels_per_m':DENSITY,'pitch_95mm_pixels':.095*DENSITY,
        'top_short_width_5p76mm_pixels':.00576*DENSITY,'rectangles':list(rects.values()),
        'quiet_steel_reserved_uv':[.01,.01,.99,390/2048],
        'all_copies_no_uv_rotation':True,'scope':'Exact dimensions; representative wear is intentionally reused, not unique over all 137m2.'}


def mesh_from_rows(name,rows,indices,materials):
    verts=[];faces=[];normals=[]
    for ri in indices:
        row=rows[ri];start=len(verts);verts.extend(row['positions']);faces.append((start,start+1,start+2));normals.extend(row['normals'])
    mesh=bpy.data.meshes.new(name+'_Mesh');mesh.from_pydata(verts,[],faces);mesh.update()
    slots=list(materials)
    for mat in materials.values():mesh.materials.append(mat)
    for face,ri in zip(mesh.polygons,indices):
        face.material_index=slots.index(rows[ri]['material']);face.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for key in UVS+['DeliveryBakeUV']:mesh.uv_layers.new(name=key)
    mesh.color_attributes.new(name='WeatherUse',type='FLOAT_COLOR',domain='CORNER')
    for fi,ri in enumerate(indices):
        row=rows[ri]
        for j in range(3):
            li=fi*3+j
            for key in UVS:mesh.uv_layers[key].data[li].uv=row['uvs'][key][j]
            mesh.color_attributes['WeatherUse'].data[li].color=row['roles'][j]
            if row['delivery_uv'] is not None:mesh.uv_layers['DeliveryBakeUV'].data[li].uv=row['delivery_uv'][j]
    for attribute_name,values in [('DeliveryGroup',[GROUPS.index(rows[i]['body']) for i in indices]),('SourceRow',indices)]:
        attribute=mesh.attributes.new(name=attribute_name,type='INT',domain='FACE')
        for d,value in zip(attribute.data,values):d.value=value
    mesh.uv_layers.active_index=mesh.uv_layers.find('DeliveryBakeUV')
    for layer in mesh.uv_layers:layer.active_render=layer.name=='DeliveryBakeUV'
    obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
    obj.matrix_basis=Matrix.Identity(4)
    return obj


def unwrap_quiet(proxy,rows):
    bpy.ops.object.select_all(action='DESELECT');proxy.select_set(True);bpy.context.view_layer.objects.active=proxy
    bpy.context.tool_settings.mesh_select_mode=(False,False,True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
    for poly,row in zip(proxy.data.polygons,rows):poly.select=row['material']=='IB_DeckSteel' and not row['top']
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    layer=proxy.data.uv_layers['DeliveryBakeUV']
    for poly,row in zip(proxy.data.polygons,rows):
        if row['material']=='IB_DeckSteel' and not row['top']:
            row['delivery_uv']=[(.01+layer.data[li].uv.x*.98,.01+layer.data[li].uv.y*(390/2048-.01)) for li in poly.loop_indices]
        elif row['material']=='IB_BlueSteel':
            lo,hi=COATING_DOMAIN
            row['delivery_uv']=[tuple((uv[i]-lo[i])/(hi[i]-lo[i]) for i in range(2))
                                for uv in row['uvs']['PaintPanelUV']]
        for li,value in zip(poly.loop_indices,row['delivery_uv']):layer.data[li].uv=value
    assert all(math.isfinite(v) and -1e-6<=v<=1.000001 for loop in layer.data for v in loop.uv)


def coating_receiver(material):
    # The approved coating output depends only on PaintPanelUV, as source audit proves.
    # Preserve its authored 6m/1m metric basis for tangent normal baking.
    row={'body':'WestLanding','material':'IB_BlueSteel','roles':[(1,0,0,0)]*3}
    # Source uses EXTEND beyond [0,1]. Bake that exact domain, with edge padding,
    # instead of clamping individual faces or allowing runtime sampler repetition.
    lo,hi=COATING_DOMAIN
    width=6*(hi[0]-lo[0]);height=hi[1]-lo[1]
    verts=[(0,0,0),(width,0,0),(width,-height,0),(0,-height,0)]
    uv=[(0,0),(1,0),(1,1),(0,1)];rs=[]
    source_uv=[(lo[0]+u*(hi[0]-lo[0]),lo[1]+v*(hi[1]-lo[1])) for u,v in uv]
    for ids in [(0,2,1),(0,3,2)]:
        rs.append(dict(row,positions=[verts[i] for i in ids],normals=[(0,0,1)]*3,
                  uvs={k:[source_uv[i] if k=='PaintPanelUV' else (0,0) for i in ids] for k in UVS},
                  delivery_uv=[uv[i] for i in ids]))
    return mesh_from_rows('CoatingBakeProxy',rs,list(range(2)),{'IB_BlueSteel':material})


def main():
    started=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    assert not (OUT/'uv_checkpoint.blend').exists(), 'Preserve any prior preparation failure/checkpoint.'
    prior=OUT/'failed_missing_paint_20261019_1636/uv_checkpoint.blend'
    reuse=None
    if prior.exists():
        bpy.ops.wm.open_mainfile(filepath=str(prior))
        reuse=deck_fingerprint(bpy.data.objects['DeckBakeProxy'])
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
    source_images=[]
    for image in bpy.data.images:
        if image.source!='FILE':continue
        # Resolve while the ORIGINAL .blend is current, before saving elsewhere.
        absolute=Path(bpy.path.abspath(image.filepath)).resolve()
        assert absolute.is_file(), ('Missing source image',image.name,str(absolute))
        image.filepath=str(absolute)
        _=tuple(image.pixels[:4]);assert image.has_data and min(image.size)>0
        source_images.append({'name':image.name,'path':str(absolute),'sha256':sha(absolute),'size':list(image.size)})
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    scene.render.threads_mode='FIXED';scene.render.threads=2
    parts,rows,plates,mats=gather();representatives,atlas=rectangle_plan(plates,rows)
    proxy=mesh_from_rows('DeliveryProxy',rows,list(range(len(rows))),mats)
    unwrap_quiet(proxy,rows)
    chosen=[i for i,r in enumerate(rows) if r['material']=='IB_DeckSteel' and (not r['top'] or i in representatives)]
    deck=mesh_from_rows('DeckBakeProxy',rows,chosen,{'IB_DeckSteel':mats['IB_DeckSteel']})
    if reuse:
        current=deck_fingerprint(deck)
        assert current==reuse, ('Deck bake mapping/material changed',reuse,current)
    coating=coating_receiver(mats['IB_BlueSteel'])
    for obj in bpy.data.objects:
        if obj.type=='MESH':obj.hide_render=True;obj.hide_set(True)
    bpy.context.view_layer.objects.active=None
    per_body={name:sum(1 for r in rows if r['body']==name) for name in GROUPS}
    scene['delivery_source_sha256']=SOURCE_SHA
    checkpoint=OUT/'uv_checkpoint.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint),relative_remap=False)
    report={'stage':'UV_PREPARED_PENDING_CHANNEL_BAKES','source_sha256':SOURCE_SHA,
            'checkpoint_sha256':sha(checkpoint),'geometry_triangles':len(rows),'body_triangles':per_body,
            'source_parts':len(parts),'atlas':atlas,'deck_bake_triangles':len(chosen),
            'source_images_resolved_before_save':source_images,
            'deck_reuse_exact_receiver_and_material_fingerprint':reuse,
            'materials':{'Deck':2048,'Coating':1024},'runtime_same_uv_all_pbr_channels':True,
            'coating_source_uv_domain':COATING_DOMAIN,
            'coating_pixels_per_m':[1024/(6*(COATING_DOMAIN[1][0]-COATING_DOMAIN[0][0])),
                                    1024/(COATING_DOMAIN[1][1]-COATING_DOMAIN[0][1])],
            'geometry_added':False,'authoring_source_unchanged':sha(SOURCE)==SOURCE_SHA,
            'seconds':time.monotonic()-started,'limits':['Atlas reuses ten actual source plate variants; unique global wear is reduced.',
            'Coating transfer uses its explicit PaintPanelUV function; no object/generated coordinate dependency.']}
    write(OUT/'atlas_preparation_report.json',report)
    print('LANDING_ATLAS '+json.dumps({'triangles':len(rows),'seconds':report['seconds'],'density':DENSITY}),flush=True)


if __name__=='__main__':main()
