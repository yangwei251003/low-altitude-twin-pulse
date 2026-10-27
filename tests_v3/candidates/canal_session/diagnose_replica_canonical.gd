extends SceneTree
## Read-only scalar/resource probe; no World, profile, physics tick or transport.
const Replica = preload("res://scripts/v3/gameplay/twin_canal_replica.gd")

func _initialize() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(.4,.4,.4)
	var pose := Replica._pose(Transform3D(Basis(Vector3.UP,0.0),Vector3(14,5,-25)))
	pose[2] = -0.0 # Explicit value commonly produced by rotated real bases.
	var color := Color("689baf")
	var body := {"path":"/root/ObservedAssembly/Body","pose":pose,"layer":8,"mask":47,"target_id":"","color":[color.r,color.g,color.b],"shapes":[{
		"path":"/root/ObservedAssembly/Body/Shape","pose":pose.duplicate(),"disabled":false,"kind":"box","data":Replica._xyz(box.size),"margin":float(box.margin)}]}
	var event := {"bodies":[body],"targets":[]}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(event,"",true,true))
	var left := canonical(event)
	var right := canonical(decoded)
	var differences: Array = []
	compare(event,decoded,"root",differences)
	print("CANAL_CANONICAL_DIAGNOSTIC "+JSON.stringify({"same_digest":Replica._geometry_digest(event.bodies,event.targets)==Replica._geometry_digest(decoded.bodies,decoded.targets),
		"original_canonical":left,"decoded_canonical":right,"numeric_differences":differences},"",true,true))
	quit()

func canonical(event: Dictionary) -> String:
	var fixed: Array = []
	for body in event.bodies:
		fixed.append({"path":body.path,"layer":body.layer,"mask":body.mask,"target_id":body.target_id,"color":body.color,"shapes":body.shapes})
	return JSON.stringify(Replica._json_numbers([fixed,[]]),"",true,true)

func compare(a,b,path: String,out: Array) -> void:
	if (a is int or a is float) and (b is int or b is float):
		var left := JSON.stringify(float(a),"",true,true)
		var right := JSON.stringify(float(b),"",true,true)
		if left != right: out.append({"path":path,"before":left,"after":right,"exact_numeric_equal":float(a)==float(b),"both_zero":float(a)==0.0 and float(b)==0.0})
	elif a is Dictionary and b is Dictionary:
		for key in a: compare(a[key],b[key],path+"."+str(key),out)
	elif a is Array and b is Array:
		for index in range(a.size()): compare(a[index],b[index],path+"["+str(index)+"]",out)
