"""Inspect explicit GLB JSON/binary without invoking Godot or importing it."""
from pathlib import Path
import json, struct, hashlib, itertools, sys
sys.stdout.reconfigure(encoding="utf-8",errors="replace")
root=Path(__file__).resolve().parents[3]
path=root/"assets/v3/industrial/service_bridge.glb"
raw=path.read_bytes()
magic,version,total=struct.unpack_from("<III",raw,0)
length,kind=struct.unpack_from("<II",raw,12)
doc=json.loads(raw[20:20+length].decode())
names={n.get("name"):i for i,n in enumerate(doc["nodes"])}
parent={}
for index,node in enumerate(doc["nodes"]):
    for child in node.get("children",[]):parent[child]=index
rows=[]
for name in ["ServiceBridge","Shutter"]+[f"Slat_{i:02d}" for i in range(16)]:
    n=doc["nodes"][names[name]]
    rows.append({"name":name,"parent":doc["nodes"][parent[names[name]]].get("name") if names[name] in parent else None,
                 "translation":n.get("translation",[0,0,0]),"rotation":n.get("rotation",[0,0,0,1]),
                 "scale":n.get("scale",[1,1,1]),"matrix":n.get("matrix")})
meshtri=sum(doc["accessors"][p["indices"]]["count"]//3 for m in doc["meshes"] for p in m["primitives"])
identity=[[float(i==j) for j in range(4)] for i in range(4)]
def multiply(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def local_matrix(n):
    if "matrix" in n:return [[n["matrix"][j*4+i] for j in range(4)] for i in range(4)]
    x,y,z,w=n.get("rotation",[0,0,0,1]); sx,sy,sz=n.get("scale",[1,1,1]); tx,ty,tz=n.get("translation",[0,0,0])
    return [[(1-2*y*y-2*z*z)*sx,(2*x*y-2*z*w)*sy,(2*x*z+2*y*w)*sz,tx],
            [(2*x*y+2*z*w)*sx,(1-2*x*x-2*z*z)*sy,(2*y*z-2*x*w)*sz,ty],
            [(2*x*z-2*y*w)*sx,(2*y*z+2*x*w)*sy,(1-2*x*x-2*y*y)*sz,tz],[0,0,0,1]]
worlds={}
def world_matrix(i):
    if i not in worlds:worlds[i]=multiply(world_matrix(parent[i]) if i in parent else identity,local_matrix(doc["nodes"][i]))
    return worlds[i]
points=[]
for ni,n in enumerate(doc["nodes"]):
    if "mesh" not in n:continue
    mat=world_matrix(ni)
    for primitive in doc["meshes"][n["mesh"]]["primitives"]:
        acc=doc["accessors"][primitive["attributes"]["POSITION"]]
        for p in itertools.product(*zip(acc["min"],acc["max"])):
            points.append([sum(mat[i][j]*p[j] for j in range(3))+mat[i][3] for i in range(3)])
bmin=[min(p[i] for p in points) for i in range(3)]
bmax=[max(p[i] for p in points) for i in range(3)]
report={"asset":str(path),"sha256":hashlib.sha256(raw).hexdigest(),"bytes":len(raw),"valid_glb_v2":magic==0x46546c67 and version==2 and total==len(raw),
"meshes":len(doc["meshes"]),"primitives":sum(len(m["primitives"]) for m in doc["meshes"]),"triangles":meshtri,
"materials":len(doc["materials"]),"images":len(doc.get("images",[])),"images_embedded":all("bufferView" in im for im in doc.get("images",[])),
"world_aabb_gltf_y_up":{"minimum":bmin,"maximum":bmax,"size":[bmax[i]-bmin[i] for i in range(3)]},
"node_transforms":rows,"slats_are_direct_shutter_children":all(row["parent"]=="Shutter" for row in rows[2:]),
"all_uv_present":all("TEXCOORD_0" in p["attributes"] for m in doc["meshes"] for p in m["primitives"]),
"pbr_textures_present":all("baseColorTexture" in m.get("pbrMetallicRoughness",{}) and "metallicRoughnessTexture" in m.get("pbrMetallicRoughness",{}) and "normalTexture" in m for m in doc["materials"])}
out=root/"artifacts/v3/art/industrial/glb_inspection.json"
out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(report,ensure_ascii=False,indent=2))
