extends "res://tests_v3/test_boss_hit_amount.gd"
## Source-only regression after OWNER_VITALS.patch; original MAIN, bodies and Crown.
const CrownEncounter = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
# QA observation only: count the original accepted playback return, not variants.
class ObservedAudio extends "res://scripts/v3/audio/twin_audio.gd":
	var accepted_vitals: Dictionary = {"disabled":0,"revived":0}
	func play_event(cue_id: String, at: Vector3 = Vector3.ZERO, options: Dictionary = {}) -> bool:
		var accepted: bool = super.play_event(cue_id,at,options)
		if accepted and accepted_vitals.has(cue_id):
			accepted_vitals[cue_id] = int(accepted_vitals[cue_id])+1
		return accepted
class PhysicsWitness extends Node:
	var probe: SceneTree
	func _physics_process(_delta: float) -> void:
		probe.call("_witness_physics")

var crash_witness: Dictionary = {}
var reset_witness: Dictionary = {}
var reset_before := -1
var crown_vitals_before: Dictionary = {}

func _scope() -> String:
	return "Fresh private source MAIN/F1. Explicit whole-hull-clear PLAYER observation pose and accepted DamageModel prior-hull-injury fixture; no direct health/clock/Boss/environment edits. Original Crown development start and natural ticks cause a real lethal hit and synchronous reset, not earned campaign access. A presentation-only QA Audio subclass counts true returns from original super.play_event; logical ingress also cross-checks original diagnostics.played. These are accepted playback requests, not fabricated Stats or human listening. Logical Guest ingress/owner/session/region/duplicate fixtures are not ENet. Healthy common-pause/baseline checks do not repeat the separately validated paused downed lifecycle fix. Original inherited bounded QA teardown, no new normal-quit/LAN/audio-output claim."

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_audio_vitals_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/audio-vitals-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	boss="crown"; region="F1"; began=Time.get_ticks_msec()
	create_timer(35.0).timeout.connect(func():
		if not finished: _check(false,"35 second bounded actual MAIN audio vitals",_diagnostics()); _finish())
	session=MAIN.instantiate()
	# Replace only the empty, not-yet-ready Audio Node before normal Session setup.
	# MAIN/Session remain original; do not set_script on an instantiated Session.
	var unused_audio: Node=session.audio
	session.audio=ObservedAudio.new()
	unused_audio.free()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo") and session._load_region("F1"),"fresh original MAIN private Store and ordinary F1 factory"): _finish(); return
	session.inputs.test_enabled=true
	session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
	for unused in 3:
		if not await _frame(): return
	if not _check(session.audio.diagnostics().ready and session.audio._listener_ready,"real Session audio/listener bound"): _finish(); return
	var generation: int=session.store.snapshot().generation
	var personal: Dictionary=session.store.snapshot().personal.duplicate(true)
	if not await _poll_retry(): _finish(); return
	if not _check(session.store.snapshot().generation==generation and session.store.snapshot().personal==personal,"accepted life cues write no Store/reward or progression"): _finish(); return
	if not await _receiver_and_pause(): _finish(); return
	if not await _actual_crown(): _finish(); return
	fixtures.append({"kind":"actual_Crown_post_physics_witness","crash":crash_witness,"reset":reset_witness})
	var before: Dictionary=_counts()
	# Public rebinding exercises the same fresh-observation baseline, not ENet.
	session.audio.bind_session(session)
	for unused in 3:
		if not await _frame(): return
	if not _check(_counts()==before,"fresh observation/rebind does not replay saved vitals"): _finish(); return
	if not _check(session._load_region("I1"),"ordinary factory region change for baseline"): _finish(); return
	for unused in 3:
		if not await _frame(): return
	_check(_counts()==before and session.audio.diagnostics().region=="I1","region baseline creates no disabled/revived cue")
	_check(session.store.snapshot().personal==personal,"no life-cue discovery/reward writes")
	_finish()

func _counts() -> Dictionary:
	return session.audio.accepted_vitals.duplicate()

func _advanced(before: Dictionary, disabled: int, revived: int) -> bool:
	var now: Dictionary=_counts()
	return now.disabled==before.disabled+disabled and now.revived==before.revived+revived

func _poll_retry() -> bool:
	var body: FlightBodyV2=session.players[1]
	var native_id: int=body.get_instance_id()
	var before: Dictionary=_counts()
	var hit: Dictionary=body.apply_combat_hit(100000.0,Vector3.ZERO,body.global_position,"collision",{"qa_fixture":"accepted_lethal_hull_damage"})
	fixtures.append({"kind":"accepted_DamageModel_lethal_fixture_not_an_enemy_attack","receipt":hit})
	if not _check(hit.get("killed",false) and not body.enabled and _advanced(before,1,0),"accepted crash_started emits one disabled cue before rendering",{"cues":_counts(),"hit":hit}): return false
	for unused in 3:
		if not await _frame(): return false
	if not _check(body.health==0 and _advanced(before,1,0),"normal zero-health rendering/polling cannot duplicate disabled"): return false
	session.network.send_action("retry",{})
	if not _check(body.enabled and body.health>0 and body.get_instance_id()==native_id and _advanced(before,1,1),"original accepted retry restores same body and emits one revived at listener",_counts()): return false
	for unused in 3:
		if not await _frame(): return false
	session.network.send_action("retry",{})
	return _check(_advanced(before,1,1),"positive-health polling and healthy retry do not duplicate revived",_counts())

func _receiver_and_pause() -> bool:
	var before: Dictionary=_counts()
	session._request_pause()
	for unused in 30:
		if not await _frame(): return false
		if session.simulation_paused: break
	if not _check(session.simulation_paused,"original solo Consensus accepts common pause"): return false
	var event: Dictionary=_event("paused-owner")
	if not _check(not session.audio.receive_event(event) and _counts()==before,"paused owner cue is rejected; no new pause queue"): return false
	session._request_pause()
	for unused in 30:
		if not await _frame(): return false
		if not session.simulation_paused: break
	if not _check(not session.simulation_paused and _counts()==before,"original resume creates no health cue"): return false
	# Cooldown is an original cue policy, not bypassed by this regression.
	var until: int=Time.get_ticks_msec()+1050
	while Time.get_ticks_msec()<until:
		if not await _frame(): return false
	var played_before: int=int(session.audio.diagnostics().played)
	var old_mode: String=session.network.mode
	var old_session: String=session.received_session
	session.network.mode="guest"; session.received_session=session.network.session_id
	event=_event("logical-owner-receive")
	var wrong: Dictionary=event.duplicate(true); wrong.session_id="old-session"; session._network_event(wrong)
	wrong=event.duplicate(true); wrong.region="I1"; session._network_event(wrong)
	wrong=event.duplicate(true); wrong.owner_id=2; session._network_event(wrong)
	var rejected: bool=_counts()==before and int(session.audio.diagnostics().played)==played_before
	session._network_event(event)
	session._network_event(event)
	var accepted_once: bool=_advanced(before,1,0) and int(session.audio.diagnostics().played)==played_before+1
	session.network.mode=old_mode; session.received_session=old_session
	var ingress: Dictionary={"kind":"logical_Guest_audio_ingress_only_not_ENet","event_id":event.event_id,"local_id":session.network.local_id(),"cues_before":before,"cues_after":_counts(),"played_before":played_before,"played_after":int(session.audio.diagnostics().played)}
	fixtures.append(ingress)
	return _check(rejected and accepted_once,"original session/region gates, owner isolation and duplicate event_id reject; one valid owner receive",ingress)

func _event(id: String) -> Dictionary:
	return {"kind":"audio","cue":"disabled","position":session.players[1].global_position,"emitter":"local_damage","owner_id":1,"session_id":session.network.session_id,"region":session.region_id,"event_id":"qa-vitals:"+id}

func _actual_crown() -> bool:
	var body: FlightBodyV2=session.players[1]
	var point:=Vector3(0,8,-18)
	if not _check(_clear_pose(point),"candidate PLAYER observation pose is whole-hull clear",point) or not await _place(point): return false
	body.freeze=false # Restore ordinary physics after the inherited one-time QA pose.
	var prior: Dictionary=body.apply_combat_hit(body.health-2.0,Vector3.ZERO,body.global_position,"collision",{"qa_fixture":"accepted_prior_hull_injury_only"})
	fixtures.append({"kind":"accepted_prior_hull_injury_not_direct_HP_edit","receipt":prior,"pose_not_flown":point})
	if not _check(not prior.is_empty() and body.enabled and is_equal_approx(body.health,2.0),"original DamageModel produces low live health without HP assignment",prior): return false
	crown_vitals_before=_counts()
	reset_before=session.crown.reset_serial
	body.crash_started.connect(_crash_seen)
	var witness:=PhysicsWitness.new(); witness.probe=self; witness.process_physics_priority=1000; session.add_child(witness)
	session._start_boss(false)
	if not _check(session.crown.active(),"original Crown development start, not campaign progression"): return false
	var deadline: int=Time.get_ticks_msec()+8000
	var geometry: Dictionary={}
	while Time.get_ticks_msec()<deadline and reset_witness.is_empty():
		if not await _frame(): return false
		var attack: Dictionary=_state().get("attack",{})
		if geometry.is_empty() and not attack.is_empty():
			var inside:=false
			for shape: Dictionary in attack.shapes: inside=inside or CrownEncounter.contains_shape(shape,session.world.crown_arena.to_local(body.global_position))
			geometry={"inside":inside,"los":session.world.crown_arena.attack_line_clear(attack,body.global_position,body.get_rid()),"token":attack.token,"pose":body.global_position}
			if not _check(inside and geometry.los,"first real Crown telegraph shape and native LOS reach live actor",geometry): return false
	fixtures.append({"kind":"actual_first_Crown_attack_geometry","readback":geometry})
	return _check(not reset_witness.is_empty() and reset_witness.frame==crash_witness.get("frame",-1) and reset_witness.health>0 and reset_witness.cues.disabled==crown_vitals_before.disabled+1 and reset_witness.cues.revived==crown_vitals_before.revived+1,"natural Crown lethal attack restores in same physics tick with each accepted owner cue exactly once",{"crash":crash_witness,"reset":reset_witness})

func _crash_seen() -> void:
	crash_witness={"frame":Engine.get_physics_frames(),"health":session.players[1].health,"cues":_counts()}

func _witness_physics() -> void:
	if reset_before<0 or not reset_witness.is_empty() or session.crown.reset_serial<=reset_before: return
	reset_witness={"frame":Engine.get_physics_frames(),"health":session.players[1].health,"cues":_counts(),"reset_serial":session.crown.reset_serial}
