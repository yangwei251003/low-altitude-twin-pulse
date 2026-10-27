extends SceneTree
## Pure synthetic triangle fixtures. Actual production area requires the exporter.
const G = preload("res://scripts_tools/v3/candidates/yard_connector_layout/yard_connector_geometry.gd")
const S = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
    var source: Dictionary = S._empty_geometry()
    var polygon: Array[Dictionary] = []
    for p: Vector3 in [Vector3(-25,0,10),Vector3(13,0,10),Vector3(13,0,29),Vector3(-25,0,29)]:
        polygon.append({"p":p,"n":Vector3.UP,"uv":Vector2(p.x,p.z)})
    S._emit(source,polygon,0)
    var original: PackedByteArray = source.faces.to_byte_array()
    var exclusion: Array[Dictionary] = [{"id":"synthetic_foot","rect":Rect2(0,12,1,1)}]
    var result: Dictionary = G.clip(source,exclusion)
    _check(result.ok,"bounded clipping succeeds")
    if result.ok:
        _check(absf(result.report.visible_replacement_m2-(36.6*17.5-1))<.0005,"rectangle minus real synthetic footprint")
        _check(G.overlap_rect(result.visible,exclusion[0].rect)<.0005,"footprint retained rather than covered")
        _check(absf(result.report.source_area_m2-result.report.visible_replacement_m2-result.report.retained_m2)<.0005,"whole source partitions exactly")
        _check(S._validate(result.visible).ok,"normal winding preserved")
        _check(result.visible.source_triangles.size()==result.visible.faces.size()/3,"original triangle provenance retained")
    _check(original==source.faces.to_byte_array(),"source bytes untouched")
    print("I2_YARD_SYNTHETIC_TEST "+JSON.stringify({"checks":checks,"failures":failures,"scope":"synthetic only; not measured production area"}))
    quit(0 if failures.is_empty() else 1)

func _check(ok: bool,label: String) -> void:
    checks+=1
    if not ok: failures.append(label)
