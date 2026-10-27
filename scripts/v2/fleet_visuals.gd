class_name FleetVisualsV2
extends RefCounted

static var cache: Dictionary = {}

static func make_drone(id: String, slots: Dictionary = {}) -> Node3D:
	var root = Node3D.new()
	root.name = "Airframe_" + id
	var path = "res://assets/v2/models/" + id + ".glb"
	if ResourceLoader.exists(path):
		if not cache.has(path): cache[path] = load(path)
		root.add_child(cache[path].instantiate())
	else:
		var heavy = id == "hx02"
		var width = 1.2 if heavy else 0.85
		GameVisuals.box(root, Vector3.ZERO, Vector3(0.45, 0.24, 0.62), Color("f4f0e5"))
		var count = 6 if heavy else 4
		for i in range(count):
			var angle = TAU * i / count + PI / 4.0
			var p = Vector3(cos(angle), 0.0, sin(angle)) * width * 0.65
			var arm = GameVisuals.box(root, p * 0.5, Vector3(0.10, 0.08, p.length()), Color("142a3b"))
			arm.rotation.y = -angle + PI / 2.0
			var rotor = Node3D.new()
			rotor.name = "Rotor%d" % i
			root.add_child(rotor)
			rotor.position = p + Vector3.UP * 0.10
			GameVisuals.box(rotor, Vector3.ZERO, Vector3(0.42, 0.025, 0.06), Color("405c63"))
	for slot in slots:
		var module_id = str(slots[slot])
		if module_id in ["stock", "stock_drive", "stock_battery", "none", ""]: continue
		var module_path = "res://assets/v2/models/" + module_id + ".glb"
		if slot=="weapon" and module_id in ["pulse_base","burst_capacitor"]:
			module_path="res://assets/models/v22_combat/weapon_"+("lance" if module_id=="burst_capacitor" else "pulse")+".glb"
		var mount = Vector3(0, -0.30, -0.34) if slot == "weapon" else (Vector3(0, -0.36, 0.14) if slot == "tool" else Vector3(0, 0.24, 0.14))
		if ResourceLoader.exists(module_path):
			if not cache.has(module_path): cache[module_path] = load(module_path)
			var attachment: Node3D = cache[module_path].instantiate()
			attachment.name = "Attachment_" + slot
			root.add_child(attachment)
			attachment.position = mount
		else:
			GameVisuals.box(root, mount, Vector3(0.21, 0.14, 0.24), Color("42c7b2") if slot == "tool" else Color("142a3b"))
	# Explicit GLB palette opt-in, shared with imported city props. The importer
	# retains COLOR_0 but does not enable it on the generated StandardMaterial.
	StreetDressingV2._enable_vertex_colors(root)
	return root
