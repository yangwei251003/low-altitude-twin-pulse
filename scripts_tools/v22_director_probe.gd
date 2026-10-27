extends "res://tests_v2/test_v22_enemy_brain.gd"
## Small owner-run director subset using the same real collision fixtures.
func run() -> void:
	await test_director()
	await test_director_report()
	finish("director")
