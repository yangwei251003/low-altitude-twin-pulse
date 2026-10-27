extends SceneTree
const Migration = preload("res://scripts/v2/layout_save_migration.gd")
const Layout = preload("res://scripts/v2/region_layout.gd")
const Repository = preload("res://scripts/v2/save_repository.gd")
var checks = 0
var failures: Array = []
var content: Dictionary
var fixture_counter = 0
var fixture_root = "user://qa_v2/layout_migration_"+str(Time.get_ticks_usec())

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--migration-fixture-root="): fixture_root=argument.trim_prefix("--migration-fixture-root=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("MIGRATION_FAIL "+label)

func profile(job: Dictionary, stage: Dictionary, records: Dictionary) -> Dictionary:
	return {"schema_version":2,"profile_id":"same-pilot","wallet":{"parts":817},"ledger":{"receipts":["campaign:M01:stage:1:first"],"repeat_counters":{"M01":2}},"campaign":{"completed_stages":["M01-S1"],"completed_missions":["M01"],"active_checkpoint":{"job_id":job.id,"stage_index":job.stages.find(stage),"run_id":"same-run","seconds":71.25,"repeat":false,"night":true,"conditions":{"difficulty":2,"auto_fire_used":true},"damage_state":{"hp":45,"armor":3,"components":{"rotor":.4}},"environment_state":{"platform_locked":true,"field":{"weather":"rain","time_s":12.5}},"run_state":{"stage_id":stage.id,"action_index":0,"elapsed_s":3.5,"cargo_records":records.duplicate(true),"stage_start_cargo":records.duplicate(true),"preparation_flags":{"fixed":true},"metrics":{"damage":12}}}},"world":{"regions":{},"restored_objects":{"R1-P06":true},"discovered_pois":["R1-P01"],"outposts":[]}}

func cargo(state: String, stage_id: String) -> Dictionary:
	return {"state":state,"mass_kg":2.5,"integrity":.63,"value":30,"stage_id":stage_id,"home":[298.0,.8,298.0],"position":[299.0,2.4,298.0]}

func _run() -> void:
	content=JSON.parse_string(FileAccess.get_file_as_string("res://data/v2/world_content.json"))
	var cargo_cases=0
	for job in content.missions:
		for stage in job.stages:
			for action in stage.get("actions", [])+stage.get("optional_actions", []):
				if str(action.get("type", ""))!="pickup": continue
				for state in (["staged"] if bool(action.get("reuse_staged_instance",false)) else ["available","carried"]):
					var records={str(action.cargo_id):cargo(state,str(stage.id))}
					var before=profile(job,stage,records)
					var original=JSON.stringify(before)
					var result=Migration.plan(before,content)
					cargo_cases+=1
					check(result.ok,"safe cargo "+str(job.id)+"/"+str(action.cargo_id)+"/"+state+" "+str(result.get("error","")))
					check(JSON.stringify(before)==original,"pure plan does not mutate source")
					if not result.ok: continue
					var cp: Dictionary=result.set["campaign.active_checkpoint"]
					check(cp.stage_index==before.campaign.active_checkpoint.stage_index and cp.run_id=="same-run" and cp.seconds==71.25,"checkpoint identity and progress preserved")
					check(cp.damage_state==before.campaign.active_checkpoint.damage_state and cp.conditions==before.campaign.active_checkpoint.conditions and cp.environment_state==before.campaign.active_checkpoint.environment_state,"conditions, pilot damage and environment retained")
					for field in ["cargo_records","stage_start_cargo"]:
						var migrated: Dictionary=cp.run_state[field][str(action.cargo_id)]
						check(migrated.state==state and migrated.mass_kg==2.5 and migrated.integrity==.63 and migrated.value==30,"cargo identity/value/integrity retained")
						check(migrated.position==migrated.home and migrated.home!=records[str(action.cargo_id)].home,"both spatial fields moved")
					check(cp.run_state.action_index==0 and cp.run_state.elapsed_s==3.5 and cp.run_state.metrics.damage==12,"run action/metrics retained")
	var job: Dictionary=content.missions[6]
	var stage: Dictionary=job.stages[1]
	var before=profile(job,stage,{"old-delivered":cargo("delivered",str(stage.id))})
	var brain={"version":1,"state":"attack","home":[50,5,50],"patrol_target":[100,5,100],"last_seen_position":[90,5,90],"last_seen_velocity":[1,0,1],"confidence":1,"memory_age":0,"reported":true,"report_progress":2,"rng_state":"123456","noise_left":5}
	var unit={"unit_id":"R2-E00001-U01","encounter_id":"R2-E00001","source_kind":"ambient","entry_id":"R2-road-50-50","entry":[50,5,50],"direction":[0,0,1],"target":[50,5,92],"position":[60,5,70],"role":"scout","seed":91,"status":"active","hp":31,"damage_state":{"hp":31,"armor":2,"components":{"sensor":.5}},"brain":brain}
	var pending={"encounter_id":"R2-E00002","entry_id":"R2-road-150-50","entry":[150,5,50],"direction":[0,0,1],"target":[155,5,65],"roles":["support"],"unit_seed":92,"progress":8,"eta":.1,"ttl":4}
	before.world["combat_regions"]={"R2":{"version":1,"region_id":"R2","rng_state":"998877","sequence":2,"time_s":82,"rest_left":11,"alert":.5,"noise_position":[100,5,100],"noise_age":0,"pending":pending,"units":[unit],"reported_encounters":{"R2-E00001":true},"seen_events":["damage:1"]}}
	var result=Migration.plan(before,content)
	check(result.ok,"director migration")
	if result.ok:
		var migrated: Dictionary=result.set.world.combat_regions.R2
		var saved: Dictionary=migrated.units[0]
		check(saved.unit_id==unit.unit_id and saved.hp==31 and saved.damage_state==unit.damage_state and saved.seed==91,"enemy identity and full damage preserved")
		check(saved.brain.rng_state=="123456" and saved.brain.reported and migrated.rng_state=="998877" and migrated.reported_encounters==before.world.combat_regions.R2.reported_encounters,"RNG and report dedup preserved")
		check(saved.entry_id.begins_with("R2_entry_") and saved.entry!=unit.entry and saved.target!=unit.target and saved.status=="virtual","authored entry and target rebind")
		check(saved.brain.state=="patrol" and saved.brain.confidence==0 and saved.brain.memory_age==999 and saved.brain.noise_left==0 and saved.brain.report_progress==0,"stale perception cleared")
		check(migrated.pending.encounter_id==pending.encounter_id and migrated.pending.roles==pending.roles and migrated.pending.unit_seed==92 and migrated.pending.progress==0 and migrated.pending.eta>=3,"pending encounter identity preserved")
		check(migrated.noise_age==999 and migrated.noise_position==[0.0,0.0,0.0],"director old clue cleared")
		check(result.set["campaign.active_checkpoint"].run_state.cargo_records["old-delivered"]==before.campaign.active_checkpoint.run_state.cargo_records["old-delivered"],"delivered cargo is not revived")
		var upgraded=before.duplicate(true)
		upgraded.world=result.set.world
		upgraded.campaign.active_checkpoint=result.set["campaign.active_checkpoint"]
		check(not Migration.plan(upgraded,content).changed,"migration idempotent")
		upgraded.world.layout_revision=2
		check(not Migration.plan(upgraded,content).ok,"newer layout protected")
	var malformed=before.duplicate(true)
	malformed.campaign.active_checkpoint.run_state=[]
	check(not Migration.plan(malformed,content).ok,"invalid run state fails safely")
	malformed=before.duplicate(true)
	malformed.campaign.active_checkpoint.job_id="unknown-job"
	malformed.campaign.active_checkpoint.run_state.cargo_records={}
	check(not Migration.plan(malformed,content).ok,"unknown job with retry cargo fails safely")
	malformed=before.duplicate(true)
	malformed.campaign.active_checkpoint.run_state.cargo_records={"invalid":42}
	check(not Migration.plan(malformed,content).ok,"invalid cargo record fails safely")
	malformed=before.duplicate(true)
	malformed.world.combat_regions.R2.units=[42]
	check(not Migration.plan(malformed,content).ok,"invalid combat unit fails safely")
	test_repository()
	print("WORLDUI_MIGRATION_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"cargo_cases":cargo_cases,"failures":failures}))
	quit(1 if not failures.is_empty() else 0)

func test_repository() -> void:
	for failure in ["before_write","after_generation","after_manifest"]:
		fixture_counter+=1
		var path=ProjectSettings.globalize_path(fixture_root.path_join("case_"+str(fixture_counter)+"_"+str(Time.get_ticks_usec())))
		var repo=Repository.new(path)
		check(repo.load_profile(),"isolated repository loads")
		var legacy=profile(content.missions[6],content.missions[6].stages[1],{"m07_instrument":cargo("staged","M07-S1")})
		# Use the real cargo ID of the staged pickup.
		var a: Dictionary=content.missions[6].stages[1].actions[0]
		legacy.campaign.active_checkpoint.run_state.cargo_records={str(a.cargo_id):cargo("staged","M07-S1")}
		legacy.campaign.active_checkpoint.run_state.stage_start_cargo=legacy.campaign.active_checkpoint.run_state.cargo_records.duplicate(true)
		var fixture=repo.commit({"id":"fixture-old","parts_delta":817,"set":{"world":legacy.world,"campaign":legacy.campaign}})
		check(fixture.ok,"legacy fixture commits")
		var source=repo.data.duplicate(true)
		var old_file=path.path_join("profile_g%06d.json"%int(source.generation))
		var source_hash=FileAccess.get_sha256(old_file)
		repo.failure_point=failure
		var attempt=repo.ensure_layout_revision()
		check(not attempt.ok and repo.data==source,"failed migration keeps authority unchanged "+failure)
		repo.failure_point=""
		var retry=repo.ensure_layout_revision()
		check(retry.ok and int(repo.data.world.layout_revision)==1,"migration retry succeeds "+failure+" "+str(retry.get("error","")))
		check(repo.data.wallet.parts==817 and repo.data.profile_id==source.profile_id and repo.data.schema_version==2,"schema wallet profile preserved")
		check(repo.data.ledger.receipts.count("migration:world-layout:0-to-1")==1 and "fixture-old" in repo.data.ledger.receipts,"migration receipt once; prior ledger retained")
		var backup=path.path_join("layout_backups/revision_0_generation_%06d"%int(source.generation)).path_join("profile_g%06d.json"%int(source.generation))
		check(FileAccess.file_exists(backup) and FileAccess.get_sha256(backup)==source_hash,"legacy generation backed up exactly")
		var generation=int(repo.data.generation)
		check(repo.ensure_layout_revision().ok and repo.data.generation==generation,"second ensure causes no write")
		var reloaded=Repository.new(path)
		check(reloaded.load_profile() and reloaded.data.world.layout_revision==1 and reloaded.data.campaign.active_checkpoint.run_state==repo.data.campaign.active_checkpoint.run_state,"migration survives disk reload")
