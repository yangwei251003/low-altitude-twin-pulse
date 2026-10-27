"""Read mesh/object SDNA from downloaded CC0 .blend bytes; no Blender launch.
Uses existing Git libzstd.dll via ctypes; no installation. Files remain intact.
Output is an audit only; triangle count = corners_num - 2 * faces_num, before
modifiers. This is not a source visual or engine-import acceptance.
"""
from pathlib import Path
import ctypes,struct,json,re,hashlib
BASE=Path(__file__).resolve().parent
lib=ctypes.CDLL('C:/Program Files/Git/mingw64/bin/libzstd.dll')
lib.ZSTD_findFrameCompressedSize.argtypes=[ctypes.c_void_p,ctypes.c_size_t];lib.ZSTD_findFrameCompressedSize.restype=ctypes.c_size_t
lib.ZSTD_getFrameContentSize.argtypes=[ctypes.c_void_p,ctypes.c_size_t];lib.ZSTD_getFrameContentSize.restype=ctypes.c_ulonglong
lib.ZSTD_decompress.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t];lib.ZSTD_decompress.restype=ctypes.c_size_t
lib.ZSTD_isError.argtypes=[ctypes.c_size_t];lib.ZSTD_isError.restype=ctypes.c_uint
def decompress(blob):
    if blob[:7]==b'BLENDER':return blob
    result=[];offset=0
    while offset<len(blob):
        data=ctypes.create_string_buffer(blob[offset:]);n=lib.ZSTD_findFrameCompressedSize(data,len(blob)-offset)
        if lib.ZSTD_isError(n):raise ValueError('ZSTD invalid frame')
        size=lib.ZSTD_getFrameContentSize(data,n)
        if size>100_000_000:raise ValueError('unknown or oversized decompressed frame')
        out=ctypes.create_string_buffer(size);actual=lib.ZSTD_decompress(out,size,data,n)
        if lib.ZSTD_isError(actual):raise ValueError('ZSTD decode failure')
        result.append(out.raw[:actual]);offset+=n
    return b''.join(result)

def inspect(path):
    compressed=path.read_bytes();blob=decompress(compressed)
    assert blob[:7]==b'BLENDER'
    ptr=8 if blob[7:8]==b'-' else 4;e='<' if blob[8:9]==b'v' else '>'
    fmt=e+'4sI'+('Q' if ptr==8 else 'I')+'II';head=struct.calcsize(fmt)
    blocks=[];offset=12
    while offset+head<=len(blob):
        code,size,address,sdna,count=struct.unpack_from(fmt,blob,offset);offset+=head
        data=blob[offset:offset+size];offset+=size
        blocks.append((code,address,sdna,count,data))
        if code==b'ENDB':break
    dna=next(b[4] for b in blocks if b[0]==b'DNA1');p=4
    def strings(tag):
        nonlocal p
        assert dna[p:p+4]==tag;p+=4;n=struct.unpack_from(e+'I',dna,p)[0];p+=4;out=[]
        for _ in range(n):
            end=dna.index(0,p);out.append(dna[p:end].decode());p=end+1
        p=(p+3)&~3;return out
    names=strings(b'NAME');types=strings(b'TYPE')
    assert dna[p:p+4]==b'TLEN';p+=4
    lengths=struct.unpack_from(e+str(len(types))+'H',dna,p);p+=2*len(types);p=(p+3)&~3
    assert dna[p:p+4]==b'STRC';p+=4;n=struct.unpack_from(e+'I',dna,p)[0];p+=4
    schemas=[];by_type={}
    for i in range(n):
        ti,nf=struct.unpack_from(e+'HH',dna,p);p+=4;fields={};off=0
        for _ in range(nf):
            ft,fn=struct.unpack_from(e+'HH',dna,p);p+=4;name=names[fn]
            count=1
            for value in re.findall(r'\[(\d+)\]',name):count*=int(value)
            size=(ptr if '*' in name else lengths[ft])*count
            key=re.sub(r'\[.*','',name).lstrip('*');fields[key]={'offset':off,'size':size,'type':types[ft],'pointer':'*' in name};off+=size
        schema={'name':types[ti],'fields':fields,'length':lengths[ti],'sum_fields':off}
        schemas.append(schema);by_type[types[ti]]=schema
    def get(block,key):
        f=schemas[block[2]]['fields'][key];return block[4][f['offset']:f['offset']+f['size']]
    def integer(block,key):return struct.unpack(e+'i',get(block,key)[:4])[0]
    def idname(block):
        namefield=by_type['ID']['fields']['name'];s=get(block,'id');return s[namefield['offset']:namefield['offset']+namefield['size']].split(b'\0')[0].decode('utf8','replace')
    meshes={};objects=[]
    for block in blocks:
        if block[2]>=len(schemas):continue
        schema=schemas[block[2]]
        if schema['name']=='Mesh' and len(block[4])>=schema['length']:
            f=schema['fields'];counts={}
            for key in ['verts_num','faces_num','corners_num','totvert','totpoly','totloop']:
                if key in f:counts[key]=integer(block,key)
            faces=counts.get('faces_num',counts.get('totpoly',0));corners=counts.get('corners_num',counts.get('totloop',0))
            meshes[block[1]]={'mesh':idname(block)[2:],'counts':counts,'triangles_before_modifiers':corners-2*faces,'schema_size_checked':schema['sum_fields']==schema['length']}
    for block in blocks:
        if block[2]>=len(schemas) or schemas[block[2]]['name']!='Object':continue
        address=int.from_bytes(get(block,'data'),'little' if e=='<' else 'big')
        if address in meshes:objects.append({'object':idname(block)[2:],**meshes[address]})
    return {'file':str(path.relative_to(BASE)),'sha256':hashlib.sha256(compressed).hexdigest(),'compressed_bytes':len(compressed),'memory_decompressed_bytes':len(blob),'blender_version':blob[9:12].decode(),'objects':objects,'limitations':['binary read only, no Blender execution','counts are before modifiers','no geometry/watertight/self-crossing proof for native LOD meshes']}

out=[inspect(BASE/a/(a+'_1k.blend')) for a in ['boulder_01','namaqualand_boulder_03']]
(BASE/'native_lod_counts.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(out,ensure_ascii=False,indent=2))
