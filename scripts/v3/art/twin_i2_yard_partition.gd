extends RefCounted
## Canonical production yard partition. Promoted from the verified raw-array
## layout export; no vertex snapping, hull filling or collision mutation.
const Reader = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const RectCut = preload("res://scripts/v3/art/twin_i2_east_maintenance_art.gd")
const Closure = preload("res://scripts/v3/art/twin_i2_revetment_closure_art.gd")
const Pit = preload("res://scripts/v3/world/twin_i2_inspection_pit.gd")
const REGION := Rect2(-24,10.5,36.6,17.5)
const ORIGIN := Vector3(-5.7,0,19.25)
const AREA_EPS := .0005 # Existing float32 area accounting; no cut-plane expansion.
const PUMP_SOLIDS := ["PumpFloor","PumpWestWall","PumpEastWall","PumpNorthWall","PumpSouthWestJamb","PumpSouthEastJamb"]

static func collect(world: Node3D) -> Dictionary:
    if not world.is_inside_tree() or not world.build_errors.is_empty(): return _fail("complete_live_world_required")
    for key: String in ["waterfront_install","revetment_art","east_revetment_art","east_maintenance_art","revetment_closure_art","inspection_pit","inspection_pit_art"]:
        if not world.get(key).get("ok",false): return _fail("missing_production_stage:"+key)
    var dry: MeshInstance3D = world.waterfront_install.meshes.dry_surface
    if not dry.visible or not dry.global_transform.is_equal_approx(Transform3D.IDENTITY): return _fail("final_dry_world_identity")
    var read: Dictionary = Reader._read_mesh(dry.mesh)
    if not read.ok: return read
    var source: Dictionary = read.geometry
    for p: Vector3 in source.faces:
        if p.y!=0: return _fail("top_not_exact_zero")
    var source_sha: String = Reader._attributes_sha(source)
    if source_sha!=Reader._attributes_sha(world.inspection_pit.remaining_visual): return _fail("not_final_post_pit_raw_arrays")
    var ground: StaticBody3D = world.waterfront_install.ground
    var collision: ConcavePolygonShape3D = world.waterfront_install.shape_node.shape
    var rid: RID = ground.get_rid()
    var collision_bytes: PackedByteArray = collision.get_faces().to_byte_array()
    var exclusions: Array[Dictionary] = []
    for id: String in PUMP_SOLIDS:
        var row: Dictionary = body_footprint(world.clinic.fixed_bodies[id],id)
        if not row.ok: return row
        exclusions.append(row)
    var foot: Dictionary = body_footprint(world.shared_access.fixed_bodies.WestFoot2,"WestFoot2")
    if not foot.ok: return foot
    exclusions.append(foot)
    var clipped: Dictionary = clip(source,exclusions)
    if not clipped.ok: return clipped
    var guards: Array = []
    # These surfaces were already removed by the real production installers.
    # Test absence rather than filling/re-cutting a hand-rebuilt shoreline.
    for region: Rect2 in world.clinic.ground_art.surface_regions:
        var area: float = overlap_rect(source,region)
        if area>AREA_EPS: return _fail("authored_paving_still_in_source")
        guards.append({"kind":"authored_paving","rect":[region.position.x,region.position.y,region.size.x,region.size.y],"source_overlap_m2":area})
    var pit_area: float = overlap_rect(source,Pit.REGION)
    if pit_area>AREA_EPS: return _fail("pit_still_in_source")
    guards.append({"kind":"inspection_pit","rect":[Pit.REGION.position.x,Pit.REGION.position.y,Pit.REGION.size.x,Pit.REGION.size.y],"source_overlap_m2":pit_area})
    var closure_plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Closure.PLAN))
    for segment: Dictionary in closure_plan.segments:
        var area := 0.0
        for first in range(0,source.faces.size(),3): area+=Split._polygon_area(Closure._footprint(_polygon(source,first),segment.footprint).inside)
        if area>AREA_EPS: return _fail("closure_top_still_in_source")
        guards.append({"kind":"authored_closure_top","id":segment.get("id",segment.get("name","")),"footprint":segment.footprint,"source_overlap_m2":area})
    var west_strip := Rect2(12.25,2.3,.35,13.3)
    if overlap_rect(source,west_strip)>AREA_EPS: return _fail("original_west_top_still_in_source")
    guards.append({"kind":"original_west_top","rect":[12.25,2.3,.35,13.3],"source_overlap_m2":overlap_rect(source,west_strip)})
    var read_after: Dictionary = Reader._read_mesh(dry.mesh)
    if not read_after.ok or Reader._attributes_sha(read_after.geometry)!=source_sha or ground.get_rid()!=rid or world.waterfront_install.shape_node.shape!=collision or collision.get_faces().to_byte_array()!=collision_bytes:
        return _fail("read_only_contract_changed")
    clipped.source = source
    clipped.report.merge({"source_node":str(dry.get_path()),"source_attributes_sha256":source_sha,
        "raw_vertex_sha256":Split._sha(source.faces.to_byte_array()),"raw_array_format":dry.mesh.surface_get_format(0),
        "final_post_pit_exact_match":true,"guarded_existing_surfaces":guards,"exclusions":exclusions,
        "ground_rid":rid.get_id(),"ground_instance":ground.get_instance_id(),"ground_collision_sha256":Split._sha(collision_bytes),
        "ground_collision_unchanged":true,"actual_world_identity":true,"court_and_approach_area_m2":288.0},true)
    return clipped

static func body_footprint(body: StaticBody3D,id: String) -> Dictionary:
    if not is_instance_valid(body) or not body.is_inside_tree(): return _fail("body_missing:"+id)
    var shapes: Array = body.find_children("*","CollisionShape3D",false,false)
    if shapes.size()!=1: return _fail("single_actual_shape_required:"+id)
    var node: CollisionShape3D = shapes[0]
    if node.disabled or not node.shape is BoxShape3D or not node.global_transform.basis.is_equal_approx(Basis.IDENTITY): return _fail("actual_unrotated_box_required:"+id)
    var bounds := AABB(node.global_position-node.shape.size*.5,node.shape.size)
    return {"ok":true,"id":id,"rect":Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),
        "world_min":bounds.position,"world_max":bounds.end,"node":str(body.get_path()),"rid":body.get_rid().get_id(),"role":"retain_existing_structural_footprint_no_roof_shadow"}

static func clip(source: Dictionary,exclusions: Array[Dictionary]) -> Dictionary:
    if not Split._validate(source).ok: return _fail("source_invalid")
    var visible: Dictionary = Split._empty_geometry()
    var remainder: Dictionary = Split._empty_geometry()
    var protected: Dictionary = Split._empty_geometry()
    var intersect_area := 0.0
    for first in range(0,source.faces.size(),3):
        var outer: Dictionary = RectCut._partition(_polygon(source,first),REGION)
        for piece: Array[Dictionary] in outer.outside: Split._emit(remainder,piece,first/3)
        intersect_area+=Split._polygon_area(outer.inside)
        var pending: Array = [outer.inside] if Split._polygon_area(outer.inside)>1e-12 else []
        for exclusion: Dictionary in exclusions:
            if not exclusion.get("rect") is Rect2: return _fail("exclusion_rect")
            var next: Array = []
            for piece: Array[Dictionary] in pending:
                var row: Dictionary = RectCut._partition(piece,exclusion.rect)
                Split._emit(remainder,row.inside,first/3)
                Split._emit(protected,row.inside,first/3)
                next.append_array(row.outside)
            pending=next
        for piece: Array[Dictionary] in pending: Split._emit(visible,piece,first/3)
    for output: Dictionary in [visible,remainder,protected]:
        if not output.faces.is_empty() and not Split._validate(output).ok: return _fail("clipped_attributes")
        if source.has("tangents"):
            # collect() uses Reader._read_mesh, which rejects differing tangent
            # corners within any source triangle. This is that exact planar
            # frame transfer, not general tangent interpolation for curved art.
            var tangents := PackedFloat32Array()
            for triangle: int in output.source_triangles:
                for corner in 3:
                    for component in 4: tangents.append(source.tangents[triangle*12+component])
            output.tangents=tangents
    var area: float = Split._area(source)
    var v_area: float = Split._area(visible)
    var r_area: float = Split._area(remainder)
    var p_area: float = Split._area(protected)
    if absf(area-v_area-r_area)>AREA_EPS or absf(intersect_area-v_area-p_area)>AREA_EPS: return _fail("area_conservation")
    return {"ok":true,"visible":visible,"remainder":remainder,"under_structures":protected,
        "report":{"source_area_m2":area,"rectangle_intersection_m2":intersect_area,"visible_replacement_m2":v_area,"retained_m2":r_area,"retained_under_structures_m2":p_area,
        "source_triangles":source.faces.size()/3,"visible_triangles":visible.faces.size()/3,"area_accounting_tolerance_m2":AREA_EPS,
        "scope":"actual_final_dry_surface_visual_input_only; not collision replacement or art acceptance"}}

static func overlap_rect(source: Dictionary,rect: Rect2) -> float:
    var area := 0.0
    for first in range(0,source.faces.size(),3): area+=Split._polygon_area(RectCut._partition(_polygon(source,first),rect).inside)
    return area

static func _polygon(source: Dictionary,first: int) -> Array[Dictionary]:
    var polygon: Array[Dictionary] = []
    for offset in 3:
        var index: int = first+offset
        polygon.append({"p":source.faces[index],"n":source.normals[index],"uv":source.uv[index]})
    return polygon

static func _fail(code: String) -> Dictionary:
    return {"ok":false,"code":code}
