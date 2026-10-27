"""Read frozen GLB UVs only, no Blender or image pixel editing."""
from pathlib import Path
import runpy,hashlib,json,math
HERE=Path(__file__).resolve().parent
P2=HERE.parent/'delivery_p2/clinic_ground_p2.glb'
EXPECTED='03e063e4f5e77468b9d1770c7a29686e600fdafce07a537a6018e45c1cc2a691'
assert hashlib.sha256(P2.read_bytes()).hexdigest()==EXPECTED
lib=runpy.run_path(str(HERE.parent/'delivery_p2/read_glb.py'))
j,meshes,bb,images=lib['read'](P2)
triangles=list(meshes['SlabsAndSeals']['corner_uv'])
top=[t for t in triangles if all(abs(p[1])<1e-7 and p[0]<-.61 and p[2]>-.64 for p in t)]
assert top
def det(t):return (t[1][0]-t[0][0])*(t[2][2]-t[0][2])-(t[2][0]-t[0][0])*(t[1][2]-t[0][2])
t=max(top,key=lambda t:abs(det(t)));d=det(t);assert abs(d)>.1
coeff=[]
for axis in [3,4]:
 values=[p[axis] if axis==3 else 1-p[axis] for p in t]
 dx1=t[1][0]-t[0][0];dz1=t[1][2]-t[0][2];dx2=t[2][0]-t[0][0];dz2=t[2][2]-t[0][2]
 a=((values[1]-values[0])*dz2-(values[2]-values[0])*dz1)/d
 b=(dx1*(values[2]-values[0])-dx2*(values[1]-values[0]))/d
 c=values[0]-a*t[0][0]-b*t[0][2];coeff.append([a,b,c])
def mapped(x,z):return [a*x+b*z+c for a,b,c in coeff]
error=max(abs(mapped(p[0],p[2])[k]-(p[3] if k==0 else 1-p[4])) for tri in top for p in tri for k in [0,1])
assert error<2e-7,error
rect=[[-2.7,.1],[-.9,.1],[-.9,1.9],[-2.7,1.9]]
def contained(point,tri):
 x,z=point;den=det(tri)
 if abs(den)<1e-12:return False
 a=((tri[1][0]-x)*(tri[2][2]-z)-(tri[2][0]-x)*(tri[1][2]-z))/den
 b=((tri[2][0]-x)*(tri[0][2]-z)-(tri[0][0]-x)*(tri[2][2]-z))/den
 c=1-a-b;return min(a,b,c)>=-1e-6
samples=[[-2.7+1.8*i/16,.1+1.8*k/16] for i in range(17) for k in range(17)]
assert all(any(contained(p,t) for t in top) for p in samples)
dark=[t for t in triangles if all(abs(p[1]+.012)<1e-6 for p in t)]
assert dark
def uv_radius(tri):
 uv=[(p[3],1-p[4]) for p in tri];center=tuple(sum(p[i] for p in uv)/3 for i in [0,1]);ds=[]
 for a,b in zip(uv,uv[1:]+uv[:1]):
  ln=math.dist(a,b)
  ds.append(abs((b[0]-a[0])*(a[1]-center[1])-(a[0]-center[0])*(b[1]-a[1]))/ln if ln else 0)
 return min(ds),center,uv
r,center,uv=max(map(uv_radius,dark),key=lambda t:t[0]);assert r>0
report={'status':'READONLY_UV_SOURCE_VERIFIED_NOT_BLENDER','source_glb_sha256':EXPECTED,
 'concrete_patch':{'source_object':'Pour_NW top','rectangle_godot_xz':rect,'physical_width_m':1.8,'physical_depth_m':1.8,'uv_blender':list(map(lambda p:mapped(*p),rect)),'uv_affine_x_z_constant':coeff,'max_affine_residual':error,'all_289_grid_points_inside_actual_source_top':True,'scope':'Chosen region excludes P2 repair at z=-1.45, wet edge at x=2.44 and yellow at x=2.85.'},
 'dark_seal_patch':{'uv_center':center,'uv_safe_radius':r*.35,'source_triangle_uv':uv,'source_y':-.012},
 'variants':{'A':{'metric_offset_xz':[0,0]},'B':{'metric_offset_xz':[.67,.43]}},
 'no_new_texture_or_pixel_edit':True}
(HERE/'sampling_contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
