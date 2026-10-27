from pathlib import Path
import bpy,json,numpy as np,hashlib,os
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
BASE=ROOT/'asset_sources/v3/growth_approach/resource_recovery'
bpy.ops.wm.read_factory_settings(use_empty=True)
rows=[]
print('FOUNDATION_P2_INSPECT_PID',os.getpid(),flush=True)
for aid,name in [('boulder_01','boulder_01_LOD3'),('namaqualand_boulder_03','namaqualand_boulder_03_LOD3')]:
 p=BASE/aid/(aid+'_1k.blend')
 with bpy.data.libraries.load(str(p),link=False) as (src,dst):
  assert name in src.objects;dst.objects=[name]
 ob=dst.objects[0];bpy.context.scene.collection.objects.link(ob)
 coords=np.array([tuple(ob.matrix_world@v.co) for v in ob.data.vertices],dtype=float)
 centre=coords.mean(axis=0);values,basis=np.linalg.eigh(np.cov((coords-centre).T));basis=basis[:,np.argsort(values)[::-1]]
 if np.linalg.det(basis)<0:basis[:,2]*=-1
 principal=(coords-centre)@basis
 ob.data.calc_loop_triangles()
 rows.append({'asset':aid,'object':name,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'matrix':[list(r) for r in ob.matrix_world],'modifiers':[m.name for m in ob.modifiers],'vertices':coords.tolist(),'triangles':[list(t.vertices) for t in ob.data.loop_triangles],'centre':centre.tolist(),'principal_basis_columns':basis.tolist(),'principal_bounds':[principal.min(axis=0).tolist(),principal.max(axis=0).tolist()],'principal_extents':np.ptp(principal,axis=0).tolist()})
 print(aid,'bounds',coords.min(axis=0),coords.max(axis=0),'PCA',np.ptp(principal,axis=0),flush=True)
(HERE/'native_mesh_read.json').write_text(json.dumps(rows,ensure_ascii=False),encoding='utf-8')
