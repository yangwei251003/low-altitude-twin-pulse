extends "res://scripts_tools/v3/acceptance_flight_driver.gd"
## Plays authored optional content through native flight, keys and transactions.
const Jobs = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const Sites = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const Notes = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const Field = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const PrecisePilot = preload("res://scripts_tools/v3/acceptance_route_pilot.gd")
var outcomes: Array = []

func play_region(region: String, mode: String) -> bool:
	if not await travel(region) or not await _dismiss(): return false
	if mode=="all" and region in Field.regions():
		if not await field_begin(region): return false
	if mode=="all" and region in ["I1","I2","F2","I3"]:
		if not await legacy_job(region): return false
	if mode in ["all","combat"]:
		for site: Dictionary in Sites.sites(region):
			if not await combat_site(site): return false
	if mode in ["all","stories"]:
		for job: Dictionary in Jobs.definitions(region):
			if not await short_story(job): return false
	if mode in ["all","secrets"]:
		for note: Dictionary in Notes.notes(region):
			if not await secret(note): return false
	if mode=="all" and region in Field.regions():
		if not await field_finish(region): return false
	return _healthy()

func _legacy(id: String) -> Dictionary:
	return session.world_cache.world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(id,{}).duplicate(true)

func follow_contact(id: String) -> bool:
	var actor: Dictionary = session.ecology.simulation.get_actor(id)
	if not _check(not actor.is_empty(),"contact is an actual living-world actor",id): return false
	if session.story.nearest(_body().global_position)==id: return await contact(id)
	if _body().global_position.distance_to(_v(actor.position))>12 and not await approach(_v(actor.position),id,4.1): return false
	var deadline := Time.get_ticks_msec()+45000
	var next_target := 0
	while _healthy() and Time.get_ticks_msec()<deadline:
		actor = session.ecology.simulation.get_actor(id)
		if session.story.nearest(_body().global_position)==id:
			return await contact(id)
		if Time.get_ticks_msec()>=next_target:
			var point := inspect_point(_v(actor.position),id,4.1)
			if point.is_finite(): serial+=1; pilot.go_to(point,serial)
			next_target=Time.get_ticks_msec()+400
		await _next()
	return _check(false,"native flight follows moving NPC into actual contact range",id)

func legacy_job(region: String) -> bool:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/npc_sidejob_"+region.to_lower()+".json"))
	var id := str(spec.id)
	var npc := str(spec.npc_id)
	if _legacy(id).get("status","")=="complete": _event("inherited_real_legacy_completion",id); return true
	if _legacy(id).is_empty():
		if not await follow_contact(npc) or not await follow_contact(npc): return false
	if not _check(not _legacy(id).is_empty(),"two ordinary NPC contacts create a real legacy commission",id): return false
	if region=="F2":
		for mirror: String in ["F2:clock_mirror","F2:clock_mirror_bypass"]:
			var at:=_v(session.entities[mirror].position)
			var observer:=Vector3.INF
			for index_angle in range(16):
				var angle:=TAU*float(index_angle)/16.0
				var candidate:=at+Vector3(cos(angle)*6.0,2.0,sin(angle)*6.0)
				if _hull_clear(candidate) and session._line_clear(candidate,at,_body().get_rid(),mirror):observer=candidate;break
			if not _check(observer.is_finite(),"stand-off inspection leaves mirror rotation envelope empty",mirror) or not await fly_to(observer,mirror+":safe_rotation_observer"):return false
			var goal := deg_to_rad(75 if mirror=="F2:clock_mirror" else 15)
			for _turn in range(12):
				if absf(wrapf(float(session.entities[mirror].angle)-goal,-PI,PI))<.002: break
				if not await ability(mirror,"light"): return false
			if not _check(absf(wrapf(float(session.entities[mirror].angle)-goal,-PI,PI))<.002,"ordinary mirror inputs reach the authored dual-reflection orientation",mirror):return false
	var deadline := Time.get_ticks_msec()+210000
	var next_follow := 0
	while _healthy() and _legacy(id).get("status","")!="complete" and Time.get_ticks_msec()<deadline:
		var row: Dictionary = _legacy(id)
		var actor: Dictionary = session.ecology.simulation.get_actor(npc)
		if row.get("status","")=="ready" or region in ["I1","I2"] and bool(actor.get("cargo",false)) and not bool(row.get("witnessed",false)):
			if not await follow_contact(npc): return false
		else:
			if region in ["I1","I2"] and Time.get_ticks_msec()>=next_follow:
				var point := inspect_point(_v(actor.position),npc,4.1)
				if point.is_finite() and _leg_clear(_body().global_position,point): serial+=1;pilot.go_to(point,serial)
				next_follow=Time.get_ticks_msec()+400
			await _next()
	if not _check(_legacy(id).get("status","")=="complete","actual new ecology/cargo/optics observations and nearby claim finish legacy commission",{"id":id,"saved":_legacy(id),"actor":session.ecology.simulation.get_actor(npc)}): return false
	var discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	if not await follow_contact(npc): return false
	if not _check(discoveries==session.store.snapshot().personal.discoveries and discoveries.count(str(spec.reward_id))==1,"legacy commission reward is unique on repeated actual contact",id): return false
	outcomes.append({"kind":"legacy_commission","id":id,"saved":_legacy(id)})
	return true

func _field(region: String) -> Dictionary:
	return session.world_cache.world.get("field_requests_next_v1",{}).get("jobs",{}).get(region,{}).duplicate(true)

func field_begin(region: String) -> bool:
	if _field(region).get("complete",false): _event("inherited_real_field_completion",region); return true
	var id := Field.contact_id(region)
	var marker: Dictionary = session.story.markers[id]
	if not await approach(session.story._point(marker),id,4.2): return false
	if _field(region).is_empty():
		if not await contact(id) or not await contact(id): return false
	if not _check(not _field(region).is_empty(),"explicit two-contact invitation accepts real field request",region): return false
	for index in range(2):
		var survey_id := Field.survey_id(region,index)
		if (int(_field(region).get("survey_bits",0))&(1<<index))!=0:_event("inherited_real_field_survey",survey_id);continue
		var survey: Dictionary = session.story.markers[survey_id]
		if not await approach(session.story._point(survey),survey_id,3.5): return false
		for _attempt in range(5):
			if not await contact(survey_id):return false
			var until:=Time.get_ticks_msec()+1800
			while _healthy() and (int(_field(region).get("survey_bits",0))&(1<<index))==0 and Time.get_ticks_msec()<until:await _next()
			if (int(_field(region).get("survey_bits",0))&(1<<index))!=0:break
		if not _check((int(_field(region).get("survey_bits",0))&(1<<index))!=0,"native near-G survey acknowledgement is saved before leaving",{"id":survey_id,"row":_field(region)}):return false
	return _check(int(_field(region).get("survey_bits",0))==3,"both physical survey contacts are saved",{"region":region,"row":_field(region)})

func field_finish(region: String) -> bool:
	if _field(region).get("complete",false): return true
	var deadline := Time.get_ticks_msec()+180000
	while _healthy() and str(_field(region).get("native_event_id","")).is_empty() and Time.get_ticks_msec()<deadline: await _next()
	if not _check(not str(_field(region).get("native_event_id","")).is_empty(),"new real NPC ecology task event follows acceptance",{"region":region,"row":_field(region)}): return false
	var id := Field.contact_id(region)
	if not await approach(session.story._point(session.story.markers[id]),id,4.2) or not await contact(id): return false
	var until:=Time.get_ticks_msec()+6000
	while _healthy() and not _field(region).get("complete",false) and Time.get_ticks_msec()<until:await _next()
	if not _check(_field(region).get("complete",false),"real field handoff durably completes",region): return false
	var discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	if not await contact(id): return false
	if not _check(session.store.snapshot().personal.discoveries==discoveries,"repeat field handoff grants no duplicate reward",region): return false
	outcomes.append({"kind":"field_request","region":region,"saved":_field(region)})
	return true

func _v(raw: Variant) -> Vector3:
	return raw if raw is Vector3 else Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

func _job(id: String) -> Dictionary:
	return session.world_cache.world.get("side_stories_dev88_v1",{}).get("jobs",{}).get(id,{}).duplicate(true)

func short_story(spec: Dictionary) -> bool:
	phase = "story:"+str(spec.id)
	var prior: Dictionary = _job(spec.id)
	if prior.get("complete",false): _event("inherited_real_short_story_completion",spec.id); return true
	var point := _v(spec.contact.position)
	if not await approach(point,str(spec.contact.id),4.1): return false
	if prior.is_empty():
		if not await contact(str(spec.contact.id)) or not await contact(str(spec.contact.id)): return false
		if not _check(not _job(spec.id).is_empty(),"ordinary invite then acceptance creates actual task",spec.id): return false
	var deadline := Time.get_ticks_msec()+600000
	while _healthy() and int(_job(spec.id).get("stage",0)) < spec.stages.size() and Time.get_ticks_msec() < deadline:
		var index := int(_job(spec.id).stage)
		var stage: Dictionary = spec.stages[index]
		_event("actual_saved_stage",{"id":spec.id,"stage":index,"type":stage.type})
		match str(stage.type):
			"ability":
				if not await ability_stage(spec,index,stage): return false
			"route":
				pilot=PrecisePilot.new()
				if not _check(pilot.bind(_body()),"original assisted controls bind for slow ring entry",spec.id):return false
				while int(_job(spec.id).stage)==index and _healthy():
					var ring:=int(_job(spec.id).route_index)
					var ring_point:=_v(stage.points[ring])
					var entered:=false
					for _entry_attempt in range(3):
						if _body().global_position.distance_to(ring_point)<=float(stage.radius)+.2:
							var outside:=Vector3.INF
							for direction_index in range(16):
								var angle:=TAU*float(direction_index)/16.0
								var candidate:=ring_point+Vector3(cos(angle),0,sin(angle))*(float(stage.radius)+3.0)
								if Regions.contains(session.region_id,candidate) and _hull_clear(candidate):outside=candidate;break
							if not _check(outside.is_finite(),"a physical outside-ring approach exists",ring_point) or not await fly_to(outside,str(spec.id)+":outside_ring"):return false
						if not await fly_to(ring_point,str(spec.id)+":authored_route"):return false
						var acknowledged_by:=Time.get_ticks_msec()+6500
						while _healthy() and int(_job(spec.id).stage)==index and int(_job(spec.id).route_index)==ring and Time.get_ticks_msec()<acknowledged_by:await _next()
						if int(_job(spec.id).stage)>index or int(_job(spec.id).route_index)>ring:entered=true;break
					if not _check(entered,"outside-to-inside low-speed flight is durably acknowledged before the next ring",{"job":spec.id,"ring":ring,"row":_job(spec.id)}):return false
				pilot=Pilot.new()
				if not _check(pilot.bind(_body()),"ordinary cruise controller rebinds after precision route",spec.id):return false
			"dock":
				if not await dock_stage(stage): return false
			"combat":
				if not session.combat_sites.completed(str(stage.site_id)):
					var found := false
					for site: Dictionary in Sites.sites(session.region_id):
						if site.id == stage.site_id:
							found = true
							if not await combat_site(site): return false
					if not _check(found,"authored combat site exists",stage.site_id): return false
			_:
				return _check(false,"supported authored task stage",stage)
		for _wait in range(24):
			await _next()
			if int(_job(spec.id).get("stage",0)) > index: break
		if not _check(int(_job(spec.id).get("stage",0)) > index,"real actions durably advance the current stage",{"id":spec.id,"stage":index,"saved":_job(spec.id)}): return false
	if not _check(int(_job(spec.id).get("stage",0)) == spec.stages.size(),"all authored steps become ready",spec.id): return false
	if not await approach(point,str(spec.contact.id),4.1) or not await contact(str(spec.contact.id)): return false
	if not _check(_job(spec.id).get("complete",false),"nearby explicit handoff commits actual completion",spec.id): return false
	var discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	if not await contact(str(spec.contact.id)): return false
	if not _check(session.store.snapshot().personal.discoveries == discoveries and discoveries.count(str(spec.reward_id)) == 1,"repeat contact cannot award twice",spec.reward_id): return false
	outcomes.append({"kind":"short_story","id":spec.id,"complete":true,"saved":_job(spec.id)})
	return true

func ability_stage(spec: Dictionary, index: int, stage: Dictionary) -> bool:
	var targets: Array = stage.targets
	var at := Vector3.ZERO
	for target: String in targets: at += _v(session.entities[target].position)
	at /= targets.size()
	if targets.size() > 1:
		var observer := Vector3.INF
		for elevation: float in [3.0,5.0,1.5]:
			for index_angle in range(16):
				var angle := TAU*float(index_angle)/16.0
				var candidate := at+Vector3(cos(angle)*4.5,elevation,sin(angle)*4.5)
				if not _hull_clear(candidate): continue
				var clear := true
				for id: String in targets:
					clear=clear and candidate.distance_to(_v(session.entities[id].position))<10 and session._line_clear(candidate,_v(session.entities[id].position),_body().get_rid(),id)
				if clear: observer=candidate;break
			if observer.is_finite(): break
		if not _check(observer.is_finite(),"a real clear position can reach both authored echo targets",spec.id): return false
		if not await fly_to(observer,str(spec.id)+":dual_operation"): return false
	else:
		if not await approach(at,str(targets[0]),4.1): return false
	for _attempt in range(8):
		if int(_job(spec.id).stage) > index: return true
		for id: String in targets:
			var selected := str(stage.abilities[0])
			if selected == "growth" and float(session.entities[id].get("growth",0)) >= .7 and "light" in stage.abilities: selected = "light"
			if selected=="growth":
				for _adjustment in range(8):
					var current_temperature: float=float(session.entities[id].get("temperature",20))
					if current_temperature>=0 and current_temperature<=60:break
					if not await ability(id,"heat",current_temperature>60):return false
				if maxf(float(session.entities[id].get("light_level",0)),float(session.entities[id].get("environment_light",0)))<.25:
					if not await ability(id,"light"):return false
			var reverse := false
			if selected == "heat":
				for clause: Dictionary in stage.get("requires",[]):
					if clause.field == "temperature" and clause.op == "lte" and (float(clause.value) <= 35 or float(session.entities[id].get("temperature",20)) > float(clause.value)): reverse = true
			if not await ability(id,selected,reverse): return false
			if int(_job(spec.id).stage) > index: return true
			var satisfied:=true
			for clause: Dictionary in stage.get("requires",[]):
				var actual: Variant=session.entities[str(clause.get("target",id))].get(str(clause.field))
				if clause.op=="eq":satisfied=satisfied and actual==clause.value
				elif clause.op=="gte":satisfied=satisfied and float(actual)>=float(clause.value)
				elif clause.op=="lte":satisfied=satisfied and float(actual)<=float(clause.value)
			if satisfied:
				var acknowledged_by:=Time.get_ticks_msec()+6500
				while _healthy() and int(_job(spec.id).stage)==index and Time.get_ticks_msec()<acknowledged_by:await _next()
				if int(_job(spec.id).stage)>index:return true
				return _check(false,"satisfied original operation receives its durable stage acknowledgement",{"job":spec.id,"stage":index,"row":_job(spec.id)})
	return _check(false,"authored ability conditions become true through ordinary actions",{"job":spec.id,"stage":index})

func dock_stage(stage: Dictionary) -> bool:
	var id := str(stage.body)
	var dock := _v(stage.position)
	var body: RigidBody3D = session.world.objects[id]
	for _attempt in range(24):
		var offset := dock-body.global_position
		if not bool(session.entities[id].get("pinned",false)):
			if _body().global_position.distance_to(body.global_position)>8.5 and not await approach(body.global_position,id,4.1): return false
			if not await ability(id,"force_field"): return false
		if offset.length() < float(stage.radius)*.8:
			for _wait in range(20): await _next()
			return _check(body.global_position.distance_to(dock) <= float(stage.radius) and body.linear_velocity.length() <= float(stage.max_speed),"native moving salvage settles inside real dock",{"id":id,"position":body.global_position,"dock":dock})
		var direction := Vector3(offset.x,0,offset.z).normalized()
		var observer := Vector3.INF
		for elevation: float in [1.8,2.7,3.5]:
			for angle: float in [0.0,.35,-.35,.7,-.7]:
				var candidate := body.global_position-direction.rotated(Vector3.UP,angle)*5.0+Vector3.UP*elevation
				if _hull_clear(candidate) and session._line_clear(candidate,body.global_position,_body().get_rid(),id): observer=candidate; break
			if observer.is_finite(): break
		if not _check(observer.is_finite(),"a real clear stand-off push position exists",{"id":id,"position":body.global_position}): return false
		if not await fly_to(observer,id+":stand_off_push"): return false
		if bool(session.entities[id].get("pinned",false)) and not await ability(id,"force_field",true): return false
		if not await ability(id,"push_pull"): return false
		var limit := Time.get_ticks_msec()+1200
		while _healthy() and Time.get_ticks_msec()<limit:
			await _next()
			if body.global_position.distance_to(dock) < float(stage.radius)*.8: break
		if not await ability(id,"force_field"): return false
	return _check(false,"salvage reaches dock through real push/pull",{"id":id,"position":body.global_position,"dock":dock})

func combat_site(spec: Dictionary) -> bool:
	if session.combat_sites.completed(str(spec.id)): return true
	if not await approach(_v(spec.terminal),str(spec.id),4.1) or not await contact(str(spec.id)): return false
	if not _check(session.combat_sites.active(),"normal station G starts a real encounter",spec.id): return false
	var envelope: Array = spec.bounds
	var centre := Vector3((float(envelope[0])+float(envelope[3]))*.5,(float(envelope[1])+float(envelope[4]))*.5,(float(envelope[2])+float(envelope[5]))*.5)
	if not await fly_to(centre,str(spec.id)+":enter_envelope"): return false
	var deadline := Time.get_ticks_msec()+240000
	var next_move := 0
	var move_index := 0
	while _healthy() and Time.get_ticks_msec()<deadline:
		var view: Dictionary = session.combat_sites.presentation()
		if str(view.get("phase","")) == "ready": break
		if str(view.get("phase","")) not in ["approach","running"]: return _check(false,"real encounter stays active until resolved",view)
		var target := ""
		for actor: Dictionary in view.get("actors",[]):
			if actor.alive and not actor.controlled and _body().global_position.distance_to(_v(actor.position)) < 35 and session._line_clear(_body().global_position,_v(actor.position),_body().get_rid(),str(actor.id)): target = str(actor.id); break
		if not target.is_empty():
			if not await select_target(target): return false
			fire = true
		else: fire = false
		if Time.get_ticks_msec() >= next_move:
			var angle := float(move_index)*TAU/5.0
			var point := centre+Vector3(cos(angle)*2.2,0,sin(angle)*2.2)
			if _hull_clear(point): serial += 1; pilot.go_to(point,serial)
			move_index += 1; next_move = Time.get_ticks_msec()+1700
		await _next()
	fire = false; Input.action_release("flight_fire")
	if not _check(str(session.combat_sites.presentation().get("phase","")) == "ready","actual threats and service requirements resolve",spec.id): return false
	if not await approach(_v(spec.terminal),str(spec.id),4.1) or not await contact(str(spec.id)): return false
	if not _check(session.combat_sites.completed(str(spec.id)),"return G commits unique encounter reward",spec.id): return false
	outcomes.append({"kind":"combat","id":spec.id,"serial":session.combat_sites.completion_serial(spec.id)})
	return true

func secret(note: Dictionary) -> bool:
	var id := str(note.id)
	var was_found: bool = id in session.story.found_notes
	if was_found: _event("inherited_real_secret_discovery",id);return true
	var marker: Dictionary = session.story.markers[id]
	if not await approach(session.story._point(marker),id,float(marker.get("radius",4.1))): return false
	var requirements: Array=marker.get("requires",[]).duplicate(true)
	var priorities: Dictionary={"temperature":0,"light_level":1,"charge":2,"growth":3,"pinned":4,"operated":5,"controlled":6}
	requirements.sort_custom(func(a: Dictionary,b: Dictionary):return int(priorities.get(a.get("field",""),50))<int(priorities.get(b.get("field",""),50)))
	for requirement: Dictionary in requirements:
		if requirement.get("kind","") == "player_speed": continue
		var target := str(requirement.target_id)
		var field := str(requirement.field)
		var selected := str({"growth":"growth","light_level":"light","charge":"charge","temperature":"heat","pinned":"force_field","operated":"echo","controlled":"takeover"}.get(field,""))
		if not _check(not selected.is_empty(),"exploration prerequisite has an authored physical interaction",requirement): return false
		if target != id and not await approach(_v(session.entities[target].position),target,4.1): return false
		for _attempt in range(8):
			var current: Variant = session.entities[target].get(field)
			var met: bool = current == requirement.value if requirement.op == "eq" else float(current) >= float(requirement.value) if requirement.op == "gte" else float(current) <= float(requirement.value)
			if met: break
			if selected=="growth":
				for _warmup in range(8):
					var temperature: float=float(session.entities[target].get("temperature",20))
					if temperature>=0 and temperature<=60:break
					if not await ability(target,"heat",temperature>60):return false
			if selected == "growth" and float(session.entities[target].get("light_level",0)) < .5:
				if not await ability(target,"light"): return false
			var reverse: bool = selected == "heat" and requirement.op == "lte"
			if not await ability(target,selected,reverse): return false
	if not was_found and not session.story._content_note_ready(1,marker): return _check(false,"real field work satisfies the record prerequisites",{"id":id,"hint":marker.get("requires_hint","")})
	if _body().global_position.distance_to(session.story._point(marker)) > float(marker.get("radius",4.1))-.1:
		if not await approach(session.story._point(marker),id,float(marker.get("radius",4.1))): return false
	if not await contact(id): return false
	if not _check(id in session.story.found_notes,"near/LOS investigation saves a real secret",id): return false
	var discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	if not await contact(id): return false
	if not _check(session.store.snapshot().personal.discoveries == discoveries and discoveries.count(str(note.discovery_id)) == 1,"re-reading a secret does not award again",id): return false
	outcomes.append({"kind":"secret_revisit" if was_found else "secret","id":id})
	return true
