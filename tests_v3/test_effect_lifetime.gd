extends SceneTree
## Real Tween scheduler; deterministic same-frame finish/resume reproduction.
const World = preload("res://scripts/v3/twin_test_world.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	var world = World.new()
	root.add_child(world)
	var flash = Node3D.new()
	world.add_child(flash)
	world._expire(flash, 0.01)
	var finished: Tween = world._effect_tweens[0]
	finished.custom_step(1.0)
	_check(flash.is_queued_for_deletion(), "effect completes in the current frame")
	_check(world._effect_tweens.is_empty(), "finished timer is removed before frame-end invalidation")
	world.set_effects_paused(true)
	world.set_effects_paused(false)
	await process_frame
	_check(not is_instance_valid(flash), "resume never restarts an expired effect")
	var paused_flash = Node3D.new()
	world.add_child(paused_flash)
	world.set_effects_paused(true)
	world._expire(paused_flash, 0.03)
	_check(not world._effect_tweens[0].is_running(), "an effect arriving while paused stays paused")
	await create_timer(0.08).timeout
	_check(is_instance_valid(paused_flash) and not paused_flash.is_queued_for_deletion(), "paused timer retains its actual effect beyond its duration")
	world.set_effects_paused(false)
	await create_timer(0.08).timeout
	_check(not is_instance_valid(paused_flash) and world._effect_tweens.is_empty(), "resume expires and unregisters the retained effect")
	var cancelled = Node3D.new()
	world.add_child(cancelled)
	world._expire(cancelled, 1.0)
	world._effect_tweens[0].kill()
	world.set_effects_paused(false)
	_check(world._effect_tweens.is_empty(), "cancelled timers are not resumed")
	world.queue_free()
	await process_frame
	print("EFFECT_LIFETIME ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
