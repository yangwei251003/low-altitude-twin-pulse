extends GutTest

func test_path_goes_around_a_wall_and_stays_inside_map() -> void:
	var nav=FlightNavigation.new()
	var obstacles: Array[Rect2]=[Rect2(-2,-8,4,16)]
	nav.configure(Rect2(-12,-12,24,24),obstacles)
	var path=nav.path(Vector3(-10,4,0),Vector3(10,4,0))
	assert_gt(path.size(),2)
	for point in path:
		assert_false(obstacles[0].has_point(point))
		assert_true(Rect2(-12,-12,24,24).has_point(point))

func test_each_map_has_distinct_layout_and_reachable_spawn_grid() -> void:
	assert_eq(ExpeditionMaps.MAPS.size(),3)
	for index in range(3):
		var spec=ExpeditionMaps.data(index)
		var b=ExpeditionMaps.bounds(index)
		assert_true(b.has_point(Vector2(spec.launch.x,spec.launch.z)))
		assert_gt(b.get_area(),7000.0)
		assert_gte(spec.objectives.size(),2)
		for objective in spec.objectives:assert_true(b.has_point(Vector2(objective.x,objective.z)))
	assert_ne(ExpeditionMaps.data(0).islands,ExpeditionMaps.data(1).islands)
	assert_ne(ExpeditionMaps.data(1).islands,ExpeditionMaps.data(2).islands)

func test_challenge_changes_attack_behavior_without_inflating_enemy_hp() -> void:
	assert_gt(GameData.DIFFICULTY[2].attackers,GameData.DIFFICULTY[0].attackers)
	assert_gt(GameData.DIFFICULTY[2].shot_speed,GameData.DIFFICULTY[0].shot_speed)
	assert_gt(GameData.DIFFICULTY[2].lead,GameData.DIFFICULTY[0].lead)
	assert_lt(GameData.DIFFICULTY[2].telegraph,GameData.DIFFICULTY[0].telegraph)
	assert_eq(GameData.DIFFICULTY[1].health,GameData.DIFFICULTY[2].health)

func test_derived_bonus_cannot_be_claimed_twice() -> void:
	var path="user://qa_v2/gut_bonus_"+Crypto.new().generate_random_bytes(8).hex_encode()+"/profile.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var p=PilotProfile.new(path)
	assert_eq(p.claim(0,"bonus-run",60,0,0,0,false,65),165)
	assert_eq(p.claim(0,"bonus-run",60,0,0,0,false,65),0)
	assert_eq(p.data.parts,165)
	assert_false(p.can_play(3))
