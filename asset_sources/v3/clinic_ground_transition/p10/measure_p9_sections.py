"""Read-only actual P9 triangle cross sections. No Blender/model execution."""
from pathlib import Path
import ast,csv,hashlib,json,math
import numpy as np

P=Path(__file__).resolve().parent
raw=json.loads((P/'sdna_proxy_arrays.json').read_text(encoding='utf-8'))
attrs=raw['attrs'];vertices=np.asarray(attrs['position'],dtype=float)
faces=np.asarray(attrs['.corner_vert'],dtype=int).reshape((-1,3))
parent=list(range(len(vertices)))
def find(i):
    while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
    return i
for face in faces:
    root=find(int(face[0]))
    for index in face[1:]:parent[find(int(index))]=root
components={}
for i in range(len(vertices)):components.setdefault(find(i),[]).append(i)
soil_ids=set(max(components.values(),key=len))
soil_faces=np.asarray([i for i,f in enumerate(faces) if int(f[0]) in soil_ids])
tris=vertices[faces[soil_faces]]
# P9 is already triangulated; retain the real upper soil surface only.
normal=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0])
top_mask=(normal[:,2]>1e-10)&(np.min(tris[:,:,2],axis=1)>-.179)
top=tris[top_mask];top_indices=soil_faces[top_mask]
assert len(top)==1920 and len(soil_ids)==1237
godot=top[:,:,[0,2,1]].copy();godot[:,:,2]*=-1
xz=godot[:,:,[0,2]];ys=godot[:,:,1]

source=ast.parse((P.parent/'p3/build_asset.py').read_text(encoding='utf-8'))
routes=next(ast.literal_eval(node.value) for node in source.body if isinstance(node,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='ROUTES' for x in node.targets))

def station(points,fraction):
    lengths=[math.dist(a,b) for a,b in zip(points,points[1:])]
    distance=fraction*sum(lengths)
    for a,b,length in zip(points,points[1:],lengths):
        if distance<=length:
            a=np.asarray(a);b=np.asarray(b);tangent=(b-a)/length
            return a+(b-a)*distance/length,tangent
        distance-=length
    raise AssertionError('Station outside route')

def section(center,tangent,extent=.45):
    normal2=np.array([-tangent[1],tangent[0]])
    along=np.sum((xz-center)*normal2,axis=2)
    across=np.sum((xz-center)*tangent,axis=2)
    segments=[]
    for i in range(len(top)):
        cuts=[]
        for a,b in ((0,1),(1,2),(2,0)):
            da,db=across[i,a],across[i,b]
            if abs(da)<1e-10:cuts.append((float(along[i,a]),float(ys[i,a])))
            if da*db<0:
                t=-da/(db-da)
                cuts.append((float(along[i,a]+t*(along[i,b]-along[i,a])),float(ys[i,a]+t*(ys[i,b]-ys[i,a]))))
        if len(cuts)<2:continue
        a,b=min(cuts),max(cuts)
        if b[0]-a[0]>1e-10 and a[0]<=extent and b[0]>=-extent:segments.append((a,b,int(top_indices[i])))
    def height(s):
        candidates=[a[1]+(b[1]-a[1])*(s-a[0])/(b[0]-a[0]) for a,b,_ in segments if a[0]-1e-8<=s<=b[0]+1e-8]
        return max(candidates) if candidates else None
    breaks=sorted(set([-extent,extent,0.0]+[float(v[0]) for a,b,_ in segments for v in (a,b) if -extent<v[0]<extent]))
    profile=[{'offset_m':s,'y_m':height(s)} for s in breaks if height(s) is not None]
    return normal2,segments,profile,height

rows=[];dense=[]
for ri in (0,2,4):
    for fraction in (.18,.38,.62,.82):
        center,tangent=station(routes[ri][0],fraction)
        direction,segments,profile,height=section(center,tangent)
        width=(.105+.085*fraction)*( .86 if ri==2 else 1 )
        left_y,right_y=height(-width),height(width)
        candidates=[r for r in profile if -width<=r['offset_m']<=width]+[{'offset_m':-width,'y_m':left_y},{'offset_m':width,'y_m':right_y}]
        bottom=min(candidates,key=lambda r:r['y_m']);s=bottom['offset_m'];bottom_y=bottom['y_m']
        baseline=left_y+(right_y-left_y)*(s+width)/(2*width)
        # Profile extrema are exact triangle/plane intersection breakpoints.
        left_max=max((r for r in profile if -.40<=r['offset_m']<=-width*.65),key=lambda r:r['y_m'])
        right_max=max((r for r in profile if width*.65<=r['offset_m']<=.40),key=lambda r:r['y_m'])
        shoulderline=left_max['y_m']+(right_max['y_m']-left_max['y_m'])*(s-left_max['offset_m'])/(right_max['offset_m']-left_max['offset_m'])
        row={'route':ri,'fraction':fraction,'center_xz_m':center.tolist(),'tangent_xz':tangent.tolist(),'cross_normal_xz':direction.tolist(),'designed_halfwidth_m':width,'center_y_m':height(0),'bottom':bottom,'designed_banks_y_m':[left_y,right_y],'depth_below_designed_bank_chord_m':baseline-bottom_y,'left_measured_high_shoulder':left_max,'right_measured_high_shoulder':right_max,'depth_below_measured_shoulder_chord_m':shoulderline-bottom_y,'profile_breakpoints':profile,'triangle_segments':[{'a':a,'b':b,'proxy_triangle':index} for a,b,index in segments]}
        rows.append(row)
        for s in np.linspace(-.45,.45,181):dense.append({'route':ri,'fraction':fraction,'offset_m':float(s),'y_m':height(float(s))})

# Actual top-mesh metric and UV sampling densities, no source-function estimate.
lengths=[]
for t in godot:
    for a,b in ((0,1),(1,2),(2,0)):lengths.append(float(np.linalg.norm(t[a,[0,2]]-t[b,[0,2]])))
scan=np.asarray(attrs['SoilScanUV']).reshape((-1,3,2))[top_indices]
bake=np.asarray(attrs['BakeUV']).reshape((-1,3,2))[top_indices]
det=lambda uv:abs((uv[:,1,0]-uv[:,0,0])*(uv[:,2,1]-uv[:,0,1])-(uv[:,1,1]-uv[:,0,1])*(uv[:,2,0]-uv[:,0,0]))/2
worldarea=det(xz);scanarea=det(scan);bakearea=det(bake)
texels_per_meter=np.sqrt(bakearea/worldarea)*2048
out={'source_blend':'../p9/baked_source.blend','source_sha256':raw['blend_sha256'],'method':'Actual saved BakeProxy SDNA arrays. Largest connected component is the closed soil; 1920 upward top triangles. Each cross section intersects those actual triangles, retains triangle breakpoints and uses linear height on the saved triangles. No Blender, procedural rebuild, or game physics was run. Negative/positive sides follow the reported cross normal, not screen left/right.','soil_vertices':len(soil_ids),'soil_top_triangles':len(top),'soil_top_projected_area_m2':float(worldarea.sum()),'soil_top_y_min_max_m':[float(ys.min()),float(ys.max())],'top_triangle_edge_projected_length_quantiles_m':np.percentile(lengths,[0,25,50,75,100]).tolist(),'source_uv_width_m':2.5,'source_pixel_pitch_m':2.5/2048,'actual_scan_uv_worldscale_m_quantiles':np.percentile(np.sqrt(worldarea/scanarea),[0,50,100]).tolist(),'baked_effective_texels_per_meter_quantiles':np.percentile(texels_per_meter,[0,50,100]).tolist(),'sections':rows,'limits':['Designed-bank depth is measured relative to the chord between actual heights at the existing source bank offsets. Broad-slope shoulder maxima may be outside a true local crest; both definitions are reported, not conflated.','Normal-map pixel pitch is not a measured gravel diameter. Texture detail cannot establish geometry displacement.','No new geometry or collision acceptance is implied.']}
(P/'p9_cross_sections.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
with (P/'p9_cross_sections.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=['route','fraction','offset_m','y_m']);w.writeheader();w.writerows(dense)
print(json.dumps({k:v for k,v in out.items() if k!='sections'},indent=2))
print('route t bottomY leftY rightY depth_mm shoulderDepth_mm')
for r in rows:print(r['route'],r['fraction'],round(r['bottom']['y_m'],5),*[round(y,5) for y in r['designed_banks_y_m']],round(r['depth_below_designed_bank_chord_m']*1000,2),round(r['depth_below_measured_shoulder_chord_m']*1000,2))
