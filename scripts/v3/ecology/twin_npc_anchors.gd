extends RefCounted
## Bind persisted route progress to the scene's flight corridor. The F3 service
## node names the receiver; drones dock above its solid housing, not inside it.
## Keep the validated graph/digest, job clocks and saved actor positions intact.
const F3_SERVICE_LIFT := Vector3(0,1.6,0)

static func local_position(actor: Dictionary) -> Vector3:
	var raw: Array = actor.position
	var at := Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
	if actor.get("region") != "F3": return at
	var from_service := str(actor.get("node","")) == "service"
	var next: String = str(actor.get("next_node",""))
	var weight := 1.0 if from_service else 0.0
	if not next.is_empty():
		var progress := clampf(float(actor.get("progress",0.0)),0.0,1.0)
		weight = lerpf(weight,1.0 if next == "service" else 0.0,progress)
	return at + F3_SERVICE_LIFT * weight

static func node_position(region: String, node_id: String, position: Array) -> Vector3:
	return local_position({"region":region,"node":node_id,"position":position})
