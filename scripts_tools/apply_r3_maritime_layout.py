"""Call after the authored R3 structures/decorations are built, before writing data.
No files are written by importing this module or calling its pure data transform.
"""
from copy import deepcopy

WATER_ROUTES = {
    'R3-P11>R3-P02': {
        'id':'R3_maintenance_return','vessel':'maintenance_boat',
        'poi_ids':['R3-P11','R3-P02'],
        'points_xz_m':[[78,355],[66,355],[64,333],[86,300],[68,255],[38,218],[37,195],[61,163],[66,139],[68,121]],
        'poi_waypoint_indices':[0,9],'speed_mps':3.2,'clearance_radius_m':3.4,
        'defend_stage_id':'M09-S3',
    },
    'R3-P21>R3-P19>R3-P11': {
        'id':'R3_rescue_south_coast','vessel':'rescue_raft',
        'poi_ids':['R3-P21','R3-P19','R3-P11'],
        'points_xz_m':[[535,380],[515,420],[480,450],[415,475],[345,487],[325,478],[250,448],[205,487],[160,490],[105,450],[65,410],[60,370],[78,355]],
        'poi_waypoint_indices':[0,5,12],'speed_mps':3.2,'clearance_radius_m':3.4,
    },
}

def apply_r3_maritime_layout(layout, region):
    """Return copies; task/stage/action/reward IDs and schema are unchanged."""
    layout=deepcopy(layout);region=deepcopy(region)
    assert layout['region_id']=='R3' and region['id']=='R3'
    positions={'R3-P02':[90,110],'R3-P11':[87,345]}
    for poi in region['pois']:
        if poi['id'] in positions:poi['position_xz_m']=positions[poi['id']].copy()
    layout['poi_positions'].update(deepcopy(positions))
    layout['water_routes']=deepcopy(WATER_ROUTES)
    additions=[
        {'id':'R3_north_harbor_access','points':[[100,100,0],[90,110,0]],'width':4.0,'bridge':False},
        {'id':'R3_west_maintenance_access','points':[[135,390,0],[115,345,0],[108,345,0]],'width':4.0,'bridge':False},
    ]
    replace_ids={a['id'] for a in additions}
    layout['roads']=[r for r in layout['roads'] if r.get('id') not in replace_ids]+additions
    # The generator's generic automatic 18m land pad must not fill these berths.
    layout['land']=[p for p in layout['land'] if p['id'] not in {'pier_R3-P02','pier_R3-P11','R3_north_harbor_quay','R3_west_maintenance_quay'}]
    # Low solid quays are land supports, not fly-under bridges. Berths stay outside.
    layout['land'] += [
        {'id':'R3_north_harbor_quay','points':[[64,107],[85,107],[85,113],[64,113]],'height':.5,'color':'9b9e90'},
        {'id':'R3_west_maintenance_quay','points':[[76,340],[110,340],[110,350],[76,350]],'height':.5,'color':'9b9e90'},
    ]
    for sector in region.get('sectors',[]):
        points=[p['position_xz_m'] for p in region['pois'] if p['sector_id']==sector['id']]
        if points:sector['bounds_xz_m']=[max(0,min(p[0] for p in points)-30),max(0,min(p[1] for p in points)-30),min(600,max(p[0] for p in points)+30),min(500,max(p[1] for p in points)+30)]
    # Entry identity stays stable; recompute only its old POI target coordinate.
    for entry in layout.get('entries',[]):
        if entry.get('target',[None])[0:3:2]==[175,100]:entry['target']=[90,11,110]
    return layout,region
