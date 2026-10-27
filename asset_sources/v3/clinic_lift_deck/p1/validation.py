"""Actual saved-source comparison with documented delivery precision."""
from common import *
def source_state():
    rows=[]
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source'))),key=lambda x:x.name):
        me=ob.data
        rows.append({'name':ob.name,'parent':ob.parent.name,'matrix':[list(r) for r in ob.matrix_local],
            'vertices':[list(v.co) for v in me.vertices],'faces':[(list(p.vertices),p.material_index,p.use_smooth) for p in me.polygons],
            'UV':{u.name:[list(v.uv) for v in u.data] for u in me.uv_layers},'materials':[m.name for m in me.materials]})
    return hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def evaluated_state():
    deps=bpy.context.evaluated_depsgraph_get();state={}
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source'))),key=lambda x:x.name):
        ev=ob.evaluated_get(deps);me=ev.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
        try:
            me.calc_loop_triangles()
            state[ob.name]={'p':[tuple(v.co) for v in me.vertices],'t':[(tuple(t.vertices),tuple(t.loops),t.material_index) for t in me.loop_triangles],
                'n':[tuple(n.vector) for n in me.corner_normals],'uv':{u.name:[tuple(q.uv) for q in u.data] for u in me.uv_layers}}
        finally:ev.to_mesh_clear()
    return state
def compare_evaluated(a,b):
    assert a.keys()==b.keys();pos=0.;uv=0.;angle=0.;component=0.;bylayer={};changed=[]
    for name in a:
        aa,bb=a[name],b[name]
        assert aa['t']==bb['t'],(name,'topology or winding changed')
        assert len(aa['p'])==len(bb['p']) and len(aa['n'])==len(bb['n'])
        for x,y in zip(aa['p'],bb['p']):pos=max(pos,max(abs(float(i)-float(j)) for i,j in zip(x,y)))
        for x,y in zip(aa['n'],bb['n']):
            component=max(component,max(abs(float(i)-float(j)) for i,j in zip(x,y)))
            dot=sum(float(i)*float(j) for i,j in zip(x,y))
            cross=(x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0])
            angle=max(angle,math.degrees(math.atan2(math.sqrt(sum(c*c for c in cross)),dot)))
        assert aa['uv'].keys()==bb['uv'].keys()
        for key,values in aa['uv'].items():
            assert len(values)==len(bb['uv'][key])
            maximum=max((abs(float(i)-float(j)) for x,y in zip(values,bb['uv'][key]) for i,j in zip(x,y)),default=0.)
            bylayer[key]=max(bylayer.get(key,0.),maximum);uv=max(uv,maximum)
            if maximum:changed.append({'object':name,'layer':key,'max_component_difference':maximum})
    report={'max_position_m':pos,'max_UV':uv,'max_normal_angle_degrees':angle,'max_normal_component':component,
        'UV_by_layer':bylayer,'changed_UV_object_layers':changed,'topology_winding_exact':True,
        'limits':{'position_m':1e-5,'UV':1e-5,'normal_angle_degrees':.1},
        'note':'Bevel evaluated UV can change last bits on save/reopen; record numeric error, not a false bitwise-identity claim.'}
    write('reopen_validation.json',report)
    assert pos<=1e-5 and uv<=1e-5 and angle<=.1,report
    return report

