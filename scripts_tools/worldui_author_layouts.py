"""Authored four-world layouts. Reproducible, with preserved original coordinates."""
from pathlib import Path
import json, math
from apply_r3_maritime_layout import apply_r3_maritime_layout
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'docs/v2/data/world_content.json'
OUT=ROOT/'data/worldui'
OUT.mkdir(parents=True,exist_ok=True)
original=json.loads(SOURCE.read_text(encoding='utf-8-sig'))
legacy=ROOT/'docs/v2/data/worldui_legacy_layout.json'
if not legacy.exists(): legacy.write_text(json.dumps({r['id']:{p['id']:p['position_xz_m'] for p in r['pois']} for r in original['regions']},ensure_ascii=False,indent=2),encoding='utf-8')
points={
'R1':[(160,130),(130,145),(100,205),(60,150),(300,70),(380,95),(465,95),(535,155),(120,275),(190,305),(110,350),(60,390),(385,250),(445,225),(520,265),(450,315),(100,440),(190,440),(245,475),(60,480),(385,405),(465,390),(530,435),(450,470)],
'R2':[(90,85),(145,115),(190,165),(105,185),(300,95),(345,140),(410,105),(490,155),(70,300),(130,330),(190,285),(170,390),(295,265),(355,295),(395,245),(440,330),(245,425),(305,455),(365,420),(410,465),(500,365),(535,415),(550,300),(495,255)],
'R3':[(100,100),(175,100),(200,175),(160,225),(285,105),(350,100),(405,135),(470,170),(105,240),(155,310),(195,355),(135,390),(320,235),(385,235),(440,280),(470,335),(230,380),(290,395),(335,435),(200,415),(390,365),(425,405),(475,380),(505,330)],
'R4':[(235,170),(185,175),(130,155),(95,110),(345,90),(410,120),(490,90),(545,150),(65,245),(115,280),(135,350),(75,405),(475,240),(535,285),(470,335),(535,385),(70,460),(125,440),(145,490),(55,345),(465,445),(525,455),(575,400),(565,490)]}
polys={
'R1':[[[-16,-16],[205,-16],[165,90],[180,155],[235,220],[265,280],[220,355],[280,430],[290,516],[-16,516]],[[270,-16],[616,-16],[616,516],[360,516],[348,425],[300,355],[335,285],[310,215],[240,140],[230,80]]],
'R2':[[[-16,-16],[616,-16],[616,516],[-16,516]]],
'R3':[[[75,35],[220,15],[320,55],[420,45],[540,110],[575,200],[500,250],[545,345],[475,430],[345,465],[245,425],[175,470],[80,400],[115,300],[50,210],[85,170],[130,175],[145,120],[80,140]]],
'R4':[[[-16,-16],[616,-16],[616,516],[420,516],[420,235],[350,190],[250,190],[180,235],[180,516],[-16,516]]]}
roadpoints={
'R1':[[[160,130,0],[157,146,0],[130,145,0],[100,205,0],[120,275,0],[190,305,0],[110,350,0],[100,440,0],[245,475,0]],[[300,70,0],[380,95,0],[465,95,0],[535,155,0],[445,225,0],[385,250,0],[450,315,0],[385,405,0],[450,470,0]],[[130,145,3],[270,150,3]],[[230,305,4],[345,315,4]]],
'R2':[[[90,85,0],[145,115,0],[190,165,0],[235,215,0],[295,265,0],[355,295,0],[440,330,0],[500,365,0],[535,415,0]],[[105,185,0],[70,300,0],[130,330,0],[170,390,0],[245,425,0],[305,455,0]],[[300,95,0],[345,140,0],[410,105,0],[490,155,0],[495,255,0]]],
'R3':[[[100,100,0],[175,100,0],[200,175,0],[160,225,0],[155,310,0],[195,355,0],[290,395,0],[390,365,0],[470,335,0]],[[285,105,0],[350,100,0],[405,135,0],[470,170,0],[385,235,0],[440,280,0]],[[105,240,0],[135,390,0],[200,415,0]]],
'R4':[[[235,170,0],[185,175,0],[130,155,0],[95,110,0],[345,90,0],[410,120,0],[490,90,0],[545,150,0]],[[90,95,0],[65,245,0],[115,280,0],[135,350,0],[125,440,0],[145,490,0]],[[490,90,0],[475,240,0],[535,285,0],[470,335,0],[465,445,0],[565,490,0]]]}
def inside(x,z,poly):
 c=False
 for (ax,az),(bx,bz) in zip(poly,poly[1:]+poly[:1]):
  if (az>z)!=(bz>z) and x<(bx-ax)*(z-az)/(bz-az)+ax:c=not c
 return c
def surface(layout,x,z):
 return max([p['height'] for p in layout['land'] if inside(x,z,p['points'])],default=-3)
def rect(x,z,w,l):return [[x-w/2,z-l/2],[x+w/2,z-l/2],[x+w/2,z+l/2],[x-w/2,z+l/2]]
manifest={}
for region in original['regions']:
 rid=region['id'];region['layout_revision']=1
 for p,xy in zip(region['pois'],points[rid]):p['position_xz_m']=list(xy)
 for sec in region['sectors']:
  ps=[p['position_xz_m'] for p in region['pois'] if p['sector_id']==sec['id']]
  sec['bounds_xz_m']=[max(0,min(p[0] for p in ps)-30),max(0,min(p[1] for p in ps)-30),min(600,max(p[0] for p in ps)+30),min(500,max(p[1] for p in ps)+30)]
 layout={'revision':1,'region_id':rid,'water_level':-.6,'land':[{'id':'land_'+str(i),'points':p,'height':0,'color':{'R1':'a5b39a','R2':'918c72','R3':'849788','R4':'777f7d'}[rid]} for i,p in enumerate(polys[rid])],'roads':[{'points':p,'width':{'R1':7,'R2':6,'R3':5.5,'R4':10}[rid],'bridge':any(v[2]>0 for v in p)} for p in roadpoints[rid]],'structures':[],'decorations':[],'poi_positions':{p['id']:p['position_xz_m'] for p in region['pois']}}
 if rid=='R3':
  layout['land'].insert(0,{'id':'sandy_shore','points':polys[rid][0],'height':-.25,'color':'a89f7f'})
  layout['land'][1]['points']=[[300+(x-300)*.973,250+(z-250)*.973] for x,z in polys[rid][0]]
 if rid=='R2':
  for ident,poly,h in [('west_foot',[[-16,-16],[70,-16],[85,80],[65,170],[35,220],[-16,220]],4),('west_slope',[[-16,-16],[50,-16],[65,80],[45,170],[15,215],[-16,210]],10),('upper',[[270,20],[570,30],[585,210],[470,215],[430,175],[300,175]],8),('middle',[[15,230],[190,235],[215,300],[210,410],[130,455],[20,430]],4),('ridge_west',[[-16,-16],[35,-16],[50,90],[30,170],[5,210],[-16,200]],20),('ridge_east',[[570,225],[616,200],[616,516],[590,516],[555,450],[575,360]],22)]:layout['land'].append({'id':ident,'points':poly,'height':h,'color':'9d967e' if h<12 else '797c70'})
 # Local terrain platforms are explicit, with authored shore supports for operations.
 for p in region['pois']:
  x,z=p['position_xz_m']
  if surface(layout,x,z)<-1:layout['land'].append({'id':'pier_'+p['id'],'points':rect(x,z,18,18),'height':0,'color':'9b9e90'})
 # Place meaningful clusters beside each service/work site, with space reserved for all action offsets.
 protected=[tuple(p['position_xz_m']) for p in region['pois']]
 for collection in ['missions','airframe_challenges','mode_configs']:
  for job in original[collection]:
   if job['region_id']!=rid:continue
   for st in job.get('stages',[job]):
    for a in st.get('actions',[])+st.get('optional_actions',[]):
     p=layout['poi_positions'].get(a.get('poi_id',''))
     if p:
      o=a.get('offset_xz_m',[0,0]);protected.append((p[0]+o[0],p[1]+o[1]))
 for i,p in enumerate(region['pois']):
  x,z=p['position_xz_m'];kind={'R1':['research','workshop','test_frame','research'],'R2':['substation','solar','battery','solar'],'R3':['turbine','workshop','turbine','solar'],'R4':['crane','container','warehouse','container']}[rid][i%4]
  sizes={'research':(23,10,15),'workshop':(16,6,12),'test_frame':(10,7,3),'substation':(12,6,9),'solar':(14,4,8),'battery':(12,4,7),'turbine':(4,27,4),'crane':(24,23,8),'container':(12,5.6,6),'warehouse':(24,10,16)}
  w,h,l=sizes[kind]; chosen=None
  for dx,dz in [(19,-22),(-24,-20),(27,15),(-27,20),(0,-34),(35,0)]:
   xx,zz=x+dx,z+dz
   if surface(layout,xx,zz)<-1 or any(surface(layout,cx,cz)!=surface(layout,xx,zz) for cx,cz in rect(xx,zz,w,l)):continue
   if any(abs(xx-px)<w/2+5 and abs(zz-pz)<l/2+5 for px,pz in protected):continue
   chosen=(xx,zz);break
  if chosen:
   xx,zz=chosen;layout['structures'].append({'id':rid+'_'+kind+'_'+str(i),'asset':kind,'x':xx,'z':zz,'w':w,'h':h,'l':l,'base_y':surface(layout,xx,zz),'style':i%4,'yaw':0})
  # Non-repetitive small service group; no city furniture or street intersections.
  for n,(dx,dz) in enumerate([(9,-8),(-11,7)]):
   xx,zz=x+dx,z+dz
   if surface(layout,xx,zz)>=0:layout['decorations'].append({'asset':'planter' if rid=='R1' else ('rock' if rid in ['R2','R3'] else 'cargo'),'x':xx,'z':zz,'y':surface(layout,xx,zz),'variant':(i+n)%3})
 # Authored supporting complexes and topographic dressing, all reserved away from tasks.
 def add_structure(kind,x,z,yaw=0):
  w,h,l=sizes[kind]
  base=surface(layout,x,z)
  if base<0 or any(surface(layout,a,b)!=base for a,b in rect(x,z,w,l)):return False
  if any(abs(x-px)<w/2+5 and abs(z-pz)<l/2+5 for px,pz in protected):return False
  if any(abs(x-o['x'])<(w+o['w'])/2+2 and abs(z-o['z'])<(l+o['l'])/2+2 for o in layout['structures']):return False
  layout['structures'].append({'id':rid+'_complex_'+str(len(layout['structures'])),'asset':kind,'x':x,'z':z,'w':w,'h':h,'l':l,'base_y':base,'style':0,'yaw':yaw})
  return True
 for item in layout['structures']:
  if item['id']==rid+'_'+{'R1':'research','R2':'substation','R3':'turbine','R4':'crane'}[rid]+'_0':
   item['x'],item['z']={'R1':(142,135),'R2':(106,75),'R3':(119,99),'R4':(246,162)}[rid];item['base_y']=surface(layout,item['x'],item['z'])
   if rid=='R1':
    item['visual_scale']=.7
    for dimension in ['w','h','l']:item[dimension]*=.7
 if rid=='R1':
  for x,z in [(125,85),(318,90),(365,70),(420,120),(430,250),(410,410)]:add_structure('test_frame',x,z)
 elif rid=='R2':
  for x,z in [(110,91),(129,90),(129,107),(89,47),(106,47),(89,61),(320,62),(337,62),(354,62),(320,78),(337,78),(505,340),(520,340),(505,325),(115,275),(132,275)]:add_structure('solar',x,z)
  for x,z in [(110,124),(108,45),(142,66),(370,72),(470,290),(90,270)]:add_structure('battery',x,z)
 elif rid=='R3':
  for x,z in [(90,70),(127,292),(265,70),(370,300),(430,385)]:add_structure('turbine',x,z)
 elif rid=='R4':
  for x,z in [(215,130),(215,140),(235,130),(235,140),(275,140),(295,140),(135,215),(135,225),(135,235),(150,320),(150,330),(455,280),(455,290),(455,300),(480,400),(500,400)]:add_structure('container',x,z)
  for x,z in [(285,115),(480,185),(115,395)]:add_structure('warehouse',x,z)
 if rid=='R3':layout['roads'][0]['points'].insert(1,[120,110,0])
 if rid=='R4':
  for i,item in enumerate(s for s in layout['structures'] if s['asset']=='container'):
   item['asset']=['container_low','container_offset','container','container_low'][i%4]
   if item['asset']=='container_low':item['h']=2.8
 # Remove early decorations now covered by a custom landmark placement.
 layout['decorations']=[d for d in layout['decorations'] if not any(abs(d['x']-s['x'])<s['w']/2+2 and abs(d['z']-s['z'])<s['l']/2+2 for s in layout['structures'])]
 # Coasts and terrace edges use irregular clusters, never a city road grid.
 def safe_decor(x,z,radius=2.3):
  if surface(layout,x,z)<0:return False
  if any(math.hypot(x-px,z-pz)<radius+5 for px,pz in protected):return False
  return not any(abs(x-o['x'])<o['w']/2+radius and abs(z-o['z'])<o['l']/2+radius for o in layout['structures'])
 for land in layout['land']:
  if rid not in ['R2','R3']:continue
  ps=land['points']
  for edge,((ax,az),(bx,bz)) in enumerate(zip(ps,ps[1:]+ps[:1])):
   count=max(1,int(math.hypot(bx-ax,bz-az)/8))
   for j in range(count):
    if (j+edge)%5 in [1,2]:continue
    t=(j+.35+((j*7)%4)*.1)/count;x=ax+(bx-ax)*t;z=az+(bz-az)*t
    if not safe_decor(x,z,2):continue
    layout['decorations'].append({'asset':'shore_rock','x':x,'z':z,'y':surface(layout,x,z)-1.2-(j%3)*.3,'variant':(j+edge)%3,'yaw':j*1.7,'scale':2.4+((j*3+edge)%5)*.7})
 for road in layout['roads']:
  if road['bridge']:continue
  for a,b in zip(road['points'],road['points'][1:]):
   dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
   if length<1:continue
   for j in range(max(1,int(length/14))):
    t=(j+.5)/max(1,int(length/14));side=(-1 if j%2 else 1);x=a[0]+dx*t-dz/length*(road['width']/2+7)*side;z=a[1]+dz*t+dx/length*(road['width']/2+7)*side
    if not safe_decor(x,z,3):continue
    kind={'R1':'grove','R2':'scrub','R3':'coast_grove','R4':'yard'}[rid]
    layout['decorations'].append({'asset':kind,'x':x,'z':z,'y':surface(layout,x,z),'variant':j%3,'yaw':math.atan2(dx,dz)})
 # Ground utility routes explain how the industrial groups work together.
 layout['utility_routes']=[]
 if rid=='R2':
  for facility in layout['structures']:
   if facility['asset'] not in ['solar','battery']:continue
   choices=[s for s in layout['structures'] if s['asset']==('battery' if facility['asset']=='solar' else 'substation') and s['base_y']==facility['base_y']]
   if not choices:continue
   dest=min(choices,key=lambda s:math.hypot(s['x']-facility['x'],s['z']-facility['z']))
   if math.hypot(dest['x']-facility['x'],dest['z']-facility['z'])>110:continue
   layout['utility_routes'].append({'kind':'cable','points':[[facility['x'],facility['z'],facility['base_y']],[facility['x'],dest['z'],facility['base_y']],[dest['x'],dest['z'],dest['base_y']]]})
 if rid=='R4':
  for path in [[[220,180,0],[350,180,0]],[[170,250,0],[170,490,0]],[[430,250,0],[430,490,0]]]:layout['utility_routes'].append({'kind':'rail','points':path})
 layout['task_anchors']={p['id']:{'position':[p['position_xz_m'][0],surface(layout,*p['position_xz_m']),p['position_xz_m'][1]],'support_id':max((land for land in layout['land'] if inside(*p['position_xz_m'],land['points'])),key=lambda land:land['height'],default={'id':'water'})['id'],'heading_deg':0} for p in region['pois']}
 layout['living_anchor']={'R1':[125,0,112],'R2':[320,8,118],'R3':[100,0,130],'R4':[450,0,265]}[rid]
 layout['event_center']=[layout['living_anchor'][0],layout['living_anchor'][1]+3,layout['living_anchor'][2]+8]
 layout['entries']=[{'id':rid+'_entry_'+str(i),'position':[p[0],surface(layout,*p)+11,p[1]],'target':[points[rid][(i+1)%24][0],surface(layout,*points[rid][(i+1)%24])+11,points[rid][(i+1)%24][1]]} for i,p in enumerate(points[rid][::3])]
 layout['restoration_pois']={'R1':['R1-P05','R1-P06','R1-P07'],'R2':['R2-P06'],'R3':['R3-P11','R3-P02'],'R4':['R4-P02']}[rid]
 if rid=='R3':
  layout,updated_region=apply_r3_maritime_layout(layout,region)
  region.clear();region.update(updated_region)
  # Wayfinding buoys flank the actual boat route; they never sit on its swept hull.
  for route in layout.get('water_routes',{}).values():
   carry=0.0
   for a,b in zip(route['points_xz_m'],route['points_xz_m'][1:]):
    dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
    if length<.1:continue
    along=18-carry
    while along<length:
     if along>=0:
      for side in [1,-1]:
       x=a[0]+dx*along/length-dz/length*6.2*side;z=a[1]+dz*along/length+dx/length*6.2*side
       if surface(layout,x,z)<-.6 and not any(d['asset']=='water_buoy' and math.hypot(d['x']-x,d['z']-z)<10 for d in layout['decorations']):
        layout['decorations'].append({'asset':'water_buoy','x':x,'z':z,'y':-.6,'variant':0 if side==1 else 1});break
     along+=18
    carry=(carry+length)%18
  for p in region['pois']:
   x,z=p['position_xz_m'];support=max((land for land in layout['land'] if inside(x,z,land['points'])),key=lambda land:land['height'],default={'id':'water'})
   layout['task_anchors'][p['id']]={'position':[x,surface(layout,x,z),z],'support_id':support['id'],'heading_deg':0}
 (OUT/(rid+'.json')).write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
 manifest[rid]={'structures':len(layout['structures']),'terrain_polygons':len(layout['land']),'roads':len(layout['roads'])}
SOURCE.write_text(json.dumps(original,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(manifest))
