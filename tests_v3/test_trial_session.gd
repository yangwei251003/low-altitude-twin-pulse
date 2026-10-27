extends SceneTree
## Actual Assembly/Rules/FlightBody/PhysicsServer/Store integration with a small
## Session-port fixture. No MAIN hooks, ENet, GPU, playthrough or timing claim.
## Link TRIAL pose and pilot positions are declared QA setup; water is produced
## by real pulse/return physics, and knowledge only by the actual window rays.
const Adapter = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const Assembly = preload("res://scripts/v3/world/twin_trial_assembly.gd")
const Station = preload("res://scripts/v3/world/twin_trial_flow_station.gd")
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Consensus = preload("res://scripts/v3/core/twin_consensus.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var host
var guest
var adapter
var client
var body
var rules=Rules.new()
var checks: Array[Dictionary]=[]
var failures: Array[String]=[]
var finished:=false
var reads: Array[Dictionary]=[]
var baseline_personal: Dictionary={}
var baseline_rewards: Dictionary={}
var initial_pair: Dictionary={}
var complete_packet: Dictionary={}
var complete_world: Dictionary={}
var profile:=""

class NetworkPort extends RefCounted:
	var mode:="solo"
	var session_id:="qa-trial-session"
	var guests: Dictionary={2:{}}
	var events: Array[Dictionary]=[]
	func is_authority() -> bool: return mode!="guest"
	func send_event(peer: int, event: Dictionary) -> void: events.append({"peer":peer,"event":event.duplicate(true)})

class SessionPort extends Node3D:
	var network=NetworkPort.new()
	var consensus=Consensus.new()
	var region_id:="I1"
	var active:=true
	var owns_world:=true
	var simulation_paused:=false
	var received_session:=""
	var _resolving_decision:=false
	var entities: Dictionary={}
	var players: Dictionary={}
	var world_cache: Dictionary={}
	var notes: Array=[]
	var store
	func _commit(receipt: String, changes: Dictionary, _discovery: String="") -> bool:
		var tx: Dictionary={"id":receipt+":"+str(store.snapshot().generation),"set":changes}
		var result: Dictionary=store.commit(tx)
		if result.ok: world_cache=store.snapshot()
		return result.ok
	func _persistent_environment() -> Dictionary: return {} # No fabricated actor state is persisted.
	func _note(peer: int, message: String) -> void: notes.append([peer,message])
	func _note_all(message: String) -> void: notes.append([0,message])
	func _apply_pause_state() -> void: pass

class ErrorLog extends Logger:
	var errors: Array=[]
	func _log_error(fn: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger=ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant=null) -> void:
	checks.append({"passed":ok,"label":label,"detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	var count:=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile=arg.trim_prefix("--qa-profile=")
			count+=1
		elif arg.begins_with("--qa-network") or arg.begins_with("--qa-capture") or arg.begins_with("--qa-suite"):
			_check(false,"no sockets/capture/suite flags in this isolated fixture")
	if count!=1 or not profile.begins_with("qa_trial_session_") or profile!=profile.validate_filename():
		_check(false,"one fresh qa_trial_session_ profile is required")
	if not failures.is_empty():
		_finish()
		return
	var path: String="user://qa_v3_trial_session/"+profile
	if DirAccess.dir_exists_absolute(path) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		_check(false,"refuse existing QA directories")
		_finish()
		return
	create_timer(90).timeout.connect(func():
		if not finished:
			_check(false,"bounded fixture timeout")
			_finish())
	host=SessionPort.new()
	root.add_child(host)
	host.store=Store.new(path)
	var loaded: Dictionary=host.store.load_profile()
	_check(loaded.ok,"actual fresh Store opens",loaded)
	_check(host._commit("qa-bootstrap",{"world.flags":{}}),"bootstrap persists the isolated identity before transaction-fault comparisons")
	host.world_cache=host.store.snapshot()
	host.consensus.configure([1],int(host.world_cache.world_revision))
	adapter=Adapter.new()
	adapter.setup(host)
	adapter.gauge_read.connect(func(peer: int, observation: Dictionary): reads.append({"peer":peer,"observation":observation.duplicate(true)}))
	await _prepare_and_start()
	if _healthy(): await _real_samples_and_pending()
	if _healthy(): await _retained_restore()
	if _healthy(): await _network_ordering()
	_finish()

func _healthy() -> bool:
	return not finished and failures.is_empty() and logger.errors.is_empty()

func _settle() -> void:
	await physics_frame
	await physics_frame

func _prepare_and_start() -> void:
	var outside: Dictionary=adapter.prepare(host.world_cache.world,"I1",true)
	_check(outside.ok and outside.module==null and outside.state.is_empty() and not outside.needs_init,"unvisited absent trial keeps no background Assembly")
	adapter.adopt(outside,host.world_cache.world)
	var broken: Dictionary=host.world_cache.world.duplicate(true)
	broken.flags["I2:trial_future_result"]=true
	_check(not adapter.prepare(broken,"I2",true).ok,"missing mechanism cannot silently reset a reserved trial outcome")
	for point in ["before_write","after_write","before_publish"]:
		var before: Dictionary=host.store.snapshot()
		var candidate: Dictionary=adapter.prepare(before.world,"I2",true)
		_check(candidate.ok and candidate.needs_init and candidate.module.get_parent()==null,"prepare detached initial candidate: "+point)
		if not candidate.ok: return
		host.store.failure_point=point
		_check(not host._commit("trial-initial",{Adapter.STATE_PATH:candidate.state}),"real initial persistence fault rejects: "+point)
		_check(host.store.snapshot()==before and adapter.module==null and adapter.persistent_state().is_empty(),"failed save adopts no scene/history: "+point)
		var reread=Store.new(host.store.root_path)
		_check(reread.load_profile().ok and reread.snapshot()==before,"failed generation stays absent on independent reload: "+point)
		host.store.failure_point=""
		adapter.discard(candidate)
	var prepared: Dictionary=adapter.prepare(host.store.snapshot().world,"I2",true)
	_check(prepared.ok and host._commit("trial-initial",{Adapter.STATE_PATH:prepared.state}),"prepared initial pair commits before scene adoption")
	if not prepared.ok: return
	host.region_id="I2"
	host.add_child(prepared.module)
	adapter.adopt(prepared,host.world_cache.world)
	_check(adapter.ready and adapter.module.connection_status().ok,"actual Link and Station bind before host ready")
	initial_pair=adapter.module.snapshot()
	for definition in adapter.module.target_definitions(): host.entities[definition.id]=definition
	_check(host.entities.size()==4 and adapter.module.target_bodies.has(Station.RETURN_SWITCH),"four actual ability targets and separate physical return switch are exposed")
	body=Body.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze=true
	body.position=Vector3(25,10,5)
	host.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	host.players[1]=body
	adapter.sync_roster()
	baseline_personal=host.store.snapshot().personal.duplicate(true)
	baseline_rewards={"received":host.store.snapshot().ledger.guest_received.duplicate(true),"outbox":host.store.snapshot().ledger.guest_outbox.duplicate(true)}
	await _settle()
	var partial: Dictionary=adapter.module.snapshot()
	partial.link.axis.position_m=.8
	partial.station.runtime.simulation.nodes[Runtime.SOURCE].clean_ml=-1
	var before_pair: Dictionary=adapter.module.snapshot()
	_check(not adapter.module.apply_snapshot(partial).ok and adapter.module.snapshot()==before_pair,"invalid second component cannot move the first component")
	var old: Dictionary=adapter.persistent_state()
	old.station.version=1
	broken=host.world_cache.world.duplicate(true)
	broken.environment.I2_trial_flow=old
	_check(not adapter.prepare(broken,"I2",true).ok,"old unpublished standalone Station v1 is rejected")

func _place(point: Vector3) -> void:
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _step(delta: float) -> void:
	adapter.advance(delta)
	var timers: Dictionary=rules.advance_states(host.entities,delta)
	if not timers.ok or not rules.commit(timers,host.entities).ok:
		_check(false,"production ability timers must advance")
	await physics_frame

func _ability(ability: String, target: String) -> bool:
	var actor:="player:1"
	host.entities[actor]={"id":actor,"owner":"1","tags":["player"],"position":body.global_position,"energy":100.0,"health":100.0,"revision":0}
	var query:=PhysicsRayQueryParameters3D.create(body.global_position,adapter.module.entity_position(target),0xFFFFFFFF,[body.get_rid()])
	var hit: Dictionary=body.get_world_3d().direct_space_state.intersect_ray(query)
	var visible: bool=not hit.is_empty() and hit.collider.get_meta("entity_id","")==target
	var result: Dictionary=rules.resolve({"ability":ability,"actor_id":actor,"target_id":target,"mode":""},host.entities,{"sender_id":"1","line_of_sight":visible})
	if not result.ok: return false
	return rules.commit(result,host.entities,true).ok

func _real_samples_and_pending() -> void:
	await _place(Vector3(18,2,-.6))
	var generation: int=int(host.store.snapshot().generation)
	var read: Dictionary=adapter.observe_gauge(1,Runtime.RECEIVER_A)
	_check(read.ok and read.code=="reading_only" and reads.size()==1 and reads[-1].observation.volume_ml==0,"actual empty window emits a real UI reading only",read)
	_check(host.store.snapshot().generation==generation and adapter.observed_gauges()=={"A":{},"B":{}},"zero/partial samples create no hidden knowledge or write")
	# Explicit isolation starting pose; legal Link operation is covered in its
	# existing component suite. No water, ledger or sample is assigned here.
	var trial_pose: Dictionary=adapter.module.link.snapshot()
	trial_pose.axis.position_m=.8
	_check(adapter.module.link.apply_snapshot(trial_pose).ok,"declared TRIAL Link starting pose configures actual collision")
	adapter.sync_roster()
	await _place(Vector3(18,2.5,-.5))
	await _step(.01) # Observe inactive controller after a restore before takeover.
	_check(_ability("charge",Station.RELAY),"real LOS and Rules charge the physical relay")
	_check(_ability("takeover",Station.CONTROLLER),"real LOS and Rules authorize pulse owner")
	var count:=0
	while count<160 and not (adapter.module.station.status().both_samples_recorded and adapter.module.station.status().selector_position==0.0):
		await _step(.05)
		count+=1
		if not _healthy(): return
	var status: Dictionary=adapter.module.station.status()
	_check(status.both_samples_recorded and _volumes()==[160000,20000,20000],"real physical pulse creates two 20L samples with conserved 200L",status)
	await _place(Vector3(18,2,-.6))
	host.store.failure_point="before_publish"
	var saved_before: Dictionary=host.store.snapshot()
	read=adapter.observe_gauge(1,Runtime.RECEIVER_A)
	_check(not read.ok and adapter.has_pending_observation() and adapter.observed_gauges().A.is_empty(),"actual first complete reading waits for a failed Store commit",read)
	_check(host.store.snapshot()==saved_before,"read failure leaves prior disk generation/history intact")
	var first: Dictionary=adapter.pending_observation.A.duplicate(true)
	_check(first.sample.destination==Runtime.RECEIVER_A and first.sample==status.samples.B,"receiver A is validated against selection B's actual first sample")
	await _place(Vector3(18,1.35,-.5))
	_check(adapter.request_return(1).ok,"return intent uses actual pilot and first-hit switch")
	for unused in range(100):
		await _step(.05)
		if not _healthy(): return
	_check(_volumes()==[200000,0,0] and adapter.pending_observation.A==first,"real return changes current water while pending first reading remains immutable")
	host.store.failure_point=""
	var before_retry: Dictionary=adapter.module.snapshot()
	_check(adapter.retry_pending(),"retry persists latest current mechanism with earlier actual reading")
	_check(adapter.module.snapshot()==before_retry and adapter.observed_gauges().A==first,"successful save never rewinds the present valves, water or credit")
	var disk=Store.new(host.store.root_path)
	_check(disk.load_profile().ok and host.store.matches_persisted_value(adapter.persistent_state(),disk.snapshot().world.environment.I2_trial_flow),"independent Store readback contains the current pair and first reading")
	generation=int(host.store.snapshot().generation)
	await _place(Vector3(18,2,-.6))
	_check(adapter.observe_gauge(1,Runtime.RECEIVER_A).code=="already_observed" and host.store.snapshot().generation==generation,"duplicate real read returns actual UI data without repeating a commit")
	var proposed: Dictionary=host.consensus.propose("pause",{"paused":true},1)
	_check(proposed.ok,"real Consensus creates a ready shared decision fixture")
	generation=int(host.store.snapshot().generation)
	read=adapter.observe_gauge(1,Runtime.RECEIVER_B)
	_check(not read.ok and adapter.has_pending_observation() and adapter.observed_gauges().B.is_empty() and host.store.snapshot().generation==generation,"complete B reading cannot invalidate a pending shared decision by committing early")
	host.consensus.resolve(str(host.consensus.current_proposal().proposal_id),false)
	_check(adapter.retry_pending() and not adapter.observed_gauges().B.is_empty(),"returned-empty B window preserves completed selection A sample after decision clears")
	_check(adapter.observed_gauges().B.volume_ml==0 and adapter.observed_gauges().B.sample.destination==Runtime.RECEIVER_B,"historical sample and actual zero current level remain separate")
	_check(host.store.snapshot().personal==baseline_personal and host.store.snapshot().ledger.guest_received==baseline_rewards.received and host.store.snapshot().ledger.guest_outbox==baseline_rewards.outbox,"sampling and return grant no personal reward or receipt")
	complete_world=host.store.snapshot().world.duplicate(true)
	adapter.publish()
	complete_packet=host.network.events[-1].event.duplicate(true)

func _retained_restore() -> void:
	var saved: Dictionary=adapter.persistent_state()
	# prepare is being given an actual Store readback, whose JSON numbers are
	# floats. Compare its duplicated history to THAT exact persisted baseline;
	# separately verify the live-to-persisted boundary without numeric tolerance.
	var persisted_history: Dictionary=complete_world.environment.I2_trial_flow.observed_gauges.duplicate(true)
	_check(host.store.matches_persisted_value(saved.observed_gauges,persisted_history),"live first readings match the actual Store serialization boundary",{
		"live_volume_type":type_string(typeof(saved.observed_gauges.A.volume_ml)),
		"saved_volume_type":type_string(typeof(persisted_history.A.volume_ml)),
		"raw_dictionary_equal":saved.observed_gauges==persisted_history})
	var bad: Dictionary=complete_world.duplicate(true)
	bad.environment.I2_trial_flow.observed_gauges.A.sample.destination=Runtime.RECEIVER_B
	_check(not adapter.prepare(bad,"I2",true).ok,"wrong receiver/source-sample pairing rejects before adoption")
	bad=complete_world.duplicate(true)
	bad.environment.I2_trial_flow.link.geometry_sha256="unknown"
	_check(not adapter.prepare(bad,"I1",true).ok,"unknown Link geometry also rejects while away from I2")
	var away: Dictionary=adapter.prepare(complete_world,"F1",true)
	_check(away.ok,"off-region prepare accepts the actual saved history",away.get("error",""))
	_check(away.module==null,"off-region prepare creates no background physics")
	_check(away.state.observed_gauges==persisted_history,"off-region prepare exactly preserves every persisted history field")
	var old_module=adapter.module
	host.region_id="F1"
	adapter.adopt(away,complete_world)
	host.remove_child(old_module)
	old_module.free()
	var frozen: Dictionary=adapter.persistent_state()
	for unused in range(6): adapter.advance(1.0)
	_check(adapter.persistent_state()==frozen,"off-region does not advance clock, flow credit, levels or valves")
	var returning: Dictionary=adapter.prepare(complete_world,"I2",true)
	_check(returning.ok,"saved pair and history prepare for return")
	if not returning.ok: return
	host.region_id="I2"
	host.add_child(returning.module)
	adapter.adopt(returning,complete_world)
	adapter.sync_roster()
	_check(adapter.ready,"restored authority adopts both physical components",adapter.error)
	_check(adapter.observed_gauges()==persisted_history,"restored authority exactly preserves every committed observation field")
	adapter.set_paused(true)
	var paused: Dictionary=adapter.module.snapshot()
	adapter.advance(.25)
	_check(adapter.module.snapshot()==paused,"pause cannot consume stored water credit")
	adapter.publish()
	complete_packet=host.network.events[-1].event.duplicate(true)
	await _settle()

func _network_ordering() -> void:
	var viewport:=SubViewport.new()
	viewport.own_world_3d=true
	viewport.size=Vector2i(2,2)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	guest=SessionPort.new()
	guest.network.mode="guest"
	guest.owns_world=false
	guest.region_id="I2"
	guest.simulation_paused=true
	viewport.add_child(guest)
	client=Adapter.new()
	client.setup(guest)
	var candidate: Dictionary=client.prepare({},"I2",false)
	_check(candidate.ok,"guest prepares local geometry without adopting host history")
	guest.add_child(candidate.module)
	client.adopt(candidate,{})
	await _settle()
	var initial: Dictionary=client.module.snapshot()
	var foreign: Dictionary=complete_packet.duplicate(true)
	foreign.session_id="foreign-before-motion"
	foreign.serial=9000
	foreign.epoch=9000
	client.receive(foreign)
	client.receive(complete_packet)
	_check(not client.ready and client.module.snapshot()==initial,"early reliable frames cannot choose session or expose physical readiness")
	guest.received_session=complete_packet.session_id
	_check(client.consume(int(complete_packet.serial),int(complete_packet.epoch),"I2") and client.ready,"motion binds identity and applies both validated reliable components")
	_check(Adapter._same(client.module.snapshot(),{"link":complete_packet.state.link,"station":complete_packet.state.station}) and Adapter._same(client.observed_gauges(),complete_packet.state.observed_gauges),"first accepted paused frame restores exact pair and observed history")
	_check(_physical_matches(client.module),"first paused packet immediately publishes real Link, valve and float PhysicsServer transforms")
	var before: Dictionary=client.module.snapshot()
	var newer: Dictionary=complete_packet.duplicate(true)
	newer.serial=int(complete_packet.serial)+1
	_check(not client.consume(int(newer.serial),int(newer.epoch),"I2") and not client.ready,"new motion reference closes readiness until its exact reliable serial")
	client.receive(complete_packet)
	_check(not client.ready and client.module.snapshot()==before,"older reliable serial cannot release the new-reference barrier")
	client.receive(newer)
	_check(client.ready and client.module.snapshot()==before,"matching reliable packet restores readiness without inventing motion")
	var corrupt: Dictionary=newer.duplicate(true)
	corrupt.serial+=1
	corrupt.state.link.axis.position_m=0.0
	corrupt.state.station.runtime.simulation.nodes[Runtime.SOURCE].clean_ml=-1
	_check(not client.consume(int(corrupt.serial),int(corrupt.epoch),"I2"),"invalid candidate begins behind the new-frame barrier")
	client.receive(corrupt)
	_check(not client.ready and client.module.snapshot()==before and _physical_matches(client.module),"invalid Station/history cannot partially move Link or publish ready")
	var branch: Dictionary=complete_packet.duplicate(true)
	branch.epoch=int(complete_packet.epoch)+1
	branch.serial=int(corrupt.serial)+1
	branch.state=Adapter._envelope(initial_pair,{"A":{},"B":{}})
	client.receive(branch)
	_check(not client.ready,"future branch reliable event waits for its motion epoch")
	_check(client.consume(int(branch.serial),int(branch.epoch),"I2") and client.observed_gauges()=={"A":{},"B":{}},"new branch epoch may restore earlier legitimate knowledge and geometry")
	_check(not client.consume(int(newer.serial),int(newer.epoch),"I2"),"old motion epoch is rejected after branch restore")
	var stable: Dictionary=client.module.snapshot()
	client.advance(.25)
	_check(client.module.snapshot()==stable and _physical_matches(client.module),"guest never advances local water, axes or credit")
	client.reset_connection()
	guest.received_session="new-host-session"
	var reconnected: Dictionary=branch.duplicate(true)
	reconnected.session_id=guest.received_session
	reconnected.epoch=1
	reconnected.serial=1
	# Rebuild a local view to exercise first-frame reconstruction after reset.
	for child in guest.get_children():
		guest.remove_child(child)
		child.free()
	candidate=client.prepare({},"I2",false)
	guest.add_child(candidate.module)
	client.adopt(candidate,{})
	client.receive(reconnected)
	_check(client.consume(1,1,"I2") and client.ready and _physical_matches(client.module),"new host identity accepts low counters only after explicit connection reset")
	client.clear()
	viewport.queue_free()
	await _settle()

func _physical_matches(assembly) -> bool:
	for collection in [assembly.link.moving_bodies,assembly.station.selector_bodies,assembly.station.valve_bodies,assembly.station.float_bodies]:
		for value in collection.values():
			var actual: Transform3D=PhysicsServer3D.body_get_state(value.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not actual.is_equal_approx(value.global_transform): return false
	return true

func _volumes() -> Array:
	var result: Array=[]
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]: result.append(int(adapter.module.station.get_water_node(id).volume_ml))
	return result

func _finish() -> void:
	if finished: return
	finished=true
	_check(logger.errors.is_empty(),"no engine errors",logger.errors)
	print("TRIAL_SESSION_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks,"engine_errors":logger.errors,"profile":profile,"scope":"real physics + real Store + Session port; injected transport, no MAIN/ENet/GPU/playthrough"}))
	if adapter!=null: adapter.clear()
	if is_instance_valid(host): host.free()
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
