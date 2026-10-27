extends SceneTree
## Pure presentation contract, no physics/GUI/human usability claim.
## godot --headless --path PROJECT --script res://scripts/v3/tests/test_opening_guidance.gd
const Guidance = preload("res://scripts/v3/ui/twin_opening_guidance.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var checks = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)

func _run() -> void:
	var markers: Dictionary = {}
	var authored_objectives: Dictionary = {}
	for path in ["res://data/v3/actions/opening_actions.json", "res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json", "res://data/v3/actions/underdeck_action.json", "res://data/v3/actions/clinic_action.json"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			expect(false, "authored action JSON loads: " + path)
			_finish()
			return
		for marker in data.markers: markers[str(marker.id)] = marker
		for action in data.actions:
			for objective in action.objectives: authored_objectives[str(objective.id)] = objective
	# Explicit entity fixtures match current twin_test_world authored anchors.
	# They are input data, not an instantiated scene or world-physics evidence.
	var entities: Dictionary = {
		"F1:mirror":{"position":Vector3(-24, 5.2, 25), "name":"共脉折光环", "tags":["photosensitive", "rotatable"]},
		"F1:growth":{"position":Vector3(-16, 5.2, 26.35), "name":"活性根簇", "tags":["photosensitive", "growable"]},
	}
	var original_markers: Dictionary = markers.duplicate(true)
	var original_entities: Dictionary = entities.duplicate(true)
	for id in Guidance.OBJECTIVE_TARGETS:
		expect(authored_objectives.has(id), "mapped objective exists in production data: " + id)
		if authored_objectives.has(id):
			var matches = false
			for event in authored_objectives[id].events:
				if event.target_id == Guidance.OBJECTIVE_TARGETS[id]: matches = true
			expect(matches, "mapping preserves objective event target: " + id)
	var rescue: Dictionary = Guidance.resolve_anchor("I1:rescue_channel", "I1", markers, entities)
	expect(rescue.get("anchor_id") == "I1:rescue_pocket" and rescue.get("fallback", false), "first rescue fact points to destination, not one gate tool")
	var source: Array = markers["I1:rescue_pocket"].position
	expect(rescue.get("position") == Vector3(source[0], source[1], source[2]), "rescue position uses actual authored marker")
	expect(Guidance.resolve_anchor("I1:rescue:channel", "I1", markers, entities) == _requested(rescue, "I1:rescue:channel"), "objective and fact resolve same destination")
	var light: Dictionary = Guidance.resolve_anchor("F1:light_receiver", "F1", markers, entities)
	expect(light.get("anchor_id") == "F1:mirror" and light.get("position") == entities["F1:mirror"].position, "missing light fact resolves live mirror")
	expect(Guidance.resolve_anchor("F1:repair:grow", "F1", markers, entities).get("position") == entities["F1:growth"].position, "growth fact points to actual root receiver")
	entities["F1:mirror"].position += Vector3(0, 2, -1)
	expect(Guidance.resolve_anchor("F1:light_receiver", "F1", markers, entities).position == entities["F1:mirror"].position, "moved live source is used without stale cache")
	entities["F1:light_receiver"] = {"position":Vector3(2, 3, 4), "name":"真实接收点"}
	expect(Guidance.resolve_anchor("F1:light_receiver", "F1", markers, entities).get("fallback", true) == false, "exact entity overrides fallback")
	expect(Guidance.resolve_anchor("F1:repair:light", "F1", markers, entities).position == Vector3(2, 3, 4), "objective uses its existing exact event entity")
	entities["F1:light_receiver"].position = Vector3.INF
	expect(Guidance.resolve_anchor("F1:light_receiver", "F1", markers, entities).is_empty(), "invalid exact entity does not silently redirect to mirror")
	entities.erase("F1:light_receiver")
	expect(Guidance.resolve_anchor("F1:light_receiver", "I1", markers, entities).is_empty(), "cross-world fact does not expose other-world position")
	expect(Guidance.resolve_anchor("npc:atai", "I1", markers, {}).is_empty(), "NPC explicit region is respected")
	expect(Guidance.resolve_anchor("unknown", "F1", markers, entities).is_empty(), "unknown ID gives empty result")
	expect(Guidance.resolve_anchor("F1:light_receiver", "F1", {}, {}).is_empty(), "missing source has no invented coordinates")
	expect(Guidance.resolve_anchor("I1:whale_engaged", "I1", markers, {}).is_empty(), "not-yet-present boss gets no phantom origin")
	var bad_markers: Dictionary = {"bad":{"region":"I1", "position":[1, "2", 3]}, "npc:no_region":{"position":[0, 0, 0]}}
	expect(Guidance.resolve_anchor("bad", "I1", bad_markers, {}).is_empty(), "malformed marker coordinates rejected")
	expect(Guidance.resolve_anchor("npc:no_region", "I1", bad_markers, {}).is_empty(), "unscoped marker rejected")
	rescue.label = "caller edit"
	expect(markers == original_markers, "returned anchors do not alias or mutate markers")
	entities = original_entities.duplicate(true)
	var before: Dictionary = entities.duplicate(true)
	for id in Rules.DEFINITIONS:
		var hint: Dictionary = Guidance.ability_hint(id)
		expect(hint.get("range_m") == float(Rules.DEFINITIONS[id].range), "range comes from actual rules: " + id)
		expect(hint.get("target_required") == bool(Rules.DEFINITIONS[id].target), "target contract matches rules: " + id)
		expect(not hint.get("distance_known", true) and not hint.has("in_range"), "unknown distance is not falsely zero/in-range: " + id)
		expect(not hint.has("abilities") and hint.ability == id, "returns only selected ability: " + id)
	var distant: Dictionary = {"position":Vector3(3, 4, 12), "tags":["conductive"]}
	var charge: Dictionary = Guidance.ability_hint("charge", Vector3.ZERO, distant)
	expect(is_equal_approx(charge.distance_m, 13.0) and is_equal_approx(charge.approach_m, 1.0), "distance includes vertical difference (3,4,12 ->13m), charge range12m")
	expect(charge.distance_known and charge.distance_text.contains("13.0m") and charge.distance_text.contains("1.0m"), "computed charge distance replaces unknown defaults in presentation fields")
	expect(not charge.in_range and charge.height_delta_m == 4.0, "out-of-range and signed height remain separate")
	expect(charge.reverse_text == "X 抽能", "charge reverse matches session drain mode")
	var actor: Dictionary = {"owner":"1", "tags":["player"], "health":100, "energy":100.0, "position":Vector3.ZERO}
	var rule_entities: Dictionary = {"player:1":actor, "fixture":distant}
	var rules = Rules.new()
	var validation: Dictionary = rules.validate({"actor_id":"player:1", "ability":"charge", "target_id":"fixture"}, rule_entities, {"sender_id":"1", "line_of_sight":true})
	expect(validation.get("code") == "out_of_range", "real rules agree with displayed 13m refusal")
	for distance in [12.0, 12.0005, 12.002]:
		distant.position = Vector3(distance, 0, 0)
		var hint: Dictionary = Guidance.ability_hint("charge", Vector3.ZERO, distant)
		validation = rules.validate({"actor_id":"player:1", "ability":"charge", "target_id":"fixture"}, rule_entities, {"sender_id":"1", "line_of_sight":true})
		expect(hint.in_range == bool(validation.ok), "same 1mm range boundary as production rules: " + str(distance))
	var rotate: Dictionary = Guidance.ability_hint("light", Vector3.ZERO, entities["F1:mirror"])
	expect(rotate.action == "点亮并转环30°" and rotate.reverse_text == "X 熄灭光源", "rotatable light F turns; X does not reverse rotation")
	var growth: Dictionary = Guidance.ability_hint("growth")
	expect(not growth.has_reverse and growth.reverse_text.contains("X 与 F 相同"), "growth has no invented shrinking reverse")
	var blink: Dictionary = Guidance.ability_hint("blink", Vector3.ZERO, distant, Vector3(0, 0, 6))
	expect(blink.distance_m == 6.0 and blink.range_m == 9.0, "actual planned 6m blink distinct from rules 9m maximum")
	expect(blink.distance_known and blink.distance_text.contains("6.0m"), "planned blink point replaces unknown presentation distance")
	expect(not Guidance.ability_hint("blink", Vector3.ZERO, distant).distance_known, "blink never uses locked entity as destination")
	expect(not Guidance.ability_hint("charge", Vector3(NAN, 0, 0), distant).distance_known, "nonfinite actor does not produce fabricated distance")
	expect(Guidance.ability_hint("unknown", Vector3.ZERO, distant).is_empty(), "unknown ability is empty")
	expect(entities == before, "ability text does not mutate entity state")
	expect(Guidance.recommended_abilities("F1:mirror", entities["F1:mirror"]) == ["light"], "mirror suggests only actual light rotation")
	var plant: Dictionary = {"tags":["photosensitive", "growable"], "light_level":0.0}
	expect(Guidance.recommended_abilities("fixture:plant", plant) == ["light", "growth"], "ordinary unlit plant exposes light then growth")
	plant.environment_light = 1.0
	expect(Guidance.recommended_abilities("fixture:plant", plant) == ["growth"], "already illuminated plant suggests growth")
	plant.environment_light = 0.0
	expect(Guidance.recommended_abilities("F1:growth", plant) == ["growth"], "story receiver never suggests self-light as ring-beam substitute")
	plant.id = "F1:growth"
	expect(Guidance.ability_hint("growth", null, plant).note.contains("折光环"), "story receiver note explains external light prerequisite")
	var host: Dictionary = {"tags":["photosensitive", "growable", "thermal"], "light_level":0.0, "recovering":false}
	expect(Guidance.recommended_abilities("F1:crown_host_west", host) == ["light", "heat"], "unlit crown host preserves two response paths")
	host.light_level = 1.0
	expect(Guidance.recommended_abilities("F1:crown_host_west", host) == ["growth", "heat"], "lit crown host suggests growth or thermal route")
	host.recovering = true
	expect(Guidance.recommended_abilities("F1:crown_host_west", host) == ["heat"], "recovering host does not suggest rejected growth chain")
	var relay: Dictionary = {"tags":["conductive", "electrical", "mechanical", "hackable"]}
	expect(Guidance.recommended_abilities("I1:relay", relay) == ["charge", "takeover"], "relay uses actual conductive and mechanical tags")
	expect(Guidance.recommended_abilities("unknown", {}).is_empty(), "unknown/empty target has no guessed suggestions")
	expect(Guidance.recommended_abilities("unknown", {"tags":"growable"}).is_empty(), "malformed target tags handled safely")
	expect(Guidance.recommended_abilities("I1:stone", {"tags":["stone"]}).is_empty(), "inert stone does not gain arbitrary powers")
	for fixture in [plant, host, relay, entities["F1:mirror"]]:
		var prior: Dictionary = fixture.duplicate(true)
		var suggested: Array[String] = Guidance.recommended_abilities(str(fixture.get("id", "fixture")), fixture)
		expect(suggested.size() <= 2, "suggestion list never expands ten abilities")
		for ability in suggested: expect(Rules.DEFINITIONS.has(ability), "suggested ID exists in production rules")
		expect(fixture == prior, "recommendations do not change target")
	_finish()

func _requested(anchor: Dictionary, requested: String) -> Dictionary:
	var copy: Dictionary = anchor.duplicate(true)
	copy.requested_id = requested
	return copy

func _finish() -> void:
	print("OPENING_GUIDANCE_TEST " + JSON.stringify({"checks":checks, "failures":failures, "scope":"pure presentation/data contract; no GUI, physics, or human test"}))
	quit(0 if failures.is_empty() else 1)
