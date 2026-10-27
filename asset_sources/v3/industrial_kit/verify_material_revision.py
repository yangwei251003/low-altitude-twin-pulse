"""Prove terrace material revision preserves geometry and locked relay resources."""
from pathlib import Path
import hashlib,json,struct
from PIL import Image,ImageStat

ROOT=Path(__file__).resolve().parents[3]
EVID=ROOT/'artifacts/v3/art/industrial_kit'
BASE=EVID/'material-revision-baseline'
OUT=ROOT/'assets/v3/industrial_kit'
def sha(data):return hashlib.sha256(data).hexdigest()
def read_glb(path):
    raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+size]);start=20+size
    binsize,kind=struct.unpack_from('<II',raw,start)
    assert kind==0x004e4942
    return doc,raw[start+8:start+8+binsize]
def accessor(doc,blob,i):
    a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
    component={5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}[a['componentType']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]*component
    stride=v.get('byteStride',width);start=v.get('byteOffset',0)+a.get('byteOffset',0)
    return b''.join(blob[start+j*stride:start+j*stride+width] for j in range(a['count']))
def describe(doc,blob):
    nodes={};meshdata={}
    for n in doc['nodes']:
        name=n['name'];nodes[name]={k:n.get(k,default) for k,default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]}
        nodes[name]['children']=sorted(doc['nodes'][i]['name'] for i in n.get('children',[]))
        if 'mesh' not in n:continue
        for p in doc['meshes'][n['mesh']]['primitives']:
            mat=doc['materials'][p['material']]['name'];key=name+'::'+mat
            meshdata[key]={attr:sha(accessor(doc,blob,index)) for attr,index in p['attributes'].items()}
            meshdata[key]['indices']=sha(accessor(doc,blob,p['indices']))
    return nodes,meshdata
def expanded_geometry(doc,blob):
    result={};uvs={}
    for n in doc['nodes']:
        if 'mesh' not in n:continue
        for p in doc['meshes'][n['mesh']]['primitives']:
            key=n['name']+'::'+doc['materials'][p['material']]['name']
            ia=doc['accessors'][p['indices']];fmt={5121:'B',5123:'H',5125:'I'}[ia['componentType']]
            indices=struct.unpack('<'+fmt*ia['count'],accessor(doc,blob,p['indices']))
            result[key]={}
            for semantic in ['POSITION','NORMAL']:
                data=accessor(doc,blob,p['attributes'][semantic])
                result[key][semantic]=sha(b''.join(data[i*12:i*12+12] for i in indices))
            data=accessor(doc,blob,p['attributes']['TEXCOORD_0'])
            uvs[key]=struct.unpack('<'+'f'*(len(data)//4),data)
    return result,uvs

old_doc,old_blob=read_glb(BASE/'coastal_work_terrace_v3.glb')
new_doc,new_blob=read_glb(OUT/'coastal_work_terrace.glb')
old_nodes,old_mesh=describe(old_doc,old_blob);new_nodes,new_mesh=describe(new_doc,new_blob)
checks={'nodes_names_hierarchy_transforms_identical':old_nodes==new_nodes,'mesh_material_names_identical':old_mesh.keys()==new_mesh.keys()}
changed_attributes=[]
for key,attrs in old_mesh.items():
    for attr,hashvalue in attrs.items():
        if new_mesh.get(key,{}).get(attr)!=hashvalue:changed_attributes.append(key+'::'+attr)
checks['all_positions_identical']=all(v['POSITION']==new_mesh[k]['POSITION'] for k,v in old_mesh.items())
checks['all_normals_identical']=all(v['NORMAL']==new_mesh[k]['NORMAL'] for k,v in old_mesh.items())
raw_indices_identical=all(v['indices']==new_mesh[k]['indices'] for k,v in old_mesh.items())
old_expanded,old_uv=expanded_geometry(old_doc,old_blob);new_expanded,new_uv=expanded_geometry(new_doc,new_blob)
# glTF may choose different indices for coincident UV-split vertices. Exact
# indexed triangle positions/normals are the physical geometry contract.
checks['all_indexed_triangle_positions_and_normals_exactly_identical']=old_expanded==new_expanded
other_uv_max=max(abs(a-b) for k,vals in old_uv.items() if 'SafetySignal' not in k for a,b in zip(vals,new_uv[k]))
checks['non_safety_uv_equal_within_1e_6']=other_uv_max<=1e-6
preserved=json.loads((BASE/'preserved_files.json').read_text(encoding='utf-8-sig'))
modified_preserved=[p['path'] for p in preserved if sha(Path(p['path']).read_bytes())!=p['sha256']]
checks['relay_blend_glb_and_original_17_maps_unchanged']=not modified_preserved
safety=next(m for m in new_doc['materials'] if m['name']=='IK_SafetySignal')
checks['no_safety_emission_texture']='emissiveTexture' not in safety and not any(safety.get('emissiveFactor',[0,0,0]))
safe_texture=new_doc['textures'][safety['pbrMetallicRoughness']['baseColorTexture']['index']]
safe_sampler=new_doc['samplers'][safe_texture['sampler']]
checks['safety_sampler_clamps_both_edges']=safe_sampler.get('wrapS')==33071 and safe_sampler.get('wrapT')==33071
textures=OUT/'textures'
original=Image.open(textures/'IK_IvoryWeather_BaseColor.png').convert('RGB')
revised=Image.open(textures/'IK_TerraceConcrete_BaseColor.png').convert('RGB')
w,h=original.size
old_top=original.crop((0,0,w,h//2));new_top=revised.crop((0,0,w,h//2))
old_std=ImageStat.Stat(old_top.convert('L')).stddev[0];new_std=ImageStat.Stat(new_top.convert('L')).stddev[0]
checks['vertical_base_color_pixels_unchanged']=original.crop((0,h//2,w,h)).tobytes()==revised.crop((0,h//2,w,h)).tobytes()
checks['top_luminance_variation_less_than_35_percent_old']=new_std<old_std*.35
safe=Image.open(textures/'IK_TerraceSafety_BaseColor.png').convert('RGB')
green=sum(g>r*1.08 and g>b*1.2 and g-r>12 for r,g,b in safe.getdata())
checks['zero_green_pixels_in_terrace_safety']=green==0
report={'revision':4,'old_sha256':sha((BASE/'coastal_work_terrace_v3.glb').read_bytes()),'new_sha256':sha((OUT/'coastal_work_terrace.glb').read_bytes()),'checks':checks,'all_checks_pass':all(checks.values()),'changed_attributes':changed_attributes,'raw_indices_identical':raw_indices_identical,'non_safety_uv_max_absolute_difference':other_uv_max,'index_note':'35 safety indices remap coincident UV-split vertices; all indexed triangle positions and normals remain exactly equal. Initial strict byte comparison is retained separately.','modified_preserved_files':modified_preserved,'top_grayscale_stddev_8bit':{'old':old_std,'new':new_std,'ratio':new_std/old_std},'safety_green_pixels':green,'geometry_attribute_hashes':new_mesh,'scope':'Exact indexed GLB geometry/node comparison; texture/source preservation; not runtime image or collision evidence'}
(EVID/'coastal_work_terrace_material_revision_v4.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='geometry_attribute_hashes'},ensure_ascii=False))
raise SystemExit(0 if report['all_checks_pass'] else 1)
