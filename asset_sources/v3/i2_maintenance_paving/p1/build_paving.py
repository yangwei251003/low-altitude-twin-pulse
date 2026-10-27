"""Source preparation only; root must grant a CPU2 window before execution.

Reuse frozen courtyard geometry/UV helpers and its author-channel bake protocol.
This entry does NOT bake, export GLB, write runtime assets, or start Godot.
Coordinates are Godot x/y/z, converted to Blender x/-z/y exactly once.
"""
from pathlib import Path
import sys, importlib.util, json, hashlib, math, time, os
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.dont_write_bytecode = True
CFG = json.loads((HERE / 'contract.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('frozen_courtyard_uv', ROOT / 'asset_sources/v3/clinic_ground/plain_v1/build_plain.py')
UV = importlib.util.module_from_spec(spec)
spec.loader.exec_module(UV)
H = UV.H
H.SRC = HERE
H.PIECES = []
H.AUTHORS = []
H.CHECKS = []
REPORT = {'status': 'PREPARED_NOT_RUN', 'checks': [], 'variants': [], 'limits': [
    'Source-only preview; no runtime collision or gameplay validation.',
    'Checks cover individual closed solids, dimensions, seams and surface probes; not an exhaustive inter-part intersection proof.',
    'Author materials reuse courtyard input bytes; native four-channel baking is a later approved stage.']}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def frozen_inputs():
    for rel, info in CFG['frozen_inputs'].items():
        assert sha(ROOT / rel) == info['sha256'], 'Frozen input changed: ' + rel


def check(name, ok, detail=None):
    REPORT['checks'].append({'name': name, 'passed': bool(ok), 'detail': detail})


def bg(p):
    return (p[0], -p[2], p[1])


def gd(p):
    return (float(p[0]), float(p[2]), float(-p[1]))


def rect_solid(name, rect, bottom, top, material, group, holes=(), bevel=0):
    """Closed rectilinear extrusion with real through-holes, no overlapping caps.

    Shared grid vertices and absent internal vertical faces retain a single
    watertight solid. The holes are not dark decals. No Boolean dependencies.
    """
    x0, x1, z0, z1 = rect
    xs = sorted({x0, x1} | {h[i] for h in holes for i in (0, 1)})
    zs = sorted({z0, z1} | {h[i] for h in holes for i in (2, 3)})
    assert all(x0 < h[0] < h[1] < x1 and z0 < h[2] < h[3] < z1 for h in holes)
    occupied = set()
    for i in range(len(xs)-1):
        for j in range(len(zs)-1):
            x, z = (xs[i]+xs[i+1])/2, (zs[j]+zs[j+1])/2
            if not any(h[0] < x < h[1] and h[2] < z < h[3] for h in holes):
                occupied.add((i, j))
    vertices, faces, lookup = [], [], {}
    def vi(i, j, upper):
        key = (i, j, upper)
        if key not in lookup:
            lookup[key] = len(vertices)
            vertices.append(bg((xs[i], top if upper else bottom, zs[j])))
        return lookup[key]
    for i, j in sorted(occupied):
        ring = [(i,j), (i+1,j), (i+1,j+1), (i,j+1)]
        faces.append(tuple(vi(a,b,1) for a,b in ring))
        faces.append(tuple(vi(a,b,0) for a,b in reversed(ring)))
        for edge, neighbor in zip(range(4), [(i,j-1),(i+1,j),(i,j+1),(i-1,j)]):
            if neighbor in occupied:
                continue
            a,b = ring[edge], ring[(edge+1)%4]
            faces.append((vi(*a,0),vi(*b,0),vi(*b,1),vi(*a,1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if bevel:
        mod = obj.modifiers.new('InwardManufacturingBevel', 'BEVEL')
        mod.width = bevel; mod.segments = 1; mod.limit_method = 'ANGLE'
    H.finish(obj, material, group)
    return obj


def author(name, kind, images, atlas, marked=False, salt=False):
    """Same author record format as courtyard H.bake_and_apply.

    Explicit SourceUV survives a future SurfaceUV unwrap. Object-space masks
    use a dedicated root coordinate object, never per-piece Generated bounds.
    """
    g = H.Graph(name); n, link = g.n, g.l
    uv = n.new('ShaderNodeUVMap'); uv.uv_map = 'SourceUV'
    tex = n.new('ShaderNodeTexImage'); tex.image = images['BaseColor']; tex.label = 'Frozen courtyard clean concrete'
    link.new(uv.outputs['UV'], tex.inputs['Vector'])
    coord = n.new('ShaderNodeTexCoord'); coord.label = 'Stable module coordinates, assigned per variant'
    sep = n.new('ShaderNodeSeparateXYZ'); link.new(coord.outputs['Object'], sep.inputs[0])
    x, z = sep.outputs['X'], g.op('MULTIPLY', sep.outputs['Y'], -1)
    geo = n.new('ShaderNodeNewGeometry'); norm = n.new('ShaderNodeSeparateXYZ'); link.new(geo.outputs['Normal'], norm.inputs[0])
    top = g.op('GREATER_THAN', norm.outputs['Z'], .7)
    if kind in ('concrete', 'repair'):
        neutral = (.125,.143,.150,1) if kind == 'concrete' else (.19,.195,.184,1)
        base = g.mix(neutral, g.color_mult(tex.outputs['Color'], (.46,.49,.50,1)), .20)
        rough, metal = .84, 0
        if kind == 'concrete':
            # One short pair of wheel scuffs, not tyre tracks repeated on every tile.
            if marked:
                wheel = g.op('MAXIMUM', g.rectangle(x,z,.15,.38,.10,.65), g.rectangle(x,z,.75,.35,.10,.73))
                base = g.mix(base, g.color_mult(base,(.75,.77,.78,1)), g.op('MULTIPLY',top,g.op('MULTIPLY',wheel,.40)))
                line = g.rectangle(x,z,-.46,.15,.035,.90)
                gap = g.rectangle(x,z,-.46,.15,.06,.12)
                line = g.op('MULTIPLY',line,g.op('SUBTRACT',1,gap))
                base = g.mix(base,(.43,.285,.08,1),g.op('MULTIPLY',top,line))
            if salt:
                # Only two short deposits beside the actual north/south seal.
                deposit = g.rectangle(x,z,-1.75,-1.94,.26,.035)
                base = g.mix(base,(.22,.235,.224,1),g.op('MULTIPLY',top,g.op('MULTIPLY',deposit,.22)))
    elif kind == 'teal':
        base, rough, metal = (.065,.155,.155,1), .68, .12
        # Read-only original industrial atlas, projected at metre scale.
        mapping = n.new('ShaderNodeCombineXYZ')
        link.new(g.op('ADD',.025,g.op('MULTIPLY',g.op('PINGPONG',x,1),.45)), mapping.inputs['X'])
        link.new(g.op('ADD',.025,g.op('MULTIPLY',g.op('PINGPONG',z,1),.45)), mapping.inputs['Y'])
        steel = n.new('ShaderNodeTexImage'); steel.image = atlas; steel.extension='EXTEND'
        link.new(mapping.outputs[0],steel.inputs['Vector'])
        base = g.mix(base,g.color_mult(steel.outputs['Color'],(.38,.48,.46,1)),.16)
    elif kind == 'steel':
        base, rough, metal = (.19,.22,.23,1), .56, .65
    else:
        base, rough, metal = (.035,.043,.046,1), .94, 0
    bs = n.new('ShaderNodeBsdfPrincipled'); g.value(base,bs.inputs['Base Color']); g.value(rough,bs.inputs['Roughness']); g.value(metal,bs.inputs['Metallic'])
    bs.inputs['Emission Strength'].default_value = 0
    if kind in ('concrete','repair'):
        normal = n.new('ShaderNodeTexImage'); normal.image=images['Normal']; link.new(uv.outputs['UV'],normal.inputs['Vector'])
        nm=n.new('ShaderNodeNormalMap'); nm.uv_map='SourceUV'; nm.inputs['Strength'].default_value=.06
        link.new(normal.outputs['Color'],nm.inputs['Color']); link.new(nm.outputs['Normal'],bs.inputs['Normal'])
    em=n.new('ShaderNodeEmission'); em.inputs['Strength'].default_value=1
    out=n.new('ShaderNodeOutputMaterial'); link.new(bs.outputs['BSDF'],out.inputs['Surface'])
    H.AUTHORS.append({'material':g.m,'graph':g,'bsdf':bs,'emission':em,'output':out,'channels':{'BaseColor':base,'Roughness':rough,'Metallic':metal}})
    return g.m, coord


def build_variant(row, images, atlas):
    label=row['id']; H.PIECES=[]
    coll=bpy.data.collections.new('Editable_'+label); bpy.context.scene.collection.children.link(coll)
    root=bpy.data.objects.new('MaintenancePaving_'+label,None); coll.objects.link(root)
    root['origin_contract']='Godot top centre; X5m Z4m Y[-.18,0]'
    mats={}; coords=[]
    for kind in ['concrete','repair','teal','steel','seal']:
        mat, coord=author('SOURCE_'+label+'_'+kind,kind,images,atlas,row['entry_mark'],row['local_salt'])
        mats[kind]=mat; coords.append(coord)
    for coord in coords:coord.object=root
    widths={edge:(.01 if mode=='pair_half' else .02) for edge,mode in row['edges'].items()}
    x0,x1=-2.5+widths['west'],2.5-widths['east']
    z0,z1=-2+widths['north'],2-widths['south']
    rect_solid(label+'_FullBearingBed',(-2.5,2.5,-2,2),-.18,-.05,mats['concrete'],'ConcreteFields')
    edges={'west':(-2.5,x0,-2,2),'east':(x1,2.5,-2,2),'north':(x0,x1,-2,z0),'south':(x0,x1,z1,2)}
    for side,rect in edges.items():rect_solid(label+'_BoundarySeal_'+side,rect,-.05,-.012,mats['seal'],'SealsAndBeds')
    limit=2.0 if row['inspection_band'] else x1
    fields=[('NW',(x0,-.56,z0,-.47)),('SW',(x0,-.56,-.45,z1)),('NE',(-.54,limit,z0,.74)),('SE',(-.54,limit,.76,z1))]
    for name,rect in fields:
        holes=[(-2.10,-.82,-1.40,-.72)] if row['repair'] and name=='NW' else []
        rect_solid(label+'_Pour_'+name,rect,-.05,0,mats['concrete'],'ConcreteFields',holes,.003)
        if holes:
            h=holes[0]; inset=.008
            inner=(h[0]+inset,h[1]-inset,h[2]+inset,h[3]-inset)
            rect_solid(label+'_SawcutSeal',h,-.05,-.012,mats['seal'],'SealsAndBeds',[inner])
            rect_solid(label+'_SawcutRefill',inner,-.05,-.001,mats['repair'],'ConcreteFields',bevel=.001)
    for name,rect in [('Long',(-.56,-.54,z0,z1)),('WestT',(x0,-.56,-.47,-.45)),('EastT',(-.54,limit,.74,.76))]:
        rect_solid(label+'_InternalSeal_'+name,rect,-.05,-.012,mats['seal'],'SealsAndBeds')
    if row['inspection_band']:
        # Common world x19.02..19.47 spine, independent of row edge modes.
        rect_solid(label+'_BandLeftSeal',(2.0,2.02,z0,z1),-.05,-.012,mats['seal'],'SealsAndBeds')
        # A narrow solid concrete edge keeps the separate module seam exactly
        # 20mm visually as well as numerically; do not append a second dark seal.
        rect_solid(label+'_BandEdgeConcrete',(2.47,x1,z0,z1),-.05,0,mats['concrete'],'ConcreteFields')
        rect_solid(label+'_BandBed',(2.02,2.47,z0,z1),-.05,-.04,mats['seal'],'InspectionBand')
        spans=[(z0,-.70),(-.70,.62),(.62,z1)]
        for index,(za,zb) in enumerate(spans):
            # Frame encloses actual solid cover; no open grate/imaginary drain.
            lid=(2.044,2.446,za+.024,zb-.024)
            rect_solid(f'{label}_CoverFrame{index}',(2.02,2.47,za,zb),-.04,-.002,mats['teal'],'InspectionBand',[lid],.001)
            body=(lid[0]+.004,lid[1]-.004,lid[2]+.004,lid[3]-.004)
            cx,cz=(body[0]+body[1])/2,(body[2]+body[3])/2
            holes=[(cx-.055,cx+.055,cz-.023,cz+.023)]
            holes += [(cx-.014,cx+.014,zz-.014,zz+.014) for zz in (body[2]+.07,body[3]-.07)]
            rect_solid(f'{label}_SolidCover{index}',body,-.025,-.004,mats['teal'],'InspectionBand',holes,.001)
            for hindex,hole in enumerate(holes):
                rect_solid(f'{label}_PocketFloor{index}_{hindex}',hole,-.04,-.031,mats['seal'],'InspectionBand')
            rect_solid(f'{label}_RecessedGrip{index}',(cx-.049,cx+.049,cz-.007,cz+.007),-.031,-.017,mats['steel'],'InspectionBand',bevel=.001)
            for bi,zz in enumerate((body[2]+.07,body[3]-.07)):
                bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.011,depth=.025,location=bg((cx,-.0185,zz)))
                obj=bpy.context.object; obj.name=f'{label}_CountersunkFastener{index}_{bi}'
                H.finish(obj,mats['steel'],'InspectionBand')
    parts=list(H.PIECES)
    for obj in parts:
        UV.apply_metric_uv(obj,row['uv_offset_xz'],'Seal' in obj.name)
        uv=obj.data.uv_layers.new(name='SourceUV')
        for a,b in zip(uv.data,obj.data.uv_layers['SurfaceUV'].data):a.uv=b.uv
        obj.data.uv_layers.active_index=0; obj.data.uv_layers['SurfaceUV'].active_render=True
        obj['variant']=label
        for old in list(obj.users_collection):old.objects.unlink(obj)
        coll.objects.link(obj); obj.parent=root; obj.matrix_basis=Matrix.Identity(4)
    return {'row':row,'root':root,'collection':coll,'parts':parts,'widths':widths}


def inspect(v):
    label=v['row']['id']; vertices=[]; triangles=[]; records=[]
    for obj in v['parts']:
        me=obj.data; me.calc_loop_triangles(); bm=bmesh.new(); bm.from_mesh(me)
        bad=sum(not e.is_manifold for e in bm.edges); vol=bm.calc_volume(signed=True); bm.free()
        zero=sum(t.area<1e-12 for t in me.loop_triangles)
        points=[gd(p.co) for p in me.vertices]
        bb=[[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]
        offset=len(vertices); vertices += [p.co.copy() for p in me.vertices]
        triangles += [tuple(offset+i for i in t.vertices) for t in me.loop_triangles]
        records.append({'name':obj.name,'group':obj['runtime_group'],'bounds':bb,'triangles':len(me.loop_triangles),'signed_volume':vol,'nonmanifold_edges':bad,'zero_area_triangles':zero})
        check(obj.name+' closed positive finite solid',bad==0 and vol>1e-12 and zero==0)
        check(obj.name+' finite explicit source and future bake UV',set(me.uv_layers.keys())=={'SourceUV','SurfaceUV'} and all(math.isfinite(c) and 0<=c<=1 for layer in me.uv_layers for u in layer.data for c in u.uv))
    points=[gd(p) for p in vertices]
    bb=[[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]
    check(label+' exact 5x4 top0 bounds',all(abs(bb[k][a]-[[-2.5,-.18,-2],[2.5,0,2]][k][a])<2e-6 for k in range(2) for a in range(3)),bb)
    check(label+' triangle budget <=4000',len(triangles)<=4000,len(triangles))
    for rec in records:
        if rec['group']=='InspectionBand':check(rec['name']+' hardware strictly below Y0',rec['bounds'][1][1]<-1e-5,rec['bounds'])
    bvh=BVHTree.FromPolygons(vertices,triangles,all_triangles=True)
    probes=[(-1.8,1.2,0),(.5,-1.2,0),(.5,1.2,0),(-2.5+v['widths']['west']/2,0,-.012),(2.5-v['widths']['east']/2,0,-.012),(0,-2+v['widths']['north']/2,-.012),(0,2-v['widths']['south']/2,-.012)]
    if v['row']['repair']:probes += [(-1.4,-1.05,-.001),(-2.096,-1.05,-.012)]
    if v['row']['inspection_band']:probes += [(2.10,-1.25,-.004),(2.245,(-2+v['widths']['north']-.70)/2,-.017)]
    actual=[]
    for x,z,y in probes:
        hit=bvh.ray_cast(Vector(bg((x,1,z))),Vector((0,0,-1)),2)[0]
        actual.append({'xz':[x,z],'expected_y':y,'actual_y':float(hit.z) if hit else None})
    check(label+' actual bearing/seal/cover/grip ray heights',all(p['actual_y'] is not None and abs(p['actual_y']-p['expected_y'])<3e-6 for p in actual),actual)
    edges={}
    for side in v['widths']:
        r=next(r for r in records if r['name'].endswith('_BoundarySeal_'+side))
        axis=0 if side in ('west','east') else 2
        edges[side]=r['bounds'][1][axis]-r['bounds'][0][axis]
        check(label+' '+side+' actual seam width',abs(edges[side]-v['widths'][side])<3e-7,edges[side])
    return {'id':label,'bounds':bb,'triangles':len(triangles),'parts':records,'edges':edges,'probes':actual}


def review_copy(v, at):
    root=bpy.data.objects.new('REVIEW_'+v['row']['id'],None); bpy.context.scene.collection.objects.link(root); root.location=bg((at[0],0,at[1]))
    # Original root is retained as stable material coordinate reference: sharing
    # root coordinates after translation would move masks. Copy material nodes.
    copies={}
    for obj in v['parts']:
        new=bpy.data.objects.new('REVIEW_'+obj.name,obj.data.copy()); bpy.context.scene.collection.objects.link(new); new.parent=root
        for i,mat in enumerate(new.data.materials):
            if mat.name not in copies:
                copied=mat.copy(); copies[mat.name]=copied
                for node in copied.node_tree.nodes:
                    if node.type=='TEX_COORD':node.object=root
            new.data.materials[i]=copies[mat.name]
    return root


def check_assembled_boundaries(variants):
    """Use actual model vertices in their proposed metre-grid placement.

    Four explicit flat quads represent the untouched old Y0 ground immediately
    outside the patch. They are a seam test fixture, not the production World.
    """
    verts=[]; tris=[]
    for v in variants.values():
        x,z=v['row']['center_xz']; translation=Vector(bg((x,0,z)))
        for obj in v['parts']:
            me=obj.data; me.calc_loop_triangles(); start=len(verts)
            verts.extend([p.co+translation for p in me.vertices])
            tris.extend([tuple(start+i for i in t.vertices) for t in me.loop_triangles])
    for x0,x1,z0,z1 in [(14,14.5,-14.5,2.5),(24.5,25,-14.5,2.5),(14.5,24.5,-14.5,-14),(14.5,24.5,2,2.5)]:
        start=len(verts); verts.extend([Vector(bg((x,0,z))) for x,z in [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]])
        tris.extend([(start,start+1,start+2),(start,start+2,start+3)])
    bvh=BVHTree.FromPolygons(verts,tris,all_triangles=True)
    samples=[]
    # Interior seam in both axes, and B+old flat in both axes.
    # Keep samples clear of the deliberately separate T-joints and service band.
    for x,z,y in [(19.48,-11,0),(19.492,-11,-.012),(19.508,-11,-.012),(19.52,-11,0),
                  (22,-10.02,0),(22,-10.008,-.012),(22,-9.992,-.012),(22,-9.98,0),
                  (14.495,-11,0),(14.505,-11,-.012),(14.515,-11,-.012),(14.53,-11,0),
                  (22,2.005,0),(22,1.995,-.012),(22,1.985,-.012),(22,1.97,0)]:
        hit=bvh.ray_cast(Vector(bg((x,1,z))),Vector((0,0,-1)),2)[0]
        samples.append({'world_xz':[x,z],'expected_y':y,'actual_y':float(hit.z) if hit else None})
    check('actual assembly A+A and B+flat boundary first-hit profiles',all(s['actual_y'] is not None and abs(s['actual_y']-s['expected_y'])<5e-6 for s in samples),samples)


def main():
    start=time.time(); frozen_inputs()
    blend=HERE/'maintenance_paving_p1.blend'
    assert not blend.exists(), 'Never overwrite a completed source attempt.'
    (HERE/'evidence').mkdir(exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
    scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.render.threads_mode='FIXED'; scene.render.threads=2
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
    data=json.loads((ROOT/'asset_sources/v3/clinic_ground/p2/evidence/production_report.json').read_text(encoding='utf-8'))
    images={}
    for row in data['baked_maps']:
        image=bpy.data.images.load(row['path'],check_existing=False); image.colorspace_settings.name=row['colorspace']; images[row['role']]=image
    atlas=bpy.data.images.load(str(ROOT/'asset_sources/v3/clinic_ground/p1/source_inputs/material_atlas_UNEDITED.png'),check_existing=False); atlas.colorspace_settings.name='sRGB'
    variants={}
    for row in CFG['tiles']:
        variant=build_variant(row,images,atlas); variants[row['id']]=variant
        REPORT['variants'].append(inspect(variant))
    # Actual constructed seam bounds, not nominal dimension assertions alone.
    indexed={r['id']:r for r in REPORT['variants']}
    for a in CFG['tiles']:
        for b in CFG['tiles']:
            dx=b['center_xz'][0]-a['center_xz'][0]; dz=b['center_xz'][1]-a['center_xz'][1]
            edges=('east','west') if dx==5 and dz==0 else (('south','north') if dz==4 and dx==0 else None)
            if edges:
                width=indexed[a['id']]['edges'][edges[0]]+indexed[b['id']]['edges'][edges[1]]
                check(a['id']+' to '+b['id']+' paired seam20mm',abs(width-.02)<5e-7,width)
    for row in CFG['tiles']:
        for side,mode in row['edges'].items():
            if mode=='outer_full':check(row['id']+' '+side+' flush existing-ground full20mm',abs(indexed[row['id']]['edges'][side]-.02)<3e-7)
    check_assembled_boundaries(variants)
    REPORT['status']='GEOMETRY_CHECKED_NOT_RENDERED'
    report_path=HERE/'evidence/production_report.json'; report_path.write_text(json.dumps(REPORT,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not all(c['passed'] for c in REPORT['checks']):
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'),relative_remap=False)
        raise RuntimeError('Source geometry gate failed; retained report/blend, no render.')
    H.studio(); scene.cycles.samples=16; scene.render.resolution_x=1280; scene.render.resolution_y=960
    for label,v in variants.items():v['collection'].hide_render=label!='W1'; v['collection'].hide_viewport=label!='W1'
    scene.camera.data.ortho_scale=8.0
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    out=HERE/'evidence/maintenance_single_p1.png'; scene.render.filepath=str(out); bpy.ops.render.render(write_still=True)
    previews=[{'path':str(out),'sha256':sha(out),'scope':'Offline source preview, not game'}]
    for v in variants.values():v['collection'].hide_render=True
    for row in CFG['tiles']:review_copy(variants[row['id']],(row['center_xz'][0]-19.5,row['center_xz'][1]+6))
    scene.render.resolution_x=1536; scene.render.resolution_y=864; scene.camera.data.ortho_scale=24.5
    out=HERE/'evidence/maintenance_eight_tile_layout_p1.png'; scene.render.filepath=str(out); bpy.ops.render.render(write_still=True)
    previews.append({'path':str(out),'sha256':sha(out),'scope':'Offline eight-tile surface assembly, no game obstacles'})
    frozen_inputs()
    REPORT.update(status='SOURCE_RENDERED_AWAITING_ROOT_REVIEW',previews=previews,blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
    report_path.write_text(json.dumps(REPORT,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'done','pid':os.getpid(),'seconds':time.time()-start,'failed':sum(not c['passed'] for c in REPORT['checks'])}),flush=True)


if __name__=='__main__':
    main()
