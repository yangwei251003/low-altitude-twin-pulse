extends "res://scripts_tools/v3/capture_clinic_pump_integrated.gd"
## One unchanged production pose/camera, five isolated material conditions.
## All temporary render changes are restored; this does not fix source assets.

func _initialize() -> void:
	additional_inputs=["res://scripts_tools/v3/diagnose_clinic_pump_material.gd"]
	diagnostic_only=true
	super._initialize()

func _capture(id: String,_note: String,_zoom_steps: int=0) -> void:
	if id!="01-I2-pump-entrance-default":
		# The base fixture still checks the real interior cutaway later. Keep
		# its production presentation settling even though only exterior
		# diagnostic screenshots belong to this five-condition report.
		_hold()
		_view()
		for unused in range(18):
			session._process(1.0/30.0)
			await RenderingServer.frame_post_draw
		return
	var roof: MeshInstance3D
	for mesh: MeshInstance3D in session.clinic.module.pump_art.model_meshes:
		if mesh.name=="RoofCover": roof=mesh
	var original := roof.get_active_material(0) as StandardMaterial3D
	var env_node: WorldEnvironment = session.world.find_children("*","WorldEnvironment",true,false)[0]
	var settings: Environment = env_node.environment
	var original_sky := settings.sky
	var original_reflection := settings.reflected_light_source
	physical_probes.diagnosis={"material_class":original.get_class(),"metallic":original.metallic,
		"roughness":original.roughness,"metallic_channel":original.metallic_texture_channel,
		"roughness_channel":original.roughness_texture_channel,"normal_enabled":original.normal_enabled,
		"normal_scale":original.normal_scale,"albedo_color":str(original.albedo_color),
		"sky_present":original_sky!=null,"background_mode":settings.background_mode,
		"reflection_source":original_reflection,"ambient_source":settings.ambient_light_source,
		"ambient_energy":settings.ambient_light_energy,"conditions":[]}
	for variant in ["original","normal_disabled","metallic_zero","neutral_sky_reflection","unshaded_albedo"]:
		var material: StandardMaterial3D = original.duplicate()
		settings.sky=original_sky
		settings.reflected_light_source=original_reflection
		match variant:
			"normal_disabled": material.normal_enabled=false
			"metallic_zero": material.metallic=0.0
			"neutral_sky_reflection":
				var sky_material := ProceduralSkyMaterial.new()
				for property in ["sky_top_color","sky_horizon_color","ground_bottom_color","ground_horizon_color"]:
					sky_material.set(property,Color(.6,.6,.6))
				sky_material.sun_angle_max=0.0
				var sky := Sky.new()
				sky.radiance_size=Sky.RADIANCE_SIZE_128
				sky.process_mode=Sky.PROCESS_MODE_QUALITY
				sky.sky_material=sky_material
				settings.sky=sky
				settings.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
			"unshaded_albedo": material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		roof.set_surface_override_material(0,material)
		var record := {"variant":variant,"metallic":material.metallic,"normal":material.normal_enabled,
			"shading":material.shading_mode,"sky_present":settings.sky!=null,"reflection_source":settings.reflected_light_source}
		physical_probes.diagnosis.conditions.append(record)
		await super._capture("diagnostic-"+variant,"TEMPORARY render-only diagnosis: "+variant+". Same production exterior pose and two ordinary zoom steps.",2)
		if finishing: return
	roof.set_surface_override_material(0,null)
	settings.sky=original_sky
	settings.reflected_light_source=original_reflection
	_check(roof.get_active_material(0)==original and settings.sky==original_sky and settings.reflected_light_source==original_reflection,"diagnostic restores original material and environment")
