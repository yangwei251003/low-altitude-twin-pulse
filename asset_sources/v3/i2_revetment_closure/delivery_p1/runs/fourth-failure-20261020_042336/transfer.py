"""Bounded triangle/UV transfer for this frozen revetment, no engine imports."""
from pathlib import Path
import collections, hashlib, itertools, json, math, struct

GEOMETRY_EPS = 3e-6  # Same measured float32 crop footprint bound as source.
SOURCE_UV_EPS = 3e-6
ATTRIBUTE_EPS = 3e-6
ATLAS_EPS = 2e-6

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def norm(a): return math.sqrt(dot(a,a))
def area(points): return norm(cross(sub(points[1],points[0]),sub(points[2],points[0])))*.5
def uv_area(points):
    a,b,c=points
    return abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))*.5
def mix(values,weights): return tuple(sum(w*v[j] for w,v in zip(weights,values)) for j in range(len(values[0])))
def canonical(points):
    values=[tuple(p) for p in points];index=min(range(3),key=lambda i:values[i:]+values[:i])
    return tuple(values[index:]+values[:index]),index

def read_glb(path):
    raw=Path(path).read_bytes();assert struct.unpack_from('<4sII',raw)==(b'glTF',2,len(raw))
    cursor=12;doc=None;binary=None
    while cursor<len(raw):
        length,kind=struct.unpack_from('<I4s',raw,cursor);cursor+=8
        chunk=raw[cursor:cursor+length];cursor+=length
        if kind==b'JSON':doc=json.loads(chunk)
        elif kind==b'BIN\0':binary=chunk
    assert cursor==len(raw) and doc is not None and binary is not None
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        assert 'sparse' not in a and not a.get('normalized',False)
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        code,size={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*size)
        values=[struct.unpack_from('<'+code*width,binary,start+i*stride) for i in range(a['count'])]
        assert all(math.isfinite(x) for row in values for x in row)
        return values
    return doc,binary,accessor

def original_glb_triangles(path):
    doc,binary,accessor=read_glb(path)
    assert len(doc['meshes'])==1 and len(doc['materials'])==1
    primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
    ps=accessor(attrs['POSITION']);uv=accessor(attrs['TEXCOORD_0']);indices=[v[0] for v in accessor(primitive['indices'])]
    assert len(indices)==5152*3
    rows=collections.defaultdict(list)
    for first in range(0,len(indices),3):
        ids=indices[first:first+3]
        # Godot/glTF → Blender, and raw GLB's V-down → Blender V-up.
        points=[(ps[i][0],-ps[i][2],ps[i][1]) for i in ids]
        values=[(uv[i][0],1-uv[i][1]) for i in ids]
        key,order=canonical(points);rows[key].append(values[order:]+values[:order])
    images=[]
    for image in doc['images']:
        view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
        data=binary[start:start+view['byteLength']]
        images.append({'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'size':struct.unpack_from('>II',data,16)})
    return rows,images

def barycentric(point,points):
    a,b,c=points;u=sub(b,a);v=sub(c,a);normal=cross(u,v)
    major=max(range(3),key=lambda j:abs(normal[j]));axes=[j for j in range(3) if j!=major]
    j,k=axes;denom=u[j]*v[k]-u[k]*v[j]
    assert denom!=0,'reference source triangle has true zero area'
    q=sub(point,a);b_weight=(q[j]*v[k]-q[k]*v[j])/denom;c_weight=(u[j]*q[k]-u[k]*q[j])/denom
    return (1-b_weight-c_weight,b_weight,c_weight)

class SourceTransfer:
    """Spatial bins are only candidate discovery. Final transfer validates 3D,
    both authored UV layers and every material attribute at all three corners.
    Distinct bake islands on a common geometric edge are never silently merged.
    """
    def __init__(self,rows):
        self.rows=rows;self.cells=collections.defaultdict(set);self.maximum={'position_m':0.,'outside_m':0.,'source_uv':0.,'attribute':0.}
        self.multiple_equivalent=0;self.mapped=0
        for index,row in enumerate(rows):
            ranges=[range(math.floor((min(p[j] for p in row['p'])-GEOMETRY_EPS)/.25),math.floor((max(p[j] for p in row['p'])+GEOMETRY_EPS)/.25)+1) for j in range(3)]
            for key in itertools.product(*ranges):self.cells[key].add(index)

    def map_triangle(self,target,label):
        center=tuple(sum(p[j] for p in target['p'])/3 for j in range(3));cell=tuple(math.floor(v/.25) for v in center)
        matches=[]
        for index in self.cells.get(cell,[]):
            source=self.rows[index]
            if source['material']!=target['material']:continue
            weights=[barycentric(p,source['p']) for p in target['p']]
            errors={'position_m':0.,'outside_m':0.,'source_uv':0.,'attribute':0.};valid=True
            points=source['p'];area2=2*area(points)
            altitudes=[area2/math.dist(points[(j+1)%3],points[(j+2)%3]) for j in range(3)]
            for corner,w in enumerate(weights):
                # Spatial allowance only compensates measured float32 clipping.
                # Each barycentric weight is distance to its OPPOSITE edge
                # divided by the corresponding altitude, not longest edge.
                outside=max(max(0.,-weight*altitude) for weight,altitude in zip(w,altitudes))
                errors['outside_m']=max(errors['outside_m'],outside)
                if outside>GEOMETRY_EPS:valid=False;break
                errors['position_m']=max(errors['position_m'],math.dist(target['p'][corner],mix(source['p'],w)))
                for name,values in source['uv'].items():
                    errors['source_uv']=max(errors['source_uv'],max(abs(a-b) for a,b in zip(target['uv'][name][corner],mix(values,w))))
                for name,values in source['attrs'].items():
                    errors['attribute']=max(errors['attribute'],abs(target['attrs'][name][corner]-sum(a*b for a,b in zip(values,w))))
            if not valid or errors['position_m']>GEOMETRY_EPS or errors['source_uv']>SOURCE_UV_EPS or errors['attribute']>ATTRIBUTE_EPS:continue
            mapped=[mix(source['bake'],w) for w in weights]
            matches.append((sum(errors.values()),index,mapped,errors))
        if not matches:
            raise AssertionError({'stage':'source_atlas_transfer','label':label,'reason':'no_exact_surface_correspondence','triangle':target,'candidates':sorted(self.cells.get(cell,[]))})
        matches.sort();chosen=matches[0]
        if len(matches)>1:
            differences=[max(abs(a-b) for u,v in zip(chosen[2],r[2]) for a,b in zip(u,v)) for r in matches[1:]]
            if max(differences)>ATLAS_EPS:
                raise AssertionError({'stage':'source_atlas_transfer','label':label,'reason':'ambiguous_distinct_bake_islands','matches':[(r[1],r[0],r[3]) for r in matches],'atlas_differences':differences,'triangle':target})
            self.multiple_equivalent+=1
        for key,value in chosen[3].items():self.maximum[key]=max(self.maximum[key],value)
        self.mapped+=1
        return chosen[2]
