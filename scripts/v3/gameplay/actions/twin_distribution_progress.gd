class_name TwinDistributionProgress
extends RefCounted
## Pure host history/transaction preparation. Never moves a mechanism, emits a
## reward, runs rays, advances time, or accepts client-authored proof. The host
## passes a successful Cabinet.observe_back result, not a network intent.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const EXPOSE := "I2:distribution_audit:expose"
const FACT_TARGET := "I2:distribution_back_exposed"
const OBSERVED_FLAG := "I2:distribution_back_observed"
const DISCOVERY := "I2:distribution_back_route"
const MAX_SERIAL := 9007199254740000
const HISTORY_KEYS := ["version","back_observed","method","evidence"]
const EVIDENCE_KEYS := ["mechanism_serial","observer","cover_position_m","door_fraction","electric_latched","panel_hits","center_hits"]
const SAMPLE_KEYS := ["ok","code","mechanism_serial","method","observer","cover_position_m","door_fraction","electric_latched","panel_hits","center_hits"]
const CANDIDATE_KEYS := ["ok","code","changed","base_history_sha256","history"]
const SAVE_KEYS := ["ok","code","changed","base_history_sha256","envelope"]
var _configured := false
var _layout: Dictionary = {}
var _digest := ""
var _axis = Axis.new()
var _history := _empty_history()
var _pending: Dictionary = {}
var _save_permit := ""
var _restore_permit := ""
var _restore_base := ""
var _restore_serial := 0
var _latest_serial := 0

func configure(layout: Dictionary) -> Dictionary:
	if _configured: return _result(false,"already_configured")
	# Static validation only: no Cabinet instance/geometry/tree is constructed.
	var checked: Dictionary = Cabinet._validate_layout(layout)
	if not checked.ok: return checked
	var trial = Axis.new()
	checked=trial.configure(Cabinet._axis_config(layout))
	if not checked.ok: return checked
	_layout=layout.duplicate(true)
	_digest=_hash(layout)
	_axis=trial
	_configured=true
	return _result(true,"configured")

func snapshot() -> Dictionary:
	return _history.duplicate(true)

func prepare_observation(sample: Variant, mechanism: Variant) -> Dictionary:
	var checked := _mechanism(mechanism)
	if not checked.ok: return checked
	checked=validate_history(_history,mechanism)
	if not checked.ok: return checked
	if not sample is Dictionary or not _exact(sample,SAMPLE_KEYS) or not sample.ok is bool or not sample.ok or sample.code!="back_observed": return _result(false,"successful_host_sample_required")
	var evidence: Dictionary = {}
	for key in EVIDENCE_KEYS: evidence[key]=sample[key]
	var next := {"version":1,"back_observed":true,"method":sample.method,"evidence":evidence}
	checked=validate_history(next,mechanism)
	if not checked.ok: return checked
	# New evidence must match the actual current frame, not a historic pose plus
	# a reused successful ray result. Pending retry uses prepare_retry instead.
	if int(evidence.mechanism_serial)!=int(mechanism.serial) or not _same_pose(evidence,mechanism): return _result(false,"sample_current_pose_mismatch")
	if int(mechanism.serial)<_latest_serial: return _result(false,"stale_mechanism")
	_latest_serial=int(mechanism.serial)
	# First verified observation wins, including while its disk commit is pending.
	if not _pending.is_empty(): return _pending.duplicate(true)
	if _history.back_observed: next=snapshot()
	else: next=_normalize(next)
	_pending={"ok":true,"code":"observation_candidate","changed":next!=_history,
		"base_history_sha256":_hash(_history),"history":next}
	return _pending.duplicate(true)

func prepare_retry(candidate: Variant, current_mechanism: Variant) -> Dictionary:
	# Candidate deliberately contains NO mechanism snapshot. The host supplies
	# its latest frame immediately before the same Story/Store transaction.
	if not _configured: return _result(false,"not_configured")
	if not candidate is Dictionary or not _exact(candidate,CANDIDATE_KEYS) or _pending.is_empty() or _hash(candidate)!=_hash(_pending) or candidate.base_history_sha256!=_hash(_history): return _result(false,"candidate_not_prepared")
	var checked := validate_history(candidate.history,current_mechanism)
	if not checked.ok: return checked
	if int(current_mechanism.serial)<_latest_serial: return _result(false,"stale_mechanism")
	_latest_serial=int(current_mechanism.serial)
	var prepared := {"ok":true,"code":"save_prepared","changed":candidate.history!=_history,
		"base_history_sha256":_hash(_history),"envelope":{"version":1,
			"mechanism":current_mechanism.duplicate(true),"history":_normalize(candidate.history)}}
	_save_permit=_hash(prepared)
	return prepared

func adopt_saved(prepared: Variant) -> bool:
	# The external caller must call only AFTER its atomic persistent commit.
	if not prepared is Dictionary or not _exact(prepared,SAVE_KEYS) or _save_permit.is_empty() or _hash(prepared)!=_save_permit or prepared.base_history_sha256!=_hash(_history): return false
	if not _envelope(prepared.envelope).ok or int(prepared.envelope.mechanism.serial)!=_latest_serial: return false
	_history=_normalize(prepared.envelope.history)
	_pending.clear()
	_save_permit=""
	_restore_permit=""
	return true

func validate_history(history: Variant, mechanism: Variant) -> Dictionary:
	var checked := _mechanism(mechanism)
	if not checked.ok: return checked
	checked=_history_shape(history)
	if not checked.ok: return checked
	if not history.back_observed: return _result(true,"valid")
	var proof: Dictionary = history.evidence
	if int(proof.mechanism_serial)>int(mechanism.serial): return _result(false,"future_observation")
	if int(proof.mechanism_serial)==int(mechanism.serial) and not _same_pose(proof,mechanism): return _result(false,"same_serial_pose_mismatch")
	if float(proof.door_fraction)>float(mechanism.door_fraction): return _result(false,"door_travel_reversed")
	# Cover can close later. A completed permanent electric latch cannot reverse.
	if proof.electric_latched and not mechanism.electric_latched: return _result(false,"permanent_latch_reversed")
	return _result(true,"valid")

func prepare_restore(envelope: Variant, completed: Variant, flags: Variant, discoveries: Variant = [], enforce_story: bool = true) -> Dictionary:
	_restore_permit=""
	if not _configured: return _restore_result(false,"not_configured",false,{})
	var story := {"ok":true,"has_results":false,"exposed":false}
	if enforce_story:
		story=_story_state(completed,flags,discoveries)
		if not story.ok: return _restore_result(false,story.code,false,{})
	if envelope==null:
		if not enforce_story: return _restore_result(false,"network_state_required",false,{})
		if story.has_results: return _restore_result(false,"missing_distribution_with_results",false,{})
		return _permit_restore("needs_initialization",true,_empty_history(),0)
	var checked := _envelope(envelope)
	if not checked.ok: return _restore_result(false,checked.code,false,{})
	if enforce_story and story.exposed and not envelope.history.back_observed: return _restore_result(false,"completed_expose_without_history",false,{})
	return _permit_restore("restore_prepared",false,_normalize(envelope.history),int(envelope.mechanism.serial))

func adopt_restore(prepared: Variant) -> bool:
	if not prepared is Dictionary or not _exact(prepared,["ok","code","needs_init","history"]) or _restore_permit.is_empty() or _hash(prepared)!=_restore_permit or _restore_base!=_hash(_history) or not _history_shape(prepared.history).ok: return false
	_history=_normalize(prepared.history)
	_latest_serial=_restore_serial
	_restore_permit=""
	_save_permit=""
	_pending.clear()
	return true

func fact_for(objective_id: String) -> Dictionary:
	if _configured and objective_id==EXPOSE and _history.back_observed:
		return {"kind":"fact","target":FACT_TARGET,"option":str(_history.method)}
	return {}

func _mechanism(raw: Variant) -> Dictionary:
	if not _configured: return _result(false,"not_configured")
	return Cabinet._check_snapshot(raw,_digest,_axis)

func _envelope(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,["version","mechanism","history"]) or not _integer(raw.version,1,1): return _result(false,"distribution_envelope")
	return validate_history(raw.history,raw.mechanism)

func _history_shape(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,HISTORY_KEYS): return _result(false,"history_keys")
	if not _integer(raw.version,1,1) or not raw.back_observed is bool or not raw.method is String or not raw.evidence is Dictionary: return _result(false,"history_types")
	if not raw.back_observed:
		return _result(raw.method=="" and raw.evidence.is_empty(),"valid" if raw.method=="" and raw.evidence.is_empty() else "empty_history_mismatch")
	if raw.method not in ["manual","service_lock"] or not _exact(raw.evidence,EVIDENCE_KEYS): return _result(false,"evidence_keys_or_method")
	var proof: Dictionary = raw.evidence
	if not _integer(proof.mechanism_serial,1,MAX_SERIAL) or not _number(proof.cover_position_m,0,1.2) or not _number(proof.door_fraction,0,1) or not proof.electric_latched is bool: return _result(false,"evidence_pose")
	if proof.electric_latched!=(float(proof.door_fraction)==1.0): return _result(false,"evidence_latch")
	if not proof.observer is Array or proof.observer.size()!=3 or not _number(proof.observer[0],-28,28) or not _number(proof.observer[1],-3,18) or not _number(proof.observer[2],-28,28): return _result(false,"evidence_observer")
	if not proof.panel_hits is Array or proof.panel_hits.size()!=2 or not proof.center_hits is Array or proof.center_hits.size()!=2: return _result(false,"evidence_hits")
	for i in range(2):
		if not _integer(proof.panel_hits[i],3,5) or not proof.center_hits[i] is bool or not proof.center_hits[i]: return _result(false,"evidence_hits")
	if raw.method=="manual" and float(proof.cover_position_m)<=0.0: return _result(false,"manual_cover_closed")
	if raw.method=="service_lock" and float(proof.door_fraction)<=0.0: return _result(false,"service_door_closed")
	# A pure plausibility check; it does NOT re-run physics or prove an arbitrary
	# caller's claims. Only the host's observe_back result is an authorized source.
	var sensor := Cabinet._v(proof.observer)-Cabinet._v(_layout.origin)
	var obs: Dictionary = _layout.observation
	var interior := Cabinet._bounds_box(obs.interior)
	var well := Cabinet._bounds_box(obs.well)
	var opening := Cabinet._bounds_box(obs.door_opening)
	var cover_size := Cabinet._v(_layout.cover.size)
	var cover_center := Cabinet._v(_layout.cover.center)+Vector3.RIGHT*float(proof.cover_position_m)
	var door_size := Cabinet._v(_layout.door.size)
	var door_center := Cabinet._v(_layout.door.center)+Vector3.UP*float(_layout.door.travel_m)*float(proof.door_fraction)
	for panel in _layout.panels:
		var point := Cabinet._v(panel.center)+Vector3.BACK*float(panel.size[2])*0.5
		var direction := sensor-point
		if direction.length()>float(obs.max_distance_m) or direction.length()<0.0001 or direction.normalized().dot(Vector3.BACK)<float(obs.min_facing_dot): return _result(false,"evidence_distance_or_facing")
		if _segment_hits_box(sensor,point,AABB(cover_center-cover_size*0.5,cover_size)) or _segment_hits_box(sensor,point,AABB(door_center-door_size*0.5,door_size)): return _result(false,"evidence_actuator_occluded")
		if raw.method=="manual":
			if sensor.y<=well.end.y or point.y>=well.position.y or not Cabinet._crosses_y(sensor,point,well.position.y,well) or not Cabinet._crosses_y(sensor,point,well.end.y,well): return _result(false,"manual_route_geometry")
		elif not interior.has_point(sensor):
			var plane: float = float(_layout.door.center[2])
			if sensor.z<=plane or point.z>=plane: return _result(false,"service_route_geometry")
			var hit := sensor.lerp(point,(sensor.z-plane)/(sensor.z-point.z))
			if hit.x<=opening.position.x or hit.x>=opening.end.x or hit.y<=opening.position.y or hit.y>=opening.end.y: return _result(false,"service_route_geometry")
	return _result(true,"valid")

static func _segment_hits_box(start: Vector3, finish: Vector3, box: AABB) -> bool:
	var low := 0.0
	var high := 1.0
	for axis in range(3):
		var delta: float = finish[axis]-start[axis]
		if absf(delta)<0.000000001:
			if start[axis]<box.position[axis] or start[axis]>box.end[axis]: return false
		else:
			var first: float = (box.position[axis]-start[axis])/delta
			var last: float = (box.end[axis]-start[axis])/delta
			low=maxf(low,minf(first,last))
			high=minf(high,maxf(first,last))
			if high<low: return false
	return high>=low

static func _same_pose(evidence: Dictionary, mechanism: Dictionary) -> bool:
	return float(evidence.cover_position_m)==float(mechanism.axis.position_m) and float(evidence.door_fraction)==float(mechanism.door_fraction) and evidence.electric_latched==mechanism.electric_latched

static func _story_state(completed: Variant, flags: Variant, discoveries: Variant) -> Dictionary:
	if not completed is Array or not discoveries is Array or not flags is Dictionary or completed.size()>256 or discoveries.size()>512 or flags.size()>512: return _result(false,"story_bounds")
	var sets: Array = []
	for ids in [completed,discoveries]:
		var seen: Dictionary = {}
		for id in ids:
			if not id is String or id.is_empty() or id.length()>128 or seen.has(id): return _result(false,"story_ids")
			seen[id]=true
		sets.append(seen)
	for key in flags:
		if not (key is String or key is StringName) or str(key).length()>128: return _result(false,"flag_key")
	if flags.has(OBSERVED_FLAG) and not flags[OBSERVED_FLAG] is bool: return _result(false,"observed_flag_type")
	var exposed: bool = sets[0].has(EXPOSE)
	var recorded: bool = flags.get(OBSERVED_FLAG,false)
	var discovered: bool = sets[1].has(DISCOVERY)
	# Store.switch_branch replaces world only. Personal discoveries survive an
	# earlier branch's completion, so they may precede this branch's observation.
	# Current-world completion still requires both its flag and personal receipt.
	if exposed!=recorded or (exposed and not discovered): return _result(false,"distribution_story_mismatch")
	return {"ok":true,"code":"valid","has_results":exposed or recorded,"exposed":exposed}

func _permit_restore(code: String, needs_init: bool, history: Dictionary, serial: int) -> Dictionary:
	var result := _restore_result(true,code,needs_init,history)
	_restore_permit=_hash(result)
	_restore_base=_hash(_history)
	_restore_serial=serial
	return result

static func _empty_history() -> Dictionary:
	return {"version":1,"back_observed":false,"method":"","evidence":{}}

static func _normalize(raw: Dictionary) -> Dictionary:
	var next := raw.duplicate(true)
	next.version=1
	if next.back_observed:
		next.evidence.mechanism_serial=int(next.evidence.mechanism_serial)
		next.evidence.cover_position_m=float(next.evidence.cover_position_m)
		next.evidence.door_fraction=float(next.evidence.door_fraction)
		for i in range(3): next.evidence.observer[i]=float(next.evidence.observer[i])
		for i in range(2): next.evidence.panel_hits[i]=int(next.evidence.panel_hits[i])
	return next

static func _hash(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and floor(float(value))==float(value)

static func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code}

static func _restore_result(ok: bool, code: String, needs_init: bool, history: Dictionary) -> Dictionary:
	return {"ok":ok,"code":code,"needs_init":needs_init,"history":history.duplicate(true)}
