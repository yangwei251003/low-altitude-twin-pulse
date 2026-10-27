"""Stage A: real mesh displacement, editable originals, low geometry, checkpoint. No render."""
import importlib.util, math, os, time, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy, bmesh
from mathutils import Vector, Matrix
import common as C

def ground(mat,high):
    n=64;v=[];weights=[]
    for j in range(n+1):
        t=j/n
        for i in range(n+1):
            x=-.45+.9*i/n;z=C.edge(x)-.012+(.9-C.edge(x)+.012)*t
            v.append(C.bp(x,C.ground_height(x,z),z))
            weights.append(C.controls(x,z)[1]*C.smooth(t/.075))
    f=[]
    for j in range(n):
        for i in range(n):
            a=j*(n+1)+i;f.append((a,a+1,a+n+2,a+n+1))
    ring=list(range(n+1))+[j*(n+1)+n for j in range(1,n+1)]+list(range(n*(n+1)+n-1,n*(n+1)-1,-1))+[j*(n+1) for j in range(n-1,0,-1)]
    base=len(v);v.extend((v[k][0],v[k][1],-.18) for k in ring);weights.extend([0.]*len(ring))
    for j,(a,b) in enumerate(zip(ring,ring[1:]+ring[:1])):f.append((a,b,base+(j+1)%len(ring),base+j))
    center=len(v);v.append((0,-.5,-.18));weights.append(0.)
    for j in range(len(ring)):f.append((center,base+(j+1)%len(ring),base+j))
    ob=C.mesh('EditableHighGround' if high else 'EditableLowGround',v,f,mat);ob['soil']=True;C.source_uv(ob)
    for face in ob.data.polygons:face.use_smooth=face.index<n*n
    group=ob.vertex_groups.new(name='ContinuousShoulderInfluence')
    for i,w in enumerate(weights):group.add([i],w,'REPLACE')
    if high:
        mod=ob.modifiers.new('ActualSimpleSubdivision','SUBSURF');mod.subdivision_type='SIMPLE';mod.levels=2;mod.render_levels=2
    tex=bpy.data.textures.get('OriginalRockyHeight') or bpy.data.textures.new('OriginalRockyHeight',type='IMAGE')
    tex.image=C.load_image(C.CFG['height_path'],'Non-Color');tex.extension='REPEAT';tex.use_interpolation=True
    mod=ob.modifiers.new('ActualHeightDisplace_NotNormalOnly','DISPLACE');mod.texture=tex;mod.texture_coords='UV';mod.uv_layer='RockScanUV';mod.direction='Z';mod.space='LOCAL';mod.vertex_group=group.name
    mod.mid_level=C.CFG['fixed_height_median'];mod.strength=C.CFG['fixed_strength_m']
    ob['height_amplitude_authored_not_measured']=True;ob['full_scanned_normal_disabled']=True
    return ob

def concrete(mat):
    xs=[-.45,-.32,-.19,-.07,.045,.16,.29,.38,.45];verts=[]
    for x in xs:
        e=C.edge(x);points=[(0,0),(e-.025,0),(e,-.012),(e+.007,-.052),(e-.014,-.112),(e-.022,-.18),(0,-.18)]
        verts.extend(C.bp(x,y,z) for z,y in points)
    faces=[];m=7
    for i in range(len(xs)-1):
        for j in range(m):faces.append((i*m+j,i*m+(j+1)%m,(i+1)*m+(j+1)%m,(i+1)*m+j))
    faces.extend([tuple(reversed(range(m))),tuple(range((len(xs)-1)*m,len(xs)*m))])
    ob=C.mesh('EditableConcreteBreak_18cm',verts,faces,mat)
    for face in ob.data.polygons:
        top=face.normal.z>.7
        for li in face.loop_indices:ob.data.color_attributes['SurfaceControl'].data[li].color=(.12,0 if top else .75,1 if top else 0,1)
    return ob

def aggregate(mat,slabtree):
    out=[];contacts=[]
    # Embedded aggregate at several heights, not a straight bead row.
    specs=[(-.33,-.027,.026,1.2),(-.23,-.051,.021,.7),(-.12,-.033,.032,2.1),(.06,-.061,.035,.3),(.18,-.025,.018,1.8),(.30,-.048,.028,2.7)]
    for i,(x,y,diam,angle) in enumerate(specs):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1)
        tmp=bpy.context.object;vs=[];e=C.edge(x)
        center=Vector(C.bp(x,y,e-.003))
        rot=Matrix.Rotation(angle,3,'Z') @ Matrix.Rotation(.37+i*.13,3,'X')
        for v in tmp.data.vertices:
            p=rot@Vector((v.co.x*diam*.53,v.co.y*diam*.43,v.co.z*diam*.46));p*=1+.07*math.sin(v.index*1.43+i);vs.append(tuple(p+center))
        faces=[tuple(p.vertices) for p in tmp.data.polygons];bpy.data.objects.remove(tmp,do_unlink=True)
        ob=C.mesh('EditableEmbeddedAggregate_%02d'%i,vs,faces,mat)
        for face in ob.data.polygons:face.use_smooth=True
        # Signed side test against the actual slab BVH; both buried and exposed points required.
        distances=[]
        for v in ob.data.vertices:
            p,n,idx,d=slabtree.find_nearest(v.co);assert p is not None
            distances.append((v.co-p).dot(n))
        contacts.append({'name':ob.name,'diameter_design_m':diam,'signed_surface_offsets_m':[min(distances),max(distances)]})
        assert min(distances)<-.0005 and max(distances)>.0005,contacts[-1]
        out.append(ob)
    return out,contacts

def fragment(mat,tree):
    poly=[(-.056,-.038),(.051,-.043),(.064,.015),(.008,.046),(-.047,.029)];n=len(poly)
    verts=[(x,z,0) for x,z in poly]+[(x*.95,z*.92,-.065) for x,z in poly]
    rot=Matrix.Rotation(.41,3,'Z') @ Matrix.Rotation(.23,3,'X')
    coords=[rot@Vector((x,-z,y)) for x,z,y in verts]
    px,pz=.25,.43
    shift=C.ray_height(tree,px,pz)-min(p.z for p in coords)-.012
    coords=[tuple(p+Vector(C.bp(px,shift,pz))) for p in coords]
    fs=[tuple(range(n)),tuple(reversed(range(n,2*n)))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    ob=C.mesh('EditableFallenConcreteChip',coords,fs,mat)
    for face in ob.data.polygons:
        former_top=face.index==0
        for li in face.loop_indices:ob.data.color_attributes['SurfaceControl'].data[li].color=(.15,0 if former_top else .8,1 if former_top else 0,1)
    ds=[]
    for v in ob.data.vertices:
        x,y,z=C.gp(v.co);ds.append(y-C.ray_height(tree,x,z))
    assert min(ds)<-.002 and max(ds)>.008,ds
    return ob,{'name':ob.name,'actual_ground_offsets_m':[min(ds),max(ds)]}

def main():
    started=time.monotonic();C.verify_frozen();bpy.ops.wm.read_factory_settings(use_empty=True)
    # Reuse the frozen concrete recipe and original atlas, without executing its entrypoint.
    spec=importlib.util.spec_from_file_location('read_only_concrete_recipe',C.HERE.parent/'p3/build_asset.py');H=importlib.util.module_from_spec(spec);spec.loader.exec_module(H)
    atlas=C.load_image(C.CFG['concrete_atlas'],'sRGB');cement=H.author('concrete',atlas);C.add_ao(cement)
    soil=C.make_scan_material();mineral=C.make_scan_material(True)
    high_edit=ground(soil,True);low_edit=ground(soil,False);bpy.context.view_layer.update()
    high=C.evaluated(high_edit,'HighGround');low=C.evaluated(low_edit,'LowGround')
    slab=concrete(cement);aggs,contacts=aggregate(mineral,C.actual_tree(slab));chip,chipcontact=fragment(cement,C.actual_tree(high))
    solids=[slab,*aggs,chip];hs=C.joined_copy(solids,'HighSolids');ls=C.joined_copy(solids,'LowSolids')
    uv=[C.unwrap(low,.015,.65),C.unwrap(ls,.68,.985)]
    highfull=C.joined_copy([high,hs],'HighFull');lowfull=C.joined_copy([low,ls],'LowFull')
    rows=[C.geometry(o) for o in [high,low,slab,*aggs,chip,highfull,lowfull]]
    C.write('geometry_report.json',{'objects':rows,'contacts':contacts+[chipcontact],'UV':uv,'fixed_config':C.CFG,'executed_pid':os.getpid(),
        'self_intersection_scope':'No universal triangle-intersection claim: ground uses a single-valued vertical displacement field with unchanged XZ, solids are closed separately; aggregate/slab embedding is intentional. Actual triangle intersections beyond these construction/closure checks remain untested.',
        'collision':'Source method study only, not a game collider or landing validation.'})
    for r in rows:assert r['nonmanifold_edges']==0 and r['volume_m3']>0 and r['minimum_triangle_area_m2']>1e-15,r
    full=rows[-1]['bounds'];assert full['min'][0]>=-.450001 and full['max'][0]<=.450001 and full['min'][2]>=-1e-6 and full['max'][2]<=.900001,full
    htree,ltree=C.actual_tree(high),C.actual_tree(low);deviations=[];sections=[]
    for z in (.36,.50,.66,.80):
        row=[]
        for i in range(75):
            x=-.37+i*.01;hh=C.ray_height(htree,x,z);lh=C.ray_height(ltree,x,z);row.append([x,hh,lh]);deviations.append(abs(hh-lh))
        sections.append({'z':z,'actual_high_low_samples':row,'high_span_m':max(r[1] for r in row)-min(r[1] for r in row)})
    C.write('actual_sections.json',{'sections':sections,'high_low_max_vertical_difference_m':max(deviations),'not_an_art_pass_threshold':True})
    C.studio();C.show([highfull]);before=C.images_report();C.write('image_preflight.json',before)
    path=C.OUT/'editable_checkpoint.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
    digest=C.sha(path);bpy.ops.wm.open_mainfile(filepath=str(path));after=C.images_report()
    assert {(r['absolute_path'],r['sha256'],tuple(r['size'])) for r in before}=={(r['absolute_path'],r['sha256'],tuple(r['size'])) for r in after}
    C.verify_frozen();C.write('stage_a_result.json',{'status':'CHECKPOINT_VALID_NOT_VISUALLY_APPROVED','pid':os.getpid(),'seconds':time.monotonic()-started,'source':str(path),'sha256':digest,'high_triangles':rows[-2]['triangles'],'low_triangles':rows[-1]['triangles'],'images':after,'rendered':False,'exported':False})
    print('STAGE_A_COMPLETE',os.getpid(),flush=True)

if __name__=='__main__':main()
