"""Deterministic metre-scale high-only tread layout. Pure Python, no Blender."""
import math

PITCH=.080
LENGTH=.042
WIDTH=.010
RECESS=.0025
PLATES={
    'TopServiceStrip':(-1.021,-.680,-1.021,1.021),
    'LandingPlate_0':(-.676,1.021,-1.021,-.344),
    'LandingPlate_1':(-.676,1.021,-.340,.338),
    'LandingPlate_2':(-.676,1.021,.342,1.021),
}
FASTENERS=[(-.94,-.91),(-.75,.91),(-.61,-.91),(.94,-.91),(-.61,.25),(.94,.25),(-.61,.91),(.94,.91)]

def ring(length,width,chamfer):
    a,b=length/2,width/2;c=chamfer
    return [(-a+c,-b),(a-c,-b),(a,-b+c),(a,b-c),(a-c,b),(-a+c,b),(-a,b-c),(-a,-b+c)]

def footprint(cx,cz,angle):
    ca,sa=math.cos(angle),math.sin(angle)
    return [(cx+x*ca-z*sa,cz+x*sa+z*ca) for x,z in ring(LENGTH,WIDTH,.002)]

def layout():
    rows=[]
    for name,(x0,x1,z0,z1) in PLATES.items():
        for ix in range(-14,14):
            for iz in range(-14,14):
                # Two opposed bars per cell. The phase is global, not restarted
                # per plate; actual 4 mm construction seams remain clear.
                for arm in (-1,1):
                    cx=(ix+.5)*PITCH+arm*.018
                    cz=(iz+.5)*PITCH+arm*.010
                    angle=arm*math.pi/4
                    outline=footprint(cx,cz,angle)
                    if not all(x0+.006<=x<=x1-.006 and z0+.006<=z<=z1-.006 for x,z in outline):continue
                    # Conservative clearance to the actual flush pockets.
                    if any(math.hypot(cx-x,cz-z)<.057 for x,z in FASTENERS):continue
                    rows.append({'plate':name,'centre':[cx,cz],'angle':angle,'outline':outline})
    return rows

def report():
    rows=layout();area=sum((x1-x0)*(z1-z0) for x0,x1,z0,z1 in PLATES.values())
    bar_area=LENGTH*WIDTH-2*.002**2
    return {'rib_count':len(rows),'rib_count_by_plate':{name:sum(r['plate']==name for r in rows) for name in PLATES},
            'pitch_m':PITCH,'bar_size_m':[LENGTH,WIDTH,RECESS],'nominal_plate_area_m2':area,
            'bar_projected_area_m2':bar_area*len(rows),'nominal_coverage':bar_area*len(rows)/area,
            'high_rib_triangles':len(rows)*44,'original_low_triangles':4740,
            'high_total_triangles_expected':4740+len(rows)*44,
            'note':'Static count; source topology and actual bounds are checked during Blender execution. Coverage is geometry footprint, not a visual approval.'}

if __name__=='__main__':
    import json
    print(json.dumps(report(),indent=2))
