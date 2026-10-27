extends RefCounted
## Independently authored taller companion; the original solid stays authoritative.
const RoomArt = preload("res://scripts/v3/art/twin_west_service_room_art.gd")
const MODEL_PATH := "res://assets/v3/environment/west_offset_room/west_offset_room.glb"
const ORIGIN := Vector3(-12.5,0,-2.5)
const EXTENT := AABB(Vector3(-1.5,0,-2.5),Vector3(3,4.1,5))
const PARTS := {"PaintedShell":3256,"ConcreteBase":220,"RoofMetal":2220}

static func install(works: Node3D) -> Dictionary:
	return RoomArt.install_variant(works,"WestOffsetRoof",MODEL_PATH,ORIGIN,EXTENT,PARTS,"WestOffsetRoomArt")
