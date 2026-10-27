"""Pure, bounded layout analysis. No Blender/engine, no writes outside this folder."""
from pathlib import Path
import hashlib
import itertools
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ORIGIN = [7.0, 0.0, -6.0]
POSTS = [('NW',2.5,-9.5),('NE',11.5,-9.5),('SW',2.5,-2.5),('SE',11.5,-2.5)]
MATERIAL_DIR = ROOT/'asset_sources/v3/clinic_gravity/revision_v4/textures'
REGIONS = {'post':[.5,0,.75,.5], 'beam':[.75,0,1,.5], 'steel':[.5,.5,.75,.75]}


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def overlap(a,b):
    return all(min(a['max'][i],b['max'][i])-max(a['min'][i],b['min'][i])>1e-8 for i in range(3))


def make_plan():
    parts=[];bolts=[]
    def box(name,lo,hi,material):
        assert all(hi[i]>lo[i] for i in range(3))
        parts.append({'name':name,'min':lo,'max':hi,'material_region':material})
    for tag,x,z in POSTS:
        box('FootPlate_'+tag,[x-.42,0,z-.42],[x+.42,.14,z+.42],'steel')
        box('PostBody_'+tag,[x-.3,.14,z-.3],[x+.3,4.1,z+.3],'post')
        # Column carries the beam at Y4.1. Only the two side shoulders continue
        # to Y4.12; they never enter the actual beam's central 0.50m strip.
        box('PostShoulder_'+tag+'_North',[x-.3,4.1,z-.30],[x+.3,4.12,z-.25],'post')
        box('PostShoulder_'+tag+'_South',[x-.3,4.1,z+.25],[x+.3,4.12,z+.30],'post')
        box('Bearing_'+tag+'_North',[x-.39,4.12,z-.39],[x+.39,4.6,z-.25],'beam')
        box('Bearing_'+tag+'_South',[x-.39,4.12,z+.25],[x+.39,4.6,z+.39],'beam')
        # U collar: exact side of the beam, not a duplicate box through it.
        if x < 7: lo,hi=x-.39,2.2
        else: lo,hi=11.8,x+.39
        box('Bearing_'+tag+'_End',[lo,4.12,z-.25],[hi,4.6,z+.25],'beam')
        for dx,dz in itertools.product([-.35,.35],repeat=2):
            bolts.append({'name':f'FootBolt_{tag}_{dx}_{dz}','base':[x+dx,.14,z+dz],'axis':[0,1,0],'washer_radius':.045,'hex_radius':.032,'washer_depth':.005,'head_depth':.018})
        for side,dx in itertools.product([-1,1],[-.17,.17]):
            bolts.append({'name':f'BearingBolt_{tag}_{side}_{dx}','base':[x+dx,4.36,z+side*.39],'axis':[0,0,side],'washer_radius':.052,'hex_radius':.040,'washer_depth':.006,'head_depth':.021})
    for label,z in [('North',-9.5),('South',-2.5)]:
        box('Beam_'+label,[2.2,4.1,z-.25],[11.8,4.6,z+.25],'beam')
    intersections=[(a['name'],b['name']) for a,b in itertools.combinations(parts,2) if overlap(a,b)]
    assert not intersections, intersections
    layout_path=ROOT/'data/v3/terrain/i2_clinic_layout.json'
    layout=json.loads(layout_path.read_text(encoding='utf-8'))
    conflicts=[(a['name'],b['id']) for a in parts for b in layout['fixed_solids'] if overlap(a,b)]
    # Root explicitly replaces this old single leg. Retain the real conflict in
    # the report rather than treating it as a clearance pass before removal.
    pending_removal=[item for item in conflicts if item[1]=='EastLandingLeg']
    unexpected=[item for item in conflicts if item[1]!='EastLandingLeg']
    assert not unexpected, unexpected
    dynamic=[]
    for row in layout['moving_parts']:
        # Actual runtime: clinic level3.5..4.5 +0.5 gives deck top4..5.
        dynamic.append({'name':row['id'],'min':[row['offset'][0]-row['size'][0]/2,4+row['offset'][1]-row['size'][1]/2,row['offset'][2]-row['size'][2]/2],
                        'max':[row['offset'][0]+row['size'][0]/2,5+row['offset'][1]+row['size'][1]/2,row['offset'][2]+row['size'][2]/2]})
    for id,tank in layout['tanks'].items():
        x,z=tank['center_xz'];w,h,d=tank['inner_size'];t=tank['wall']
        dynamic.append({'name':id,'min':[x-w/2-t,tank['base_y']-t,z-d/2-t],'max':[x+w/2+t,tank['base_y']+h,z+d/2+t]})
    dynamic_conflicts=[(a['name'],b['name']) for a in parts for b in dynamic if overlap(a,b)]
    assert not dynamic_conflicts, dynamic_conflicts
    # Floor support contacts are exact planes, not a floating visual shortcut.
    floors=[{'name':'rear_proposed','min':[2,4.6,-10],'max':[12,5,-6]}, {'name':'front_existing','min':[2,4.6,-6],'max':[12,5,-2]}]
    contact=[]
    for floor in floors:
        names=[p['name'] for p in parts if abs(p['max'][1]-floor['min'][1])<1e-9 and all(min(p['max'][i],floor['max'][i])-max(p['min'][i],floor['min'][i])>0 for i in [0,2])]
        assert names;contact.append({'floor':floor['name'],'contact_y':4.6,'parts':names})
    textures={}
    for role in ['BaseColor','Roughness','Metallic','Normal']:
        path=MATERIAL_DIR/f'CG_V4_{role}.png';assert path.is_file()
        textures[role]={'path':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':sha(path)}
    result={'status':'prepared_analytic_layout_only_not_constructed_or_physics_tested','origin_world':ORIGIN,
            'parts':parts,'bolts':bolts,'material_regions':REGIONS,'textures':textures,'layout_sha256':sha(layout_path),
            'world_aabb':{'min':[2.08,0,-9.92],'max':[11.92,4.6,-2.08]},
            'local_aabb':{'min':[-4.92,0,-3.92],'max':[4.92,4.6,3.92]},
            'structure_count':len(parts),'detail_count':2*len(bolts),'triangle_budget':8000,
            'same_support_box_volume_overlaps':intersections,'existing_layout_conflicts':conflicts,
            'required_old_body_removal':pending_removal,'unexpected_layout_conflicts':unexpected,'moving_tank_conflicts':dynamic_conflicts,
            'floor_contacts':contact,'moving_reservations':dynamic,
            'clearances':{'deck_x_to_beam_m':.2,'deck_x_to_bearing_m':.11,'deck_x_to_foot_m':.08,
                          'under_beam_top_y':4.1,'west_east_posts_inner_width_m':8.4,'north_south_posts_inner_depth_m':6.4},
            'limits':['No structural load/stress engineering certification','No actual Blender vertex/topology or material result yet',
                      'No runtime sweep; root must remove old EastLandingLeg and integrate rear floor/collision',
                      'No diagonal bracing across flight corridors; these are not force-simulated steel joints']}
    return result


if __name__=='__main__':
    plan=make_plan();(HERE/'support_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
    (HERE/'layout_readonly_snapshot.json').write_bytes((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_bytes())
    print(json.dumps({'prepared':True,'structure':plan['structure_count'],'details':plan['detail_count'],
                      'unexpected_conflicts':len(plan['unexpected_layout_conflicts'])+len(plan['moving_tank_conflicts']),
                      'pending_old_leg_removal':plan['required_old_body_removal']}))
