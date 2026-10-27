extends RefCounted
## Temporary physical approaches. Their meshes are also their collisions.
## The independently moving bridge and gate remain owned by TwinTestWorld.
const PATH := "res://data/v3/terrain/f1_growth_crossing.json"
var _parts: Dictionary = {}

func load_layout() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or parsed.get("id") != "f1_growth_crossing_v1":
		return {"ok":false,"code":"crossing_schema"}
	if not parsed.get("approaches") is Array or parsed.approaches.size() != 2:
		return {"ok":false,"code":"approach_count"}
	var built: Dictionary = {}
	for approach in parsed.approaches:
		if not approach is Dictionary or approach.get("id") not in ["west","east"] or built.has(approach.id):
			return {"ok":false,"code":"approach_id"}
		if not approach.get("sections") is Array or approach.sections.size()<2 or approach.sections.size()>16 or not _finite(approach.get("bottom_y")):
			return {"ok":false,"code":"sections"}
		var last_x := -INF
		var count := 0
		for section in approach.sections:
			if not section is Dictionary or not _finite(section.get("x")) or float(section.x)<=last_x or absf(section.x)>52 or not section.get("top_zy") is Array:
				return {"ok":false,"code":"section_x"}
			last_x = float(section.x)
			if count==0: count=section.top_zy.size()
			if count<2 or count>16 or section.top_zy.size()!=count: return {"ok":false,"code":"section_vertices"}
			var last_z := -INF
			for point in section.top_zy:
				if not point is Array or point.size()!=2 or not _finite(point[0]) or not _finite(point[1]): return {"ok":false,"code":"section_point"}
				if float(point[0])<=last_z or absf(point[0])>50 or float(point[1])<=float(approach.bottom_y) or float(point[1])>5.25:
					return {"ok":false,"code":"section_bounds"}
				last_z=float(point[0])
		built[approach.id] = _build(approach)
	_parts=built
	return {"ok":true,"code":"graybox_ready"}

func part_ids() -> Array:
	return _parts.keys()

func make_mesh(id: String) -> ArrayMesh:
	if not _parts.has(id): return null
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_parts[id].faces
	arrays[Mesh.ARRAY_NORMAL]=_parts[id].normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func make_shape(id: String) -> ConcavePolygonShape3D:
	if not _parts.has(id): return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_parts[id].faces)
	shape.backface_collision=true
	return shape

static func _finite(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _build(approach: Dictionary) -> Dictionary:
	var result := {"faces":PackedVector3Array(),"normals":PackedVector3Array()}
	var rows: Array=[]
	for section in approach.sections:
		var row: Array[Vector3]=[]
		for p in section.top_zy: row.append(Vector3(section.x,p[1],p[0]))
		rows.append(row)
	var floor_y: float=approach.bottom_y
	for i in range(1,rows.size()):
		var a: Array=rows[i-1]
		var b: Array=rows[i]
		for j in range(1,a.size()):
			_quad(result,a[j-1],b[j-1],b[j],a[j],Vector3.UP)
			_quad(result,_floor(a[j-1],floor_y),_floor(b[j-1],floor_y),_floor(b[j],floor_y),_floor(a[j],floor_y),Vector3.DOWN)
		_quad(result,a[0],b[0],_floor(b[0],floor_y),_floor(a[0],floor_y),Vector3.FORWARD)
		_quad(result,a.back(),b.back(),_floor(b.back(),floor_y),_floor(a.back(),floor_y),Vector3.BACK)
	for end in [0,rows.size()-1]:
		var row: Array=rows[end]
		for j in range(1,row.size()):
			_quad(result,row[j-1],row[j],_floor(row[j],floor_y),_floor(row[j-1],floor_y),Vector3.LEFT if end==0 else Vector3.RIGHT)
	return result

static func _floor(p: Vector3,y: float) -> Vector3:
	return Vector3(p.x,y,p.z)

static func _quad(result: Dictionary,a: Vector3,b: Vector3,c: Vector3,d: Vector3,toward: Vector3) -> void:
	_tri(result,a,b,c,toward)
	_tri(result,a,c,d,toward)

static func _tri(result: Dictionary,a: Vector3,b: Vector3,c: Vector3,toward: Vector3) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared()<1e-14: return
	if cross.dot(toward)>0:
		var swap:=b
		b=c
		c=swap
		cross=-cross
	for point in [a,b,c]:
		result.faces.append(point)
		result.normals.append(-cross.normalized())
