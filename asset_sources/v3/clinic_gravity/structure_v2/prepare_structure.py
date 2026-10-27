"""Static, deterministic proposed-solid review; no Blender/Godot import or execution."""
from pathlib import Path
import json, hashlib

ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
LAYOUT=ROOT/'data/v3/terrain/i2_clinic_layout.json'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def box(name,lo,hi,role): return {'id':name,'min':lo,'max':hi,'role':role}
def overlap(a,b):
    depth=[min(a['max'][i],b['max'][i])-max(a['min'][i],b['min'][i]) for i in range(3)]
    return depth if all(d>1e-7 for d in depth) else None
def segment_hit(a,b,solid,half=(0,0,0)):
    lo=[solid['min'][i]-half[i] for i in range(3)]
    hi=[solid['max'][i]+half[i] for i in range(3)]
    enter,leave=0.,1.
    for i in range(3):
        d=b[i]-a[i]
        if abs(d)<1e-12:
            if a[i]<lo[i] or a[i]>hi[i]: return None
        else:
            t0,t1=(lo[i]-a[i])/d,(hi[i]-a[i])/d
            enter=max(enter,min(t0,t1));leave=min(leave,max(t0,t1))
            if enter>leave: return None
    return enter
def swept(name,center,size,travel):
    end=[center[i]+travel[i] for i in range(3)]
    return box(name,[min(center[i],end[i])-size[i]/2 for i in range(3)],
               [max(center[i],end[i])+size[i]/2 for i in range(3)],'existing moving envelope')

def main():
    layout=json.loads(LAYOUT.read_text(encoding='utf8'))
    parts=[]
    for tag,x,z in [('NW',-11.2,-9.2),('NE',-5.8,-9.2),('SW',-11.2,-6.3),('SE',-5.8,-6.3)]:
        parts.extend([
            box('SupportLeg_'+tag,[x-.3,0,z-.3],[x+.3,5.6,z+.3],'0.6m post'),
            box('FootPlate_'+tag,[x-.42,0,z-.42],[x+.42,.14,z+.42],'real 0.84m steel foot'),
            box('BearingNode_'+tag,[x-.39,5.12,z-.39],[x+.39,5.6,z+.39],'real steel beam/post joint'),
        ])
    for tag,z in [('North',-9.2),('South',-6.3)]:
        parts.append(box('LongitudinalBeam_'+tag,[-11.5,5.2,z-.25],[-5.5,5.6,z+.25],'6m real box beam'))
    replacements=['UpperDeckLeg']
    old_hits=[]
    for p in parts:
        for old in layout['fixed_solids']:
            d=overlap(p,old)
            if d:old_hits.append({'candidate':p['id'],'existing':old['id'],'intersection_depth_m':d,
                                  'classification':'expected_old_post_replacement' if old['id'] in replacements else 'UNEXPECTED'})
    dynamic=[]
    for key in ['gravity_valve','pump_selector']:
        v=layout[key];dynamic.append(swept(key,v['center'],v['size'],v['travel']))
    v=layout['interlock_bolt'];dynamic.append(swept('interlock_bolt',v['center'],v['size'],v['park_offset']))
    for p in layout['moving_parts']:
        dynamic.append(swept(p['id'],[p['offset'][0],p['offset'][1]+4,p['offset'][2]],p['size'],[0,1,0]))
    mechanism_hits=[{'candidate':p['id'],'mechanism':d['id'],'depth':overlap(p,d)} for p in parts for d in dynamic if overlap(p,d)]
    routes=[
        {'name':'existing low pump doorway','from':[-7,1.8,15],'to':[-7,1.8,9.4],'source':'test_clinic_waterworks.gd:241'},
        {'name':'existing centre underpass','from':[0,2.3,0],'to':[0,2.3,-7],'source':'test_clinic_waterworks.gd:243'},
        {'name':'existing centre ascent','from':[0,3,10],'to':[0,10,10],'source':'test_clinic_waterworks.gd:245'},
        {'name':'existing raised access crossing','from':[-4.5,5.8,-4],'to':[4.5,5.8,-4],'source':'test_clinic_session.gd:289-290'},
        {'name':'new required upper deck underside corridor','from':[-8,3,-10.2],'to':[-8,3,-4],'source':'parent instruction + v1 study; not an existing engine QA'},
    ]
    envelopes={'tr01':[1.4,.48,1.4],'hx02':[2.2,.68,1.9]}
    route_results=[]
    for route in routes:
        for frame,size in envelopes.items():
            half=[s/2 for s in size]
            hits=[p['id'] for p in parts if segment_hit(route['from'],route['to'],p,half) is not None]
            existing=[p['id'] for p in layout['fixed_solids'] if p['id'] not in replacements and segment_hit(route['from'],route['to'],p,half) is not None]
            route_results.append({**route,'frame':frame,'axis_aligned_size':size,'new_hits':hits,'existing_fixed_hits':existing,
                                  'limitation':'exact AABB sweep of unrotated BoxShape envelope only, no Godot margins/rotated attitude/real flight'})
    actions=json.loads((ROOT/'data/v3/actions/clinic_action.json').read_text(encoding='utf8'))
    targets=[]
    def collect(value):
        if isinstance(value,dict):
            if value.get('region')=='I2' and isinstance(value.get('position'),list):targets.append({'id':value.get('id'),'position':value['position']})
            for child in value.values():collect(child)
        elif isinstance(value,list):
            for child in value:collect(child)
    collect(actions)
    targets += [{'id':'anchor:'+k,'position':v} for k,v in layout['anchors'].items()]
    targets += [{'id':'gravity_open','position':[-6.8,7,-5]}, {'id':'high_valve_operator_pose','position':[-10,7,-2.5]}]
    target_hits=[{'id':t['id'],'candidate':p['id']} for t in targets for p in parts if segment_hit(t['position'],t['position'],p) is not None]
    los=[]
    for end in [[-8,7,-5],[-6.8,7,-5]]:
        los.append({'from':[-10,7,-2.5],'to':end,'new_hits':[p['id'] for p in parts if segment_hit([-10,7,-2.5],end,p) is not None]})
    sources=['data/v3/terrain/i2_clinic_layout.json','data/v3/actions/clinic_action.json','data/v2/world_content.json','scripts/v2/flight_body.gd','scripts/v2/catalog.gd','tests_v3/test_clinic_waterworks.gd','tests_v3/test_clinic_session.gd','scripts/v3/world/twin_clinic_waterworks.gd']
    report={'status':'STATIC_CANDIDATE_NO_ENGINE_OR_BLENDER','world_origin':[-9,6,-7], 'parts':parts,'replace_existing':replacements,
            'intersections_with_old_solids':old_hits,'new_mechanism_intersections':mechanism_hits,'route_sweeps':route_results,'target_points':targets,'target_hits':target_hits,'high_valve_los':los,
            'clearances':{'HX02_at_x_minus8_to_east_post_m':.8,'HX02_at_x_minus8_to_west_post_m':1.8,'beam_underside_to_HX02_top_at_y3_m':1.86,'front_joint_bottom_to_WestLanding_top_m':.12,'front_beam_to_WestLanding_z_gap_m':.05},
            'source_hashes':{s:sha(ROOT/s) for s in sources},'must_retest':'Root must update actual solids and validate rotated/full FlightBody, collider margins, interaction LOS, real default camera; no art or structural-engineering pass claimed.'}
    report['unexpected_static_hits']=[x for x in old_hits if x['classification']=='UNEXPECTED']
    report['static_conflicts']=len(report['unexpected_static_hits'])+len(mechanism_hits)+len(target_hits)+sum(bool(r['new_hits']) for r in route_results)+sum(bool(r['new_hits']) for r in los)
    (OUT/'structure_plan.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'parts':len(parts),'static_conflicts':report['static_conflicts'],'known_replacement_intersections':len(old_hits),'route_cases':len(route_results)},ensure_ascii=False))

if __name__=='__main__':main()
