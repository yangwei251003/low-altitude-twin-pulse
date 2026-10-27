import itertools, math
import numpy as np
SPECS=[
('BedrockWideFoot',[
('ground',(0,-1,0),0),('uneven_top',(.10,1,-.06),1.75),('top_limit',(0,1,0),2.1),
('east',(1,-.08,.02),2.15),('west',(-1,-.05,-.06),2.12),('front',(0,.04,-1),4.25),('back',(0,.05,1),4.45),
('front_east',(1,.05,-.38),3.50),('front_west',(-1,.08,-.32),3.45),('back_east',(1,.10,.35),3.55),('back_west',(-1,.06,.40),3.75)]),
('ContinuousBearingBackbone',[
('buried_base',(0,-1,0),-.8),('bearing_top',(0,1,0),5.65),
('east',(1,.17,.025),1.85),('west',(-1,.20,-.035),2.05),
('front',(0,.08,-1),4.13),('back',(0,.085,1),4.18),
('front_oblique',(.25,.12,-1),4.60),('back_oblique',(-.22,.13,1),4.60)]),
('FrontInclinedStratum',[
('buried_base',(0,-1,0),-.65),('sloped_top',(.24,1,.18),4.75),('upper_limit',(0,1,0),5.1),
('buried_inner',(-1,.05,.08),.08),('outer_face',(1,.06,-.10),2.10),
('front_end',(-.08,.10,-1),4.25),('fault_edge',(-.10,.20,1),.15),
('front_big_break',(1,.15,-.48),3.88),('lower_break',(1,-.36,.15),1.15)]),
('LowMiddleStratum',[
('buried_base',(0,-1,0),-.45),('low_broad_ledge',(.12,1,-.08),3.02),
('outer_steep_face',(1,.45,.10),3.55),('outer_lower_face',(1,-.10,-.08),2.10),
('buried_inner',(-1,.04,0),-.20),('front_edge',(-.06,.15,-1),1.70),('rear_edge',(.07,.14,1),1.90),
('front_diagonal',(1,.20,-.50),3.15)]),
('RearHighStratum',[
('buried_base',(0,-1,0),-.95),('rear_high_ledge',(.27,1,-.14),5.05),('upper_limit',(0,1,0),5.5),
('outer_slanted_face',(1,.25,.04),3.30),('outer_lower_face',(1,-.18,.08),2.00),
('buried_inner',(-1,.04,-.05),.20),('fault_edge',(.10,.18,-1),.25),('rear_edge',(-.08,.12,1),4.55),
('rear_big_break',(1,.18,.40),4.10)]),
('WestBroadShoulder',[
('buried_base',(0,-1,0),-.60),('unequal_high_shoulder',(-.16,1,.12),4.30),
('outer_upper',(-1,.20,-.06),2.95),('outer_lower',(-1,-.10,.08),2.10),('buried_inner',(1,.02,-.02),.12),
('front_end',(.08,.12,-1),3.90),('rear_end',(.10,.15,1),3.90),
('front_break',(-1,.20,-.40),3.90),('rear_break',(-1,.23,.37),4.20)])]
def poly_geometry(specs):
 A=np.array([r[1] for r in specs],dtype=float);B=np.array([r[2] for r in specs],dtype=float);points=[]
 for ids in itertools.combinations(range(len(A)),3):
  aa=A[list(ids)]
  if abs(np.linalg.det(aa))<1e-10:continue
  q=np.linalg.solve(aa,B[list(ids)])
  if np.all(A@q<=B+1e-8) and not any(np.linalg.norm(q-v)<1e-7 for v in points):points.append(q)
 if len(points)<4:return np.zeros((0,3)),[],[]
 P=np.array(points);faces=[];authored=[]
 for i,(name,normal,d) in enumerate(specs):
  ids=[j for j,q in enumerate(P) if abs(float(A[i]@q-B[i]))<1e-6]
  if len(ids)<3:continue
  n=np.array(normal,dtype=float);n/=np.linalg.norm(n);axis=np.eye(3)[np.argmin(np.abs(n))]
  u=np.cross(n,axis);u/=np.linalg.norm(u);v=np.cross(n,u);centre=P[ids].mean(0)
  ids.sort(key=lambda j:math.atan2(float((P[j]-centre)@v),float((P[j]-centre)@u)))
  faces.append(tuple(ids));authored.append({'name':name,'normal_godot':normal,'plane_max_dot':d,'vertex_ids':ids})
 return P,faces,authored
def poly_volume(P,faces):
 return abs(sum(float(np.dot(P[f[0]],np.cross(P[f[k]],P[f[k+1]])))/6 for f in faces for k in range(1,len(f)-1)))
