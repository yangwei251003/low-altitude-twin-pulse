"""Read frozen source mesh; record actual plane intersections, no source mutation.
Blender background --factory-startup --threads 2 --python this_file.
Only writes natural_sections.json beside this script; no rendering or GPU.
"""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector
BASE=Path(__file__).resolve().parent
PROJECT=BASE.parents[3]
SOURCE=PROJECT/'asset_sources/v3/shore_root/p9/rigid_root_main_form.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=sha(SOURCE)
with bpy.data.libraries.load(str(SOURCE),link=False) as (src,dst):
    dst.objects=['P9_Natural_Fork_Rigid_3x_No_Stretch']
ob=dst.objects[0]
verts=[Vector((v.co.x,v.co.z,-v.co.y)) for v in ob.data.vertices]
ob.data.calc_loop_triangles()
triangles=[t.vertices[:] for t in ob.data.loop_triangles]
rows=[]
for i in range(22):
    yy=.1+.1*i
    hits=[]
    for tri in triangles:
        points=[verts[j] for j in tri]
        for a,b in zip(points,points[1:]+points[:1]):
            if (a.y-yy)*(b.y-yy)<0:
                p=a+(b-a)*((yy-a.y)/(b.y-a.y))
                hits.append(p)
    xs=sorted(p.x for p in hits)
    zs=sorted(p.z for p in hits)
    if xs:
        def quant(a,p):return a[round((len(a)-1)*p)]
        rows.append({'source_y':yy,'intersections':len(hits),'x_quantiles':[quant(xs,p) for p in (0,.1,.25,.5,.75,.9,1)],'z_quantiles':[quant(zs,p) for p in (0,.1,.25,.5,.75,.9,1)],'xz_points':[[p.x,p.z] for p in hits]})
out={'source':str(SOURCE.relative_to(PROJECT)),'source_sha256':before,'coordinate_convention':'source glTF/Godot-style x,y,z, disregarding prior object matrix','original_object_matrix':[[v for v in row] for row in ob.matrix_world],'source_unchanged':before==sha(SOURCE),'slices':rows}
(BASE/'natural_sections.json').write_text(json.dumps(out,indent=2),encoding='utf8')
print('NATURAL_SECTIONS',json.dumps([{k:v for k,v in r.items() if k!='xz_points'} for r in rows]))
