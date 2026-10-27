extends RefCounted
## One asynchronous physical capture barrier around the original Session save.
## Owns no state envelope, ledger, Store or physics step. Tick only AFTER the
## authority has advanced the ordinary live Canal in the current physics frame.
const MAX_WAIT_FRAMES := 14
const CARGO_WAIT_FRAMES := 1200
var _session
var _adapter: RefCounted
var _world: Node3D
var _operation: Callable
var _completion: Callable
var _started_frame := -1
var _last_frame := -1
var _pending := false
var last_result: Dictionary = {}

func setup(owner_session) -> void:
	if _session == owner_session: return
	cancel("session_changed")
	_session = owner_session

func request(operation: Callable, completion: Callable = Callable()) -> Dictionary:
	if _pending: return {"ok":false,"code":"save_already_pending"}
	if not is_instance_valid(_session) or not operation.is_valid() or not _session.active or not _session.owns_world or not _session.network.is_authority():
		return {"ok":false,"code":"active_save_authority_required"}
	_adapter = _session.canal
	_world = _session.world
	_operation = operation
	_completion = completion
	_started_frame = Engine.get_physics_frames()
	_last_frame = -1
	_pending = true
	last_result = {"ok":true,"code":"save_requested","completed":false}
	return last_result.duplicate()

func pending() -> bool:
	return _pending

func advance() -> Dictionary:
	if not _pending: return last_result.duplicate()
	var frame := Engine.get_physics_frames()
	if frame == _last_frame: return {"ok":true,"code":"already_polled_this_frame","completed":false}
	_last_frame = frame
	if not is_instance_valid(_session) or not _session.active or not _session.owns_world or not _session.network.is_authority() or not is_instance_valid(_world) or not is_same(_world, _session.world) or not is_same(_adapter, _session.canal):
		return _finish(false, "save_context_changed")
	var cargo_active: bool = _session.thermal_cargo.supported()
	var limit: int = CARGO_WAIT_FRAMES if cargo_active else MAX_WAIT_FRAMES
	if frame - _started_frame > limit: return _finish(false, "save_capture_timeout")
	if _adapter != null and not _adapter.status().physics_paused:
		var prepared: Dictionary = _adapter.prepare_scan_capture()
		if not prepared.get("ok", false): return _finish(false, str(prepared.get("code", "capture_prepare_failed")))
		if not prepared.get("ready", false): return {"ok":true,"code":"waiting_for_actual_physics","completed":false}
	if cargo_active:
		var cargo_ready: Dictionary = _session.thermal_cargo.prepare_save()
		if not cargo_ready.get("ok",false): return _finish(false,str(cargo_ready.get("code","cargo_capture_failed")))
		if not cargo_ready.get("ready",false): return {"ok":true,"code":"waiting_for_native_cargo","completed":false}
	# No await or simulation step between ready, capture and the original Store.
	var saved: bool = bool(_operation.call())
	return _finish(saved, "saved" if saved else "store_or_capture_rejected")

func cancel(code: String = "save_cancelled") -> Dictionary:
	if not _pending: return {"ok":true,"code":"no_pending_save","completed":true}
	return _finish(false, code)

func _finish(ok: bool, code: String) -> Dictionary:
	# Release before calling a continuation that may close/travel/change session.
	var released: Dictionary = {"ok":true}
	if _adapter != null: released = _adapter.release_scan_capture()
	if not released.get("ok", false):
		ok = false
		code = "capture_release:" + str(released.get("code", "failed"))
	var callback := _completion
	last_result = {"ok":ok,"code":code,"completed":true}
	_pending = false
	_adapter = null
	_world = null
	_operation = Callable()
	_completion = Callable()
	if callback.is_valid(): callback.call(last_result.duplicate())
	return last_result.duplicate()
