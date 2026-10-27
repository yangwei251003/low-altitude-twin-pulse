extends GutTest

var profile: PilotProfile
var PATH=""

func before_each() -> void:
	PATH="user://qa_v2/gut_core_"+Crypto.new().generate_random_bytes(8).hex_encode()+"/profile.json"
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	profile=PilotProfile.new(PATH)
	profile.data=profile.defaults()
	profile.save_profile()

func test_campaign_unlocks_only_after_real_claim() -> void:
	assert_true(profile.can_play(0))
	assert_false(profile.can_play(1))
	assert_eq(profile.claim(0,"first",42.0,2,12.0,0,false),100)
	assert_true(profile.can_play(1))
	assert_false(profile.can_play(2))
	var reload=PilotProfile.new(PATH)
	reload.load_profile()
	assert_true(reload.can_play(1))
	assert_eq(int(reload.data.parts),100)

func test_same_result_cannot_duplicate_currency() -> void:
	profile.claim(0,"run-one",20,0,0,0,false)
	assert_eq(profile.claim(0,"run-one",20,0,0,0,false),0)
	assert_eq(profile.data.parts,100)
	assert_eq(profile.claim(0,"run-two",18,0,0,0,false),25)
	assert_eq(profile.data.parts,125)

func test_purchase_equip_and_load_budget_are_enforced() -> void:
	assert_false(profile.buy_module("charge"))
	assert_false(profile.equip("charge"))
	profile.data.parts=200
	assert_true(profile.buy_module("charge"))
	assert_false(profile.buy_module("charge"))
	assert_true(profile.equip("charge"))
	assert_true(profile.buy_module("agile"))
	assert_true(profile.equip("agile"))
	assert_eq(GameData.loadout_load(profile.data.loadout),8)
	assert_false(GameData.valid_loadout({"weapon":"shield","drive":"stable","utility":"shield"},profile.data.unlocked))

func test_facility_choice_is_saved_and_cannot_double_charge() -> void:
	profile.data.parts=100
	assert_true(profile.upgrade_facility("workshop"))
	assert_eq(profile.data.parts,50)
	assert_false(profile.upgrade_facility("workshop"))
	assert_eq(profile.data.parts,50)
	assert_true(profile.data.unlocked.has("charge"))
	var reload=PilotProfile.new(PATH);reload.load_profile()
	assert_true(reload.data.facility.has("workshop"))

func test_broken_primary_recovers_backup() -> void:
	profile.data.parts=77
	profile.save_profile()
	profile.save_profile()
	var bad=FileAccess.open(PATH,FileAccess.WRITE);bad.store_string("{broken");bad.close()
	var reload=PilotProfile.new(PATH);reload.load_profile()
	assert_eq(int(reload.data.parts),77)
	assert_true(reload.notice.contains("备份"))

func test_settings_and_loadout_survive_restart() -> void:
	profile.data.settings.auto_fire=true
	profile.data.settings.input={"axis_x":3,"axis_y":2,"invert_y":true,"deadzone":0.21}
	profile.save_profile()
	var reload=PilotProfile.new(PATH);reload.load_profile()
	assert_true(reload.data.settings.auto_fire)
	assert_eq(int(reload.data.settings.input.axis_x),3)

func test_score_separates_assists_and_equipment() -> void:
	profile.claim(0,"manual",25,0,0,0,false)
	profile.claim(0,"assisted",20,0,0,0,true)
	assert_eq(profile.data.records.size(),2)
	assert_eq(profile.best_time(0,0,false),25.0)
	assert_eq(profile.best_time(0,0,true),20.0)
	assert_eq(profile.best_time(0,1,false),-1.0)

func test_invalid_mission_does_not_change_wallet() -> void:
	assert_eq(profile.claim(-1,"bad",0,0,0,0,false),0)
	assert_eq(profile.claim(3,"bad",0,0,0,0,false),0)
	assert_eq(profile.data.parts,0)
