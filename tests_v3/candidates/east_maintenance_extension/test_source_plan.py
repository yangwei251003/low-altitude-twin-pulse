"""Pure source-plan checks. Does not load Blender, Godot, collision or GLB."""
from pathlib import Path
import importlib.util,sys,unittest,json,math
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('east_paving_plan',ROOT/'asset_sources/v3/i2_east_maintenance_extension/p1/plan.py')
plan=importlib.util.module_from_spec(spec);spec.loader.exec_module(plan)

class SourcePlan(unittest.TestCase):
 @classmethod
 def setUpClass(cls): cls.parts,cls.report=plan.build()

 def test_holes_are_all_actual_low_fixed_contacts_in_domain(self):
  layout=json.loads((ROOT/'data/v3/terrain/i2_shared_access_layout.json').read_text(encoding='utf-8'))
  found={}
  for body in layout['fixed']:
   lo=[c-s/2 for c,s in zip(body['center'],body['size'])]
   hi=[c+s/2 for c,s in zip(body['center'],body['size'])]
   if lo[1]<=0<hi[1] and max(lo[0],16.9)<min(hi[0],24.5) and max(lo[2],2)<min(hi[2],15.6): found[body['id']]=(lo[0],hi[0],lo[2],hi[2])
  # The two narrower EastPiers are already contained in their real footplates.
  outer={name for name,r in found.items() if not any(other!=name and s[0]<=r[0] and s[1]>=r[1] and s[2]<=r[2] and s[3]>=r[3] for other,s in found.items())}
  self.assertEqual(outer,{h['id'] for h in self.report['body_holes']})

 def test_area_from_independent_union_sweep(self):
  removed=[plan.BANK]+[h['rect'] for h in self.report['body_holes']]
  xs=sorted({plan.OUTER[0],plan.OUTER[1]}|{x for r in removed for x in r[:2]})
  lost=0
  for a,b in zip(xs,xs[1:]):
   spans=sorted((r[2],r[3]) for r in removed if r[0]<(a+b)/2<r[1]); end=-math.inf;length=0
   for start,stop in spans:
    length+=max(0,stop-max(start,end));end=max(end,stop)
   lost+=(b-a)*length
  self.assertAlmostEqual(plan.area(plan.OUTER)-lost,self.report['net_paving_m2'],places=8)

 def test_every_cell_top_has_no_bank_or_body_overlap(self):
  for part in self.parts:
   for face in part['faces']:
    p=[part['vertices'][i] for i in face]
    if not all(abs(v[2]-p[0][2])<1e-12 for v in p): continue
    x=sum(v[0] for v in p)/len(p)+plan.ORIGIN[0]
    z=-sum(v[1] for v in p)/len(p)+plan.ORIGIN[2]
    self.assertFalse(plan.inside(x,z,plan.BANK))
    self.assertFalse(any(plan.inside(x,z,h['rect']) for h in self.report['body_holes']))

 def test_clear_route_and_no_geometry_above_original_top(self):
  for h in self.report['body_holes']: self.assertLess(h['rect'][1],21.5)
  for part in self.parts:
   for p in part['vertices']:
    self.assertGreaterEqual(p[2],-.18000001);self.assertLessEqual(p[2],0)
  route=[p for p in self.parts if p['name'].startswith('ClearRoute')]
  self.assertEqual(len(route),3)
  self.assertTrue(all(p['role']=='concrete' and p['top']==0 for p in route))

 def test_north_has_no_added_full_or_half_seal(self):
  for part in self.parts:
   if part['name']!='ShallowSeals': continue
   for face in part['faces']:
    p=[part['vertices'][i] for i in face]
    if not all(abs(v[2]+.012)<1e-12 for v in p): continue
    x=sum(v[0] for v in p)/len(p)+plan.ORIGIN[0]
    z=-sum(v[1] for v in p)/len(p)+plan.ORIGIN[2]
    if 21.6<x<24.4: self.assertGreaterEqual(z,2.02)

 def test_positive_closed_source_solids(self):
  for part in self.parts:
   volume=0
   for face in part['faces']:
    a=part['vertices'][face[0]]
    for j in range(1,len(face)-1):
     b=part['vertices'][face[j]];c=part['vertices'][face[j+1]]
     volume+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6
   self.assertGreater(volume,0,part['name'])

if __name__=='__main__': unittest.main()
