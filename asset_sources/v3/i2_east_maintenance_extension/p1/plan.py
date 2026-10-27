"""Metre geometry only. No Blender/Godot import, image edit or production write."""
from pathlib import Path
from collections import Counter
import json, hashlib, math

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ORIGIN = (20.7, 0., 8.8)
OUTER = (16.9, 24.5, 2., 15.6)
BANK = (16.9, 17.25, 2.3, 15.6)
HOLE_IDS = ('EastFoot1', 'EastFoot2', 'EastTrackPier1', 'EastTrackPier2', 'ServiceSocketPost')
INPUTS = [
 'data/v3/terrain/i2_shared_access_layout.json',
 'asset_sources/v3/i2_maintenance_paving/p3/maintenance_paving_p3.blend',
 'asset_sources/v3/i2_maintenance_paving/p3/build_material_p3.py',
 'asset_sources/v3/i2_maintenance_paving/p2/build_paving.py',
 'references/v3/production/i2_maintenance_paving/material_v2/maintenance_concrete_basecolor_v1.png',
 'references/v3/production/shared_access_bridge_deck/painted_steel_material_v1.png',
 'references/v3/production/i2_maintenance_paving/maintenance_paving_reference_v1.png',
 'references/v3/concepts/I-B.png',
 'asset_sources/v3/i2_maintenance_paving/p2/source_inputs/maintenance_concrete_basecolor_v1.png',
 'asset_sources/v3/i2_maintenance_paving/p3/source_inputs/painted_steel_material_v1.png',
 *['asset_sources/v3/clinic_ground/p2/textures/CGround_'+role+'.png' for role in ['BaseColor','Normal','Roughness','Metallic']],
]

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def area(r): return (r[1]-r[0])*(r[3]-r[2])
def inside(x,z,r): return r[0] < x < r[1] and r[2] < z < r[3]
def expand(r,d): return (r[0]-d,r[1]+d,r[2]-d,r[3]+d)
def bg(p): return (p[0]-ORIGIN[0], -p[2]+ORIGIN[2], p[1]-ORIGIN[1])

def facts():
 d=json.loads((ROOT/INPUTS[0]).read_text(encoding='utf-8'))
 assert d['origin']==[0,0,0]
 specs={r['id']:r for r in d['fixed']}; holes=[]
 for name in HOLE_IDS:
  s=specs[name]; c=s['center']; size=s['size']
  lo=[round(c[i]-size[i]/2,8) for i in range(3)]
  hi=[round(c[i]+size[i]/2,8) for i in range(3)]
  assert lo[1]==0 and hi[1]>0
  holes.append({'id':name,'rect':[lo[0],hi[0],lo[2],hi[2]],'min':lo,'max':hi})
 assert abs(sum(area(h['rect']) for h in holes)-1.16)<1e-8
 return holes

def grid_mesh(name, xs, zs, cells, bottom, top, role):
 """Single closed rectilinear extrusion, no internal stacked caps or Boolean."""
 cells=set(cells); verts=[]; faces=[]; ids={}
 def vi(i,j,upper,owner):
  # Diagonal strips may meet at a point. Keep their local vertex fans separate
  # instead of welding them into a four-face nonmanifold vertical edge.
  local={(a,b) for a in [i-1,i] for b in [j-1,j] if (a,b) in cells}
  fan={owner}; pending=[owner]
  while pending:
   a,b=pending.pop()
   for neighbor in [(a-1,b),(a+1,b),(a,b-1),(a,b+1)]:
    if neighbor in local and neighbor not in fan: fan.add(neighbor);pending.append(neighbor)
  key=(i,j,upper,min(fan))
  if key not in ids:
   ids[key]=len(verts); verts.append(bg((xs[i],top if upper else bottom,zs[j])))
  return ids[key]
 for i,j in sorted(cells):
  ring=[(i,j),(i,j+1),(i+1,j+1),(i+1,j)]
  faces.append([vi(a,b,1,(i,j)) for a,b in ring]); faces.append([vi(a,b,0,(i,j)) for a,b in reversed(ring)])
  for edge,neighbor in enumerate([(i-1,j),(i,j+1),(i+1,j),(i,j-1)]):
   if neighbor in cells: continue
   a,b=ring[edge],ring[(edge+1)%4]
   faces.append([vi(*a,0,(i,j)),vi(*b,0,(i,j)),vi(*b,1,(i,j)),vi(*a,1,(i,j))])
 edges=Counter(tuple(sorted((f[k],f[(k+1)%len(f)]))) for f in faces for k in range(len(f)))
 assert verts and all(n==2 for n in edges.values()), name+' nonmanifold edge'
 return {'name':name,'vertices':verts,'faces':faces,'role':role,
         'top_area':sum((xs[i+1]-xs[i])*(zs[j+1]-zs[j]) for i,j in cells),'top':top}

def rect_mesh(name, rect, bottom, top, role, holes=()):
 xs=sorted({rect[0],rect[1]}|{v for h in holes for v in h[:2]})
 zs=sorted({rect[2],rect[3]}|{v for h in holes for v in h[2:]})
 cells=[(i,j) for i in range(len(xs)-1) for j in range(len(zs)-1)
        if not any(inside((xs[i]+xs[i+1])/2,(zs[j]+zs[j+1])/2,h) for h in holes)]
 return grid_mesh(name,xs,zs,cells,bottom,top,role)

def build():
 holes=facts(); rings=[expand(h['rect'],.012) for h in holes]
 xs={16.9,16.92,17.25,17.27,19.,19.02,19.47,19.49,21.49,21.51,24.48,24.5}
 zs={2.,2.28,2.3,5.09,5.11,6.89,6.91,7.79,7.81,9.99,10.01,11.29,11.31,12.19,12.21,15.58,15.6}
 for r in [h['rect'] for h in holes]+rings: xs.update(r[:2]); zs.update(r[2:])
 xs=sorted(x for x in xs if OUTER[0]<=x<=OUTER[1]); zs=sorted(z for z in zs if OUTER[2]<=z<=OUTER[3])
 occupied=[]; groups={}
 for i in range(len(xs)-1):
  for j in range(len(zs)-1):
   x,z=(xs[i]+xs[i+1])/2,(zs[j]+zs[j+1])/2
   if inside(x,z,BANK) or any(inside(x,z,h['rect']) for h in holes): continue
   occupied.append((i,j))
   boundary=(x>24.48 or z>15.58 or (z<2.3 and (x<16.92 or (x<17.25 and z>2.28))) or (z>2.3 and x<17.27))
   collar=any(inside(x,z,r) for r in rings)
   band=19.02<x<19.47
   spine=19.<x<19.02 or 19.47<x<19.49 or 21.49<x<21.51
   cut=(x<19 and (6.89<z<6.91 or 11.29<z<11.31)) or (19.49<x<21.49 and 5.09<z<5.11 or 19.49<x<21.49 and 9.99<z<10.01) or (x>21.51 and (7.79<z<7.81 or 12.19<z<12.21))
   if boundary or collar or spine or cut: group='ShallowSeals'
   elif band: group='InspectionBed'
   else:
    strip='Bank' if x<19 else 'Service' if x<21.49 else 'ClearRoute'
    levels={'Bank':[6.9,11.3],'Service':[5.1,10.],'ClearRoute':[7.8,12.2]}[strip]
    group=strip+str(sum(z>q for q in levels))
   groups.setdefault(group,[]).append((i,j))
 parts=[grid_mesh('FullBearingBed',xs,zs,occupied,-.18,-.05,'concrete')]
 for name,cells in groups.items():
  top=-.012 if name=='ShallowSeals' else -.04 if name=='InspectionBed' else 0
  parts.append(grid_mesh(name,xs,zs,cells,-.05,top,'seal' if name in ['ShallowSeals','InspectionBed'] else 'concrete'))
 # The same 450mm-wide editable recessed-cover construction as the approved
 # maintenance bay, extended at metre scale rather than stretching its GLB.
 lids=[]
 for n in range(10):
  za=2+(15.58-2)*n/10; zb=2+(15.58-2)*(n+1)/10
  opening=(19.044,19.446,za+.024,zb-.024)
  body=(opening[0]+.004,opening[1]-.004,opening[2]+.004,opening[3]-.004)
  cx=(body[0]+body[1])/2; cz=(body[2]+body[3])/2
  pocket=(cx-.055,cx+.055,cz-.023,cz+.023)
  fasteners=[[cx,body[2]+.07],[cx,body[3]-.07]]
  bolt_holes=[(x-.014,x+.014,z-.014,z+.014) for x,z in fasteners]
  parts.append(rect_mesh(f'CoverFrame{n}',(19.02,19.47,za,zb),-.04,-.002,'teal',[opening]))
  parts.append(rect_mesh(f'SolidCover{n}',body,-.03,-.004,'teal',[pocket]+bolt_holes))
  parts.append(rect_mesh(f'GripPocket{n}',pocket,-.04,-.031,'seal'))
  parts.append(rect_mesh(f'RecessedGrip{n}',(cx-.049,cx+.049,cz-.007,cz+.007),-.031,-.017,'steel'))
  for k,hole in enumerate(bolt_holes): parts.append(rect_mesh(f'FastenerPocket{n}_{k}',hole,-.04,-.031,'seal'))
  # Fasteners sit within the solid cover; their 6mm depressed tops match the
  # approved source, and are source detail rather than a new collision claim.
  lids.append({'body':body,'center':[cx,cz],'fasteners':fasteners})
 area_net=sum((xs[i+1]-xs[i])*(zs[j+1]-zs[j]) for i,j in occupied)
 assert abs(area_net-97.545)<1e-8
 assert abs(sum(p['top_area'] for p in parts[1:1+len(groups)])-area_net)<1e-8
 return parts,{'origin':ORIGIN,'outer_area_m2':area(OUTER),'bank_excluded_m2':area(BANK),'outside_bank_m2':area(OUTER)-area(BANK),
  'body_holes':holes,'body_holes_m2':sum(area(h['rect']) for h in holes),'net_paving_m2':area_net,
  'source_parts':len(parts),'quad_triangles':sum(sum(len(f)-2 for f in p['faces']) for p in parts),'lids':lids,
  'north_joint':'old 20mm full seal only; new concrete starts Z2 without additional half seal',
  'scope':'static geometry and source preparation, no engine or collision claim'}

if __name__=='__main__':
 parts,report=build()
 report['inputs']={p:{'sha256':sha(ROOT/p),'bytes':(ROOT/p).stat().st_size} for p in INPUTS}
 (HERE/'prepared.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:report[k] for k in ['outer_area_m2','outside_bank_m2','body_holes_m2','net_paving_m2','source_parts','quad_triangles']}))
