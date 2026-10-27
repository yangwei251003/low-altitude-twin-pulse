"""Locate observed offline-image flat bands on actual source triangles."""
import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'shore_root_p12_basic_assembly.blend'))
s=bpy.context.scene;o=bpy.data.objects['Rock_HighShoulder'];o.data.calc_loop_triangles()
t=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[tuple(f.vertices) for f in o.data.loop_triangles],all_triangles=True)
c=s.camera;m=c.matrix_world;w=s.render.resolution_x;h=s.render.resolution_y
def gp(v):return [v.x,v.z,-v.y]
results=[]
for x,y in [(1000,385),(1100,340),(910,400),(1050,320),(940,360),(900,370),(1000,420)]:
 origin=m@Vector(((x/w-.5)*c.data.ortho_scale,(.5-y/h)*c.data.ortho_scale*h/w,0))
 direction=m.to_quaternion()@Vector((0,0,-1))
 p,n,index,d=t.ray_cast(origin,direction,100)
 r={'pixel':[x,y],'hit':gp(p) if p is not None else None,'normal':gp(n) if p is not None else None,'triangle':index}
 if index is not None:r['triangle_vertices']=[gp(o.matrix_world@o.data.vertices[i].co) for i in o.data.loop_triangles[index].vertices]
 results.append(r)
(OUT/'visible_cut_triangles.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2),flush=True)
