"""Read-only Blender preflight: actual UV occupancy, islands, normal nodes and padding."""
from pathlib import Path
import sys,os,time,json,math,collections
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
import bpy
import numpy as np
import common as C
import diagnose as D

def image_data(name):
    im=bpy.data.images[name];arr=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(arr)
    return arr.reshape((im.size[1],im.size[0],4))

def node_connections(mat):
    n=mat.node_tree.nodes;rows=[]
    for q in n:
        if q.type not in {'TEX_IMAGE','UVMAP','NORMAL_MAP','BSDF_PRINCIPLED'}:continue
        row={'name':q.name,'type':q.type,'inputs':{s.name:[{'node':link.from_node.name,'type':link.from_node.type,'socket':link.from_socket.name} for link in s.links] for s in q.inputs if s.links}}
        if q.type in {'UVMAP','NORMAL_MAP'}:row['uv_map']=q.uv_map
        if q.type=='TEX_IMAGE':row.update(image=q.image.name,space=q.image.colorspace_settings.name,interpolation=q.interpolation,extension=q.extension)
        rows.append(row)
    return rows

def main():
    start=time.monotonic();scene=C.open_source();before=C.fingerprints()
    expected='e8ddefed8b45dab3b94ab24943b0a8a6027d4ef3f370063c87af59d230e08ed2'
    assert C.sha(C.HERE/'diagnostic_manifest.json')==expected
    me=bpy.data.objects['LowFull'].data;gm=bpy.data.objects['LowGround'].data
    me.calc_loop_triangles();gm.calc_loop_triangles();triangles=list(me.loop_triangles);uv=me.uv_layers['BakeUV']
    ground={D.tri_key(gm,t):D.face_kind(gm,t) for t in gm.loop_triangles}
    kinds=[ground.get(D.tri_key(me,t),'solid') for t in triangles]
    parent=list(range(len(triangles)));edges={};geometry_edges={}
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    def join(a,b):
        a,b=find(a),find(b)
        if a!=b:parent[b]=a
    for t in triangles:
        for k in range(3):
            la,lb=t.loops[k],t.loops[(k+1)%3];va,vb=me.loops[la].vertex_index,me.loops[lb].vertex_index
            key=tuple(sorted(((va,*[round(float(x),7) for x in uv.data[la].uv]),(vb,*[round(float(x),7) for x in uv.data[lb].uv]))))
            if key in edges:join(t.index,edges[key])
            else:edges[key]=t.index
            geometry_edges.setdefault(tuple(sorted((va,vb))),[]).append(t.index)
    roots={r:i for i,r in enumerate(sorted({find(t.index) for t in triangles}))}
    island_ids=np.array([roots[find(t.index)] for t in triangles],dtype=np.int32)
    normal=image_data('Study1K_Normal');orm=image_data('Study1K_ORM');height,width,_=normal.shape
    owners=np.full((height,width),-1,np.int32);overlaps=[];triuv=[]
    for t in triangles:
        q=np.array([tuple(uv.data[li].uv) for li in t.loops],dtype=np.float64);triuv.append(q)
        a,b,c=q;det=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);assert abs(det)>1e-14
        x0=max(0,math.floor(float(q[:,0].min())*width-.5));x1=min(width-1,math.ceil(float(q[:,0].max())*width-.5))
        y0=max(0,math.floor(float(q[:,1].min())*height-.5));y1=min(height-1,math.ceil(float(q[:,1].max())*height-.5))
        yy,xx=np.mgrid[y0:y1+1,x0:x1+1];px=(xx+.5)/width-a[0];py=(yy+.5)/height-a[1]
        v=(px*(c[1]-a[1])-py*(c[0]-a[0]))/det;w=((b[0]-a[0])*py-(b[1]-a[1])*px)/det;u=1-v-w
        inside=(u>1e-7)&(v>1e-7)&(w>1e-7) # Strict interior; do not count shared-edge centers as overlap.
        block=owners[y0:y1+1,x0:x1+1]
        hit=inside&(block>=0)
        if hit.any():overlaps.append({'triangle':t.index,'pixels':int(hit.sum()),'previous_owners':np.unique(block[hit]).tolist()})
        block[inside]=t.index
    valid=owners>=0;pixel_island=np.full_like(owners,-1);pixel_island[valid]=island_ids[owners[valid]]
    kind_id={'top':1,'side':2,'bottom':3,'solid':4};labels=np.zeros_like(owners);kt=np.array([kind_id[k] for k in kinds],np.int32);labels[valid]=kt[owners[valid]]
    # Negative tangent Z is a strong orientation anomaly for these near-matching
    # high/low surfaces, not a universal normal-map validity rule.
    bad=valid&(normal[:,:,2]<.5);rows=[]
    for y,x in zip(*np.where(bad)):
        tid=int(owners[y,x]);iid=int(island_ids[tid]);q=triuv[tid]
        neighborhood=pixel_island[max(0,y-8):min(height,y+9),max(0,x-8):min(width,x+9)]
        other=neighborhood[(neighborhood>=0)&(neighborhood!=iid)]
        adjacent_kinds=set()
        for k in range(3):
            t=triangles[tid];e=tuple(sorted((t.vertices[k],t.vertices[(k+1)%3])))
            adjacent_kinds.update(kinds[j] for j in geometry_edges[e] if j!=tid)
        point=np.array([(x+.5)/width,(y+.5)/height]);dist=[]
        for k in range(3):
            a,b=q[k],q[(k+1)%3];d=b-a;f=np.clip(np.dot(point-a,d)/np.dot(d,d),0,1);dist.append(np.linalg.norm((point-(a+f*d))*[width,height]))
        rows.append({'pixel_xy_bottom_origin':[int(x),int(y)],'uv':point.tolist(),'triangle':tid,'island':iid,'surface':kinds[tid],
            'normal_rgb':normal[y,x,:3].tolist(),'ao':float(orm[y,x,0]),'distance_to_triangle_edge_pixels':float(min(dist)),
            'other_occupied_islands_within_8px':np.unique(other).tolist(),'geometric_neighbor_kinds':sorted(adjacent_kinds)})
    islands=[]
    for iid in range(len(roots)):
        ids=np.where(island_ids==iid)[0];alluv=np.concatenate([triuv[j] for j in ids]);mask=pixel_island==iid
        islands.append({'id':iid,'triangles':len(ids),'surface_classes':dict(collections.Counter(kinds[j] for j in ids)),
            'uv_bounds':[alluv.min(axis=0).tolist(),alluv.max(axis=0).tolist()],'occupied_pixels':int(mask.sum()),'negative_normal_z_pixels':int((mask&bad).sum())})
    rna=bpy.ops.object.bake.get_rna_type().properties
    defaults={name:getattr(rna[name],'default',None) for name in ('uv_layer','margin','margin_type','use_cage','normal_space') if name in rna}
    settings={name:getattr(scene.render.bake,name) for name in ('margin','margin_type','use_cage','cage_extrusion','max_ray_distance','normal_space') if hasattr(scene.render.bake,name)}
    for name in ('HighGround','LowGround','HighFull','LowFull'):bpy.data.objects[name].data.calc_loop_triangles()
    uvstate={name:{'active':bpy.data.objects[name].data.uv_layers.active.name,'render':[u.name for u in bpy.data.objects[name].data.uv_layers if u.active_render],
                  'triangles':len(bpy.data.objects[name].data.loop_triangles),'polygons':len(bpy.data.objects[name].data.polygons),
                  'ngons':sum(len(p.vertices)>4 for p in bpy.data.objects[name].data.polygons)} for name in ('HighGround','LowGround','HighFull','LowFull')}
    C.write('normal_nodes_and_bake_state.json',{'nodes':node_connections(bpy.data.materials['Study_BakedLow_ExplicitPBR']),'actual_saved_uv_state':uvstate,
        'actual_saved_scene_bake_state':settings,'current_operator_rna_defaults':defaults,'historical_script_explicit':{'margin':8,'uv_layer_argument':'not explicitly supplied; target active_index and active_render both assigned BakeUV','margin_type_argument':'not explicitly supplied'},
        'limit':'Saved scene/default state is not a recording of every historical operator argument. No assertion that default settings caused the fault.'})
    C.write('actual_uv_islands.json',{'size':[width,height],'strict_interior_pixel_count':int(valid.sum()),'overlapping_triangle_interiors':overlaps,'islands':islands})
    C.write('negative_normal_pixels.json',{'scope':'Actual native 1K pixel centers inside actual low UV triangles; PNG not modified. Negative tangent Z is diagnostic for this matched surface pair, not a new geometry acceptance tolerance.','pixels':rows})
    assert before==C.fingerprints();C.check_inputs()
    C.write('inspection_result.json',{'status':'PIXEL_PROVENANCE_EVIDENCE_NOT_REPAIR','pid':os.getpid(),'seconds':time.monotonic()-start,'occupied_pixels':int(valid.sum()),'island_count':len(roots),'overlap_records':len(overlaps),
        'negative_normal_z_by_surface':dict(collections.Counter(r['surface'] for r in rows)),
        'negative_top_pixels_with_other_island_within_8px':sum(r['surface']=='top' and bool(r['other_occupied_islands_within_8px']) for r in rows),
        'mesh_digests':before,'geometry_modified':False,'rendered':False,'baked':False})

if __name__=='__main__':main()
