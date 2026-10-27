"""Bounded actual-GLB readback; adapted from pump delivery_v8.verify_raw.

No rendering, installation or filesystem mutation. Caller supplies exact source
triangles and maps; this verifies the 12-part candidate, not a generic importer.
"""
from pathlib import Path
import collections
import hashlib
import json
import math
import struct
import numpy as np


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(corners):
    keys = [tuple(round(v,5) for v in c['p']) for c in corners]
    index = min(range(3), key=lambda i:keys[i:]+keys[:i])
    return tuple(keys[index:]+keys[:index]), corners[index:]+corners[:index]


def verify_raw(path, expected, textures, contract):
    raw = Path(path).read_bytes()
    assert struct.unpack_from('<4sII',raw) == (b'glTF',2,len(raw))
    offset, doc, binary = 12, None, None
    while offset < len(raw):
        size,kind = struct.unpack_from('<I4s',raw,offset)
        offset += 8
        chunk = raw[offset:offset+size]
        offset += size
        if kind == b'JSON':
            doc = json.loads(chunk)
        elif kind == b'BIN\0':
            binary = chunk
    assert doc is not None and binary is not None and offset == len(raw)
    assert not doc.get('animations') and not doc.get('cameras') and not doc.get('skins')

    def accessor(index):
        a = doc['accessors'][index]
        view = doc['bufferViews'][a['bufferView']]
        assert 'sparse' not in a and not a.get('normalized',False)
        width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        fmt,size = {5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        start = view.get('byteOffset',0)+a.get('byteOffset',0)
        stride = view.get('byteStride',width*size)
        result = [struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(a['count'])]
        assert all(math.isfinite(v) for row in result for v in row)
        return result

    specs = {r['name']:r for r in contract['parts']+contract['anchors']+contract['identity_groups']}
    assert len(doc['nodes']) == len(specs) and len(doc['meshes']) == 12
    parent_by_index = {}
    for index,node in enumerate(doc['nodes']):
        for child in node.get('children',[]):
            assert child not in parent_by_index
            parent_by_index[child] = index
    nodes, actual, all_points = {}, {}, []
    for index,node in enumerate(doc['nodes']):
        name = node['name']
        assert name in specs and name not in nodes
        spec = specs[name]
        parent = doc['nodes'][parent_by_index[index]]['name'] if index in parent_by_index else None
        assert parent == spec['parent'], (name,parent,spec['parent'])
        translation = node.get('translation',[0,0,0])
        assert max(abs(a-b) for a,b in zip(node.get('rotation',[0,0,0,1]),[0,0,0,1])) < 1e-7
        assert max(abs(v-1) for v in node.get('scale',[1,1,1])) < 1e-7
        matrix = node.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,*translation,1])
        expected_translation = spec.get('translation',[0,0,0])
        expected_matrix = [1,0,0,0,0,1,0,0,0,0,1,0,*expected_translation,1]
        assert max(abs(a-b) for a,b in zip(matrix,expected_matrix)) < 2e-6, (name,matrix,expected_matrix)
        nodes[name] = {'node_index':index,'parent':parent,'local_matrix_column_major':matrix,
                       'root_matrix_column_major':matrix,'raw_node':node}
        # All ancestors are exactly identity. Leaf authored centers remain in
        # matrices; the accessor positions are deliberately center-relative.
        if 'mesh' not in node:
            continue
        assert name in expected
        primitives = doc['meshes'][node['mesh']]['primitives']
        assert len(primitives) == 1
        actual[name] = []
        points = []
        for primitive in primitives:
            attrs = primitive['attributes']
            assert primitive.get('mode',4) == 4 and primitive['material'] == 0
            assert 'TEXCOORD_0' in attrs and 'TEXCOORD_1' not in attrs and 'TANGENT' in attrs
            ps,ns,uv = accessor(attrs['POSITION']),accessor(attrs['NORMAL']),accessor(attrs['TEXCOORD_0'])
            tangents = accessor(attrs['TANGENT'])
            assert all(abs(abs(t[3])-1) < 1e-6 for t in tangents)
            indices = [v[0] for v in accessor(primitive['indices'])]
            assert len(indices)%3 == 0
            assert all(-1e-6 <= v <= 1.000001 for row in uv for v in row)
            points.extend(ps)
            all_points.extend([[p[i]+expected_translation[i] for i in range(3)] for p in ps])
            for i in range(0,len(indices),3):
                actual[name].append([{'p':list(ps[j]),'n':list(ns[j]),'uv':[uv[j][0],1-uv[j][1]]} for j in indices[i:i+3]])
        local_bounds = {'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)]}
        assert max(abs(a-b) for key in ('min','max') for a,b in zip(local_bounds[key],spec['accessor_local_bounds_expected'][key])) < 3e-6
        nodes[name]['accessor_local_bounds'] = local_bounds
        nodes[name]['triangles'] = len(actual[name])
        assert len(actual[name]) == spec['triangles']
    assert set(actual) == set(expected)
    errors = {'position':0.,'normal_after_exporter_quantization':0.,'uv':0.}
    raw_normal_error = 0.
    for name in expected:
        a,b = collections.defaultdict(list),collections.defaultdict(list)
        for row in expected[name]:
            key,corners = canonical(row)
            a[key].append(corners)
        for row in actual[name]:
            key,corners = canonical(row)
            b[key].append(corners)
        assert {k:len(v) for k,v in a.items()} == {k:len(v) for k,v in b.items()}, (name,'triangle multiset/winding')
        for key in a:
            sorting = lambda tri:tuple(round(v,6) for c in tri for v in c['uv']+c['n'])
            for left,right in zip(sorted(a[key],key=sorting),sorted(b[key],key=sorting)):
                for e,c in zip(left,right):
                    errors['position'] = max(errors['position'],max(abs(x-y) for x,y in zip(e['p'],c['p'])))
                    errors['uv'] = max(errors['uv'],max(abs(x-y) for x,y in zip(e['uv'],c['uv'])))
                    # Same installed 5.2.1 exporter rule verified in pump pipeline:
                    # float32 round(4), then normalize. Do not hide source delta.
                    q = np.round(np.asarray([e['n']],dtype=np.float32),4)
                    np.divide(q,np.linalg.norm(q,axis=1,keepdims=True),out=q)
                    errors['normal_after_exporter_quantization'] = max(errors['normal_after_exporter_quantization'],max(abs(float(x)-y) for x,y in zip(q[0],c['n'])))
                    raw_normal_error = max(raw_normal_error,max(abs(x-y) for x,y in zip(e['n'],c['n'])))
    assert errors['position'] < 3e-6 and errors['uv'] < 2e-6 and errors['normal_after_exporter_quantization'] < 3e-5, errors
    assert sum(len(v) for v in actual.values()) == 10912
    assert len(doc['materials']) == 1 and len(doc['images']) == 3
    material = doc['materials'][0]
    assert material['name'] == 'SharedBridgeDeck_PBR'
    assert not material.get('doubleSided',False) and material.get('alphaMode','OPAQUE') == 'OPAQUE'
    assert material.get('emissiveFactor',[0,0,0]) == [0,0,0]
    for texture in [material['pbrMetallicRoughness']['baseColorTexture'],material['pbrMetallicRoughness']['metallicRoughnessTexture'],material['normalTexture']]:
        assert texture.get('texCoord',0) == 0
    images = []
    for image in doc['images']:
        assert 'bufferView' in image and 'uri' not in image and image['mimeType'] == 'image/png'
        view = doc['bufferViews'][image['bufferView']]
        data = binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        assert data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',data,16) == (2048,2048)
        images.append({'name':image.get('name'),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    assert {r['sha256'] for r in images} == {sha(p) for p in textures.values()}, 'Embedded bytes differ; stop and inspect.'
    return {'status':'RAW_GLB_VERIFIED_NOT_GODOT','sha256':sha(path),'bytes':len(raw),
            'nodes':nodes,'meshes':12,'triangles':10912,'surfaces':12,'materials':[material],'images':images,
            'bounds':{'min':[min(p[i] for p in all_points) for i in range(3)],'max':[max(p[i] for p in all_points) for i in range(3)]},
            'source_errors':errors,'raw_source_normal_delta':raw_normal_error,'world_origin_godot':[15,5,0],
            'note':'Matrices are actual glTF column-major local/root matrices. Only grouping ancestors are identity; mesh centers are authored translations.'}
