"""Angles from decoded vector components in Python double, no near-one acos."""
import math
import numpy as np


def normal_metrics(actual, expected):
    a=np.asarray(actual,np.float64);b=np.asarray(expected,np.float64)
    assert a.shape==b.shape and a.shape[-1]==3
    angles=[];unit_errors=[];raw_errors=[]
    for av,bv in zip(a.reshape((-1,3)),b.reshape((-1,3))):
        ax,ay,az=map(float,av);bx,by,bz=map(float,bv)
        raw_errors.append(math.hypot(ax-bx,ay-by,az-bz))
        al=math.hypot(ax,ay,az);bl=math.hypot(bx,by,bz)
        assert math.isfinite(al) and math.isfinite(bl) and al>0 and bl>0
        ax/=al;ay/=al;az/=al;bx/=bl;by/=bl;bz/=bl
        cross=math.hypot(ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx)
        dot=math.fsum((ax*bx,ay*by,az*bz))
        angles.append(math.degrees(math.atan2(cross,dot)))
        unit_errors.append(math.hypot(ax-bx,ay-by,az-bz))
    return (np.asarray(angles,np.float64).reshape(a.shape[:-1]),
            {'max_raw_vector_error':max(raw_errors,default=0.),
             'max_unit_vector_error':max(unit_errors,default=0.),
             'max_angle_deg':max(angles,default=0.),
             'calculation':'Python double components: atan2(norm(cross(unitA,unitB)), fsum(dot))',
             'visual_shading_tolerance_deg':0.1,'bitwise_normal_equality_claim':False})
