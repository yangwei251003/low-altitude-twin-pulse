extends RefCounted
## Visual child of the existing hydraulic Deck; movement remains in Waterworks.
const Validate=preload("res://scripts/v3/art/twin_west_service_room_art.gd")
const MODEL_PATH:="res://assets/v3/environment/clinic_lift_deck/clinic_lift_deck.glb"
const EXTENT:=AABB(Vector3(-2,-.175,-2),Vector3(4,.35,4))
const PARTS:={"DeckSteel":656,"DeckPaint":572}

static func install(works: Node3D) -> Dictionary:
	if works.is_inside_tree() or works.has_meta("authored_clinic_lift_deck"):
		return {"ok":false,"code":"lift_deck_install_before_tree_once"}
	var body := works.moving_bodies.get("Deck") as StaticBody3D
	if body==null or body!=works.deck: return {"ok":false,"code":"lift_deck_original_body_required"}
	var shape := body.get_node_or_null("ExactBoxCollision") as CollisionShape3D
	var old := body.get_node_or_null("Visual") as MeshInstance3D
	if shape==null or not shape.shape is BoxShape3D or not shape.transform.is_equal_approx(Transform3D.IDENTITY) or not shape.shape.size.is_equal_approx(EXTENT.size) or old==null:
		return {"ok":false,"code":"lift_deck_original_shape_required"}
	var top: float=works.status().deck_top_y
	if not body.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,top-.175,-4))):
		return {"ok":false,"code":"lift_deck_authoritative_pose_required"}
	var packed:=load(MODEL_PATH) as PackedScene
	if packed==null: return {"ok":false,"code":"lift_deck_glb_required"}
	var model:=packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"lift_deck_visual_root_required"}
	var checked: Dictionary=Validate._validate(model,EXTENT,PARTS,2)
	if not checked.ok:
		model.free()
		return {"ok":false,"code":"lift_deck:"+str(checked.code)}
	model.name="ClinicLiftDeckArt"
	body.add_child(model) # Authored centre origin: no second movement/offset.
	for mesh: MeshInstance3D in checked.meshes: mesh.set_meta("terrain_visibility_single_sided",true)
	old.hide()
	works.set_meta("authored_clinic_lift_deck",true)
	return {"ok":true,"code":"lift_deck_installed","path":MODEL_PATH,"model":model,
		"body":body,"shape":shape,"model_meshes":checked.meshes,"triangles":checked.triangles,
		"materials":checked.materials,"bounds":checked.bounds,"occluders":[body],
		"collision_policy":"all nine moving bodies and original hydraulic sweep unchanged"}
