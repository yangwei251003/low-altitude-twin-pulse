"""Pure data planning extraction. No engine, modeling, image generation or edits elsewhere."""
from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
ORIGIN=[-7.,0.,8.]
IDS=['PumpFloor','PumpWestWall','PumpEastWall','PumpNorthWall','PumpSouthWestJamb','PumpSouthEastJamb','PumpRoof']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def local(v):return [v[i]-ORIGIN[i] for i in range(3)]
def main():
 layout_path=ROOT/'data/v3/terrain/i2_clinic_layout.json'
 data=json.loads(layout_path.read_text(encoding='utf-8'))
 by_id={s['id']:s for s in data['fixed_solids']}
 shell=[{'id':i,'world_min':by_id[i]['min'],'world_max':by_id[i]['max'],'local_min':local(by_id[i]['min']),'local_max':local(by_id[i]['max'])} for i in IDS]
 q=data['pump_selector'];half=[v*.5 for v in q['size']]
 sweep_min=[min(q['center'][i],q['center'][i]+q['travel'][i])-half[i] for i in range(3)]
 sweep_max=[max(q['center'][i],q['center'][i]+q['travel'][i])+half[i] for i in range(3)]
 inputs=['data/v3/terrain/i2_clinic_layout.json','scripts/v3/world/twin_clinic_waterworks.gd','scripts/v3/twin_session.gd','scripts/v3/art/twin_terrain_visibility.gd','scripts/v2/flight_camera.gd','scripts_tools/v3/capture_clinic_integrated.gd','tests_v3/test_clinic_waterworks.gd','references/v3/concepts/I-B.png']
 report={'status':'PLANNED_ONLY_NOT_MODELED_OR_TESTED','asset_root':'ClinicPumpShell','proposed_world_origin':ORIGIN,'scale':[1,1,1],'front_godot_axis':'+Z','blender_coordinate_mapping':'(localX,-localZ,localY)','world_bounds':[[-12.25,0,3.75],[-1.75,3.5,12.25]],'local_bounds':[[-5.25,0,-4.25],[5.25,3.5,4.25]],'fixed_shell_solids':shell,'wall_segment_count':5,'doorway':{'world_min':[-8.7,.4,12.],'world_max':[-5.3,3.2,12.25],'local_min':[-1.7,.4,4.],'local_max':[1.7,3.2,4.25],'width':3.4,'height':2.8,'physical_floor_step':.4,'note':'Floor ends at Z12; no existing raised threshold/ramp over opening Z12..12.25.'},'independent_fixed_machinery':[by_id[i] for i in ['PumpCabinet','PumpSelectorRail']],'pump_selector':q,'pump_selector_swept_world_aabb':[sweep_min,sweep_max],'relay':{'world_center':data['anchors']['pump_relay'],'size':[.4,.7,.35],'world_aabb':[[-9.2,1.2,6.825],[-8.8,1.9,7.175]]},'current_fade_candidate_ids':['PumpRoof','PumpWestWall','PumpEastWall','PumpNorthWall'],'proposed_render_groups':{'PermanentNavigation':['FloorSurface','WallFeetAndJambs'],'OccludingCover':['WestCover','EastCover','NorthCover','RoofCover']},'proposed_low_wall_band_world_y':[.4,.75],'current_collision':'ExactBoxCollision BoxShape3D on each fixed body; layer1. Selector/relay layer8; no new collision or body written.','existing_route_probes_not_rerun':[[[-7,1.8,15],[-7,1.8,9.4]],[[-7,1.6,14],[-7,1.6,10]]],'planned_budget_not_measured':{'meshes':[6,8],'materials':3,'triangles':[8000,12000]},'inputs':[{'path':s,'sha256':sha(ROOT/s),'bytes':(ROOT/s).stat().st_size} for s in inputs]}
 assert len(shell)==7 and abs(by_id['PumpSouthEastJamb']['min'][0]-by_id['PumpSouthWestJamb']['max'][0]-3.4)<1e-12
 assert sweep_min==[-7.4,1.35,6.825] and sweep_max==[-5.8,1.85,7.175]
 (HERE/'contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'status':report['status'],'solids':len(shell),'wall_segments':5,'doorway':[3.4,2.8],'output':str(HERE/'contract.json')},ensure_ascii=False))
if __name__=='__main__':main()
