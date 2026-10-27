extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var label = "sample"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sample="): label = argument.trim_prefix("--sample=").validate_filename()
	var world = RegionWorldV2.new()
	world.configure(CatalogV2.content().regions[0],false,{})
	var samples: Array[float] = []
	var checksum = Vector3.ZERO
	for repetition in range(5):
		var started = Time.get_ticks_usec()
		for i in range(1000): checksum += world.wind_acceleration(Vector3(120,4,130),float(i)*0.017)
		samples.append((Time.get_ticks_usec()-started)/1000.0)
	var report = {"sample":label,"calls_per_repeat":1000,"repeat_ms":samples,"checksum":str(checksum),"source_sha256":FileAccess.get_sha256("res://scripts/v2/region_world.gd"),"scope":"Headless microbenchmark, not GPU FPS or physical wind validation"}
	DirAccess.make_dir_recursive_absolute("res://artifacts/v2")
	var file = FileAccess.open("res://artifacts/v2/wind_cost_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	world.free()
	print("WIND_COST ",JSON.stringify(report))
	quit()
