"""Prepared only; not imported by either diagnostic stage. No mesh/height edit."""
def apply_side_uv_only(ob):
    """Requires a later approved repair copy, never the frozen source.

    Top triangles keep their original horizontal mapping; only vertical closure
    faces use X/height on +/-Z ends and Z/height on +/-X sides. This preserves
    original 2m/2.5m texel scale rather than compressing a full map to the side.
    Corner continuity remains a separate visual check, not a promised match.
    """
    me=ob.data;changed=[]
    for p in me.polygons:
        if p.use_smooth or abs(p.normal.z)>.9:continue
        side_x=abs(p.normal.x)>=abs(p.normal.y)
        for li in p.loop_indices:
            v=me.vertices[me.loops[li].vertex_index].co;x,y,z=v.x,v.z,-v.y
            horizontal=z if side_x else x
            me.uv_layers['RockScanUV'].data[li].uv=(horizontal/2+.31,y/2+.09)
            me.uv_layers['SoilScanUV'].data[li].uv=(horizontal/2.5+.13,y/2.5+.27)
        changed.append(p.index)
    return changed
