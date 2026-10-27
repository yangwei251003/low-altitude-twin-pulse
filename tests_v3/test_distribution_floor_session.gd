extends "res://tests_v3/test_distribution_session.gd"
## Reuses the real MAIN safety guards, logger, callback isolation and exact JSON
## comparison from the distribution integration fixture. This script does not
## execute its parent's play/transport scenarios. Historical observations are
## explicitly saved-state fixtures prepared through the real legacy Progress.
const FloorMigration = preload("res://scripts/v3/world/twin_distribution_layout_migration.gd")
const DistributionAdapter = preload("res://scripts/v3/gameplay/twin_distribution_session.gd")
const RECEIPT := "qa:distribution-floor-existing-receipt"
var legacy_layout: Dictionary = {}
var fixture_envelopes: Dictionary = {}
var input_hashes: Dictionary = {}

func _run() -> void:
	var count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile=arg.trim_prefix("--qa-profile=")
			count+=1
		elif arg.begins_with("--qa-"):
			check(false,"refuse unrelated automated drivers")
			_finish(2)
			return
	if count!=1 or not profile.begins_with("qa_distribution_floor_") or profile!=profile.validate_filename():
		check(false,"one fresh --qa-profile=qa_distribution_floor_<unique> is required")
		_finish(2)
		return
	base="user://qa_v3_distribution_floor/"+profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		check(false,"refuse any pre-existing test/profile directory")
		_finish(2)
		return
	create_timer(120.0).timeout.connect(func():
		if not done:
			check(false,"bounded floor migration integration timed out")
			_finish(2))
	for path in [FloorMigration.LEGACY_PATH,Cabinet.PATH]: input_hashes[path]=FileAccess.get_sha256(path)
	if not _build_floor_fixtures():
		_finish(1)
		return
	_prepare_matrix_and_rejection()
	if _healthy(): _store_branch_cas()
	if _healthy(): await _startup_rejections()
	if _healthy(): await _startup_migration("I1","manual")
	if _healthy(): await _startup_migration("I2","service_lock","host")
	if _healthy(): _environment_save_idempotency()
	if _healthy(): await _real_branch_switch()
	for path in input_hashes: check(FileAccess.get_sha256(path)==input_hashes[path],"test preserves layout input bytes: "+str(path))
	_finish(0 if _healthy() else 1)

func _build_floor_fixtures() -> bool:
	phase="declared historical fixture"
	check(input_hashes[FloorMigration.LEGACY_PATH]==FloorMigration.LEGACY_FILE_SHA,"frozen old floor has its reviewed raw hash")
	check(input_hashes[Cabinet.PATH]==FloorMigration.TARGET_FILE_SHA,"production layout is the reviewed five-piece floor before integration test")
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(FloorMigration.LEGACY_PATH))
	if not parsed is Dictionary:
		check(false,"frozen legacy JSON loads")
		return false
	legacy_layout=parsed
	var director=Director.new()
	var loaded: Dictionary=director.load_definitions(Director.DEFAULT_PATH,ActionData.OLD_EXTENSIONS)
	check(loaded.ok,"real previous seven-action definitions load")
	if not loaded.ok: return false
	history_fixture=director.default_state()
	for row in ActionData.OLD_EVENTS:
		var applied: Dictionary=director.apply_event(history_fixture,{"id":"floor-history:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]},
			{"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		if not applied.get("changed",false):
			check(false,"predecessor fixture is a legal Director replay",applied)
			return false
		history_fixture=applied.state
	check(history_fixture.completed.size()==27,"history fixture contains the existing27 goals, no new distribution completion")
	for method in ["manual","service_lock"]:
		var old=Cabinet.new()
		var configured: Dictionary=old.configure(legacy_layout,{},false)
		check(configured.ok,"actual old Cabinet configures: "+method,configured)
		if not configured.ok:
			old.free()
			return false
		var mechanism: Dictionary=old.snapshot()
		old.free()
		mechanism.serial=22
		mechanism.axis.position_m=1.2 if method=="manual" else 0.0
		mechanism.axis.last_serial={"1":3,"2":-1}
		mechanism.door_fraction=0.0 if method=="manual" else 0.75
		var tracker=Progress.new()
		check(tracker.configure(legacy_layout).ok,"old Progress configures actual frozen geometry")
		# Trusted successful observation is declared, not claimed as a ray run here.
		var sample: Dictionary={"ok":true,"code":"back_observed","mechanism_serial":22,"method":method,
			"observer":[18.0,5.75,-10.6] if method=="manual" else [17.8,2.7,-7.85],
			"cover_position_m":mechanism.axis.position_m,"door_fraction":mechanism.door_fraction,
			"electric_latched":false,"panel_hits":[5,5],"center_hits":[true,true]}
		var observation: Dictionary=tracker.prepare_observation(sample,mechanism)
		check(observation.ok,"real legacy Progress accepts declared historical proof: "+method,observation)
		if not observation.ok: return false
		mechanism.serial=29
		mechanism.axis.position_m=0.35
		mechanism.axis.velocity_mps=-0.25
		mechanism.door_fraction=1.0 if method=="service_lock" else 0.45
		mechanism.electric_latched=method=="service_lock"
		var submission: Dictionary=tracker.prepare_retry(observation,mechanism)
		check(submission.ok,"saved fixture pairs first proof with a later moving mechanism: "+method,submission)
		if not submission.ok: return false
		fixture_envelopes[method]=submission.envelope.duplicate(true)
	return _healthy()

func _fixture_world(envelope: Dictionary,region: String) -> Dictionary:
	return {"region_id":region,"environment":{"I2_distribution":envelope.duplicate(true)},
		"actions":{"opening":history_fixture.duplicate(true)},"flags":history_fixture.flags.duplicate(true),
		"completed_objectives":history_fixture.completed.duplicate(),"entities":{},"choices":{}}

func _expected_envelope(old: Dictionary) -> Dictionary:
	var expected: Dictionary=old.duplicate(true)
	expected.mechanism.layout_sha256=FloorMigration.TARGET_STATE_SHA
	# Existing host restore semantics, not a relaxation or a new migration loss.
	expected.mechanism.axis.velocity_mps=0.0
	expected.mechanism.axis.last_serial={}
	return expected

func _prepare_matrix_and_rejection() -> void:
	phase="host prepare and strict client boundaries"
	var adapter=DistributionAdapter.new()
	for method in fixture_envelopes:
		for region in ["I1","F1","I2"]:
			var world_data: Dictionary=_fixture_world(fixture_envelopes[method],region)
			var before: Dictionary=world_data.duplicate(true)
			var prepared: Dictionary=adapter.prepare(world_data,region,true,[Progress.DISCOVERY])
			check(prepared.ok and prepared.get("migrated",false),method+": legacy host migration succeeds while entering "+region,prepared.get("error"))
			if not prepared.ok: return
			check(_same(prepared.state,_expected_envelope(fixture_envelopes[method])) and _same(world_data,before),"candidate retains full old history and only known restore changes")
			check((region=="I2")==is_instance_valid(prepared.get("module")),"only visible I2 constructs a physical cabinet")
			var current_world: Dictionary=world_data.duplicate(true)
			current_world.environment.I2_distribution=prepared.state.duplicate(true)
			var repeated: Dictionary=adapter.prepare(current_world,region,true,[Progress.DISCOVERY])
			check(repeated.ok and not repeated.get("migrated",true) and _same(repeated.get("state"),prepared.state),"already-migrated prepare is idempotent without history regression")
			adapter.discard(repeated)
			adapter.discard(prepared)
	for kind in ["unknown_digest","bad_history","bad_axis"]:
		var world_data: Dictionary=_fixture_world(fixture_envelopes.manual,"I2")
		match kind:
			"unknown_digest": world_data.environment.I2_distribution.mechanism.layout_sha256="0".repeat(64)
			"bad_history": world_data.environment.I2_distribution.history.evidence.mechanism_serial=30
			"bad_axis": world_data.environment.I2_distribution.mechanism.axis.velocity_mps=3.0
		var before: Dictionary=world_data.duplicate(true)
		var rejected: Dictionary=adapter.prepare(world_data,"I2",true,[Progress.DISCOVERY])
		check(not rejected.ok and _same(world_data,before) and not is_instance_valid(rejected.get("module")),"host cannot migrate or reset invalid saved state: "+kind,rejected.get("error"))
		adapter.discard(rejected)
	var client: Dictionary=adapter.prepare(_fixture_world(fixture_envelopes.manual,"I2"),"I2",false,[Progress.DISCOVERY])
	check(not client.ok,"client prepare cannot migrate an old host layout")
	adapter.discard(client)

func _fresh_store(label: String):
	var store=Store.new(base.path_join(label))
	check(store.load_profile().ok,"fresh isolated Store opens: "+label)
	return store

func _seed_old(store,method: String,region: String,id: String) -> bool:
	var world_data: Dictionary=_fixture_world(fixture_envelopes[method],region)
	var changes: Dictionary={}
	for key in world_data: changes["world."+str(key)]=world_data[key]
	var discovery_list: Array=history_fixture.discoveries.duplicate()
	if Progress.DISCOVERY not in discovery_list: discovery_list.append(Progress.DISCOVERY)
	var saved: Dictionary=store.commit({"id":id,"set":changes,
		"append":{"personal.discoveries":discovery_list,"personal.collections":["qa:floor-existing-collection"]}})
	check(saved.ok,"explicit old-world fixture is saved without a distribution objective: "+id,saved)
	return saved.ok

func _published_hashes(store) -> Dictionary:
	var result: Dictionary={}
	var directory:=DirAccess.open(store.root_path)
	if directory==null: return result
	for filename in directory.get_files():
		if filename.ends_with(".json"): result[filename]=FileAccess.get_sha256(store.root_path.path_join(filename))
	return result

func _assert_original_disk(store,before: Dictionary,hashes: Dictionary,label: String) -> void:
	var disk=Store.new(store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),before),label+": independent Store reread retains the last published generation")
	check(_published_hashes(store)==hashes,label+": original published JSON bytes and file set remain unchanged; unpublished tmp is not treated as a save")

func _preserves_personal(before: Dictionary,after: Dictionary,label: String) -> void:
	check(_same(after.personal,before.personal) and _same(after.ledger.guest_outbox,before.ledger.guest_outbox) and _same(after.ledger.guest_received,before.ledger.guest_received),label+": personal records and both receipt ledgers are unchanged")
	check(_same(after.world.actions,before.world.actions) and _same(after.world.completed_objectives,before.world.completed_objectives) and _same(after.world.flags,before.world.flags),label+": no objective/flag/reward is invented by a floor migration")

func _store_branch_cas() -> void:
	phase="real Store target CAS and atomic branch patch"
	var store=_fresh_store("cas")
	var guest=_fresh_store("receipt-owner")
	var guest_id: String=str(guest.snapshot().profile_id)
	if not _seed_old(store,"manual","I1","cas-seed"): return
	check(store.queue_guest_receipt(guest_id,RECEIPT,{"discoveries":[RECEIPT]}).ok,"existing guest receipt sentinel is persisted before migration")
	check(store.fork_branch("old-target","Old floor target",false).ok,"real old target branch created")
	var adapter=DistributionAdapter.new()
	var prepared: Dictionary=adapter.prepare(store.snapshot().branches["old-target"].world,"I1",true,store.snapshot().personal.discoveries)
	check(prepared.ok and prepared.get("migrated",false),"real target preparation returns a migration patch")
	if not prepared.ok: return
	var patch: Dictionary={DistributionAdapter.STATE_PATH:prepared.state.duplicate(true)}
	adapter.discard(prepared)
	var target_hash: String=store.branch_world_hash("old-target")
	var disk=Store.new(store.root_path)
	check(disk.load_profile().ok and disk.branch_world_hash("old-target")==target_hash,"target CAS hash survives JSON disk reload")
	check(store.switch_branch("old-target").ok and store.commit({"id":"target-cas-edit","set":{"world.choices.floor_race":true}}).ok and store.switch_branch("main").ok,"declared intervening target edit occurs through real Store APIs")
	var before: Dictionary=store.snapshot()
	check(not store.switch_branch("old-target",patch,target_hash).ok and _same(store.snapshot(),before),"stale prepared target cannot switch or apply migration")
	target_hash=store.branch_world_hash("old-target")
	var hashes: Dictionary=_published_hashes(store)
	for point in ["before_write","after_write","before_publish"]:
		store.failure_point=point
		check(not store.switch_branch("old-target",patch,target_hash).ok and _same(store.snapshot(),before),point+": failed switch and floor patch retain all in-memory state")
		_assert_original_disk(store,before,hashes,point)
		store.failure_point=""
	var result: Dictionary=store.switch_branch("old-target",patch,target_hash)
	var after: Dictionary=store.snapshot()
	check(result.ok and int(after.generation)==int(before.generation)+1 and int(after.world_revision)==int(before.world_revision)+1,"successful branch+floor patch publishes one generation/revision")
	check(_same(after.world.environment.I2_distribution,patch[DistributionAdapter.STATE_PATH]) and _same(after.world,after.branches["old-target"].world),"active and target branch worlds contain the same migrated envelope")
	check(_same(after.personal,before.personal) and _same(after.ledger,before.ledger) and _same(after.branches.main,before.branches.main),"target patch does not clone personal assets, receipt ledger or alter inactive main")
	disk=Store.new(store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),after),"successful branch migration fully survives independent reread")
	var pending: Array=store.pending_guest_receipts(guest_id)
	check(pending.size()==1,"migration leaves exactly the original queued receipt")
	if pending.size()==1:
		check(guest.apply_guest_receipt(pending[0]).ok,"original receipt remains claimable")
		var received: Dictionary=guest.snapshot()
		var duplicate: Dictionary=guest.apply_guest_receipt(pending[0])
		check(duplicate.ok and duplicate.duplicate and _same(guest.snapshot(),received) and received.personal.discoveries.count(RECEIPT)==1,"repeated receipt remains idempotent after floor migration")

func _release_main() -> void:
	if not is_instance_valid(session): return
	if _has_property("active"): session.active=false
	if _has_property("owns_world"): session.owns_world=false
	var transport: Node=session.get_node_or_null("Network")
	if is_instance_valid(transport) and transport.has_method("close"): transport.call("close")
	session.free()
	session=null

func _attach_main(store) -> bool:
	_release_main()
	session=MAIN.instantiate()
	if not _main_usable():
		check(false,"MAIN must retain a usable Session script")
		return false
	root.add_child(session)
	if not _disable_callbacks(): return false
	check(session.profile_ready,"real MAIN bootstraps only the explicitly named fresh QA profile")
	if not session.profile_ready: return false
	# Each case replaces only its own Store with an isolated prewritten QA save;
	# production start_flight still performs the complete load/prepare/commit path.
	session.store=store
	session.world_cache=store.snapshot()
	return _healthy()

func _startup_migration(region: String,method: String,mode: String="solo") -> void:
	phase="real MAIN startup "+region+" "+method+" "+mode
	var store=_fresh_store("startup-"+region)
	if not _seed_old(store,method,region,"startup-old-"+region): return
	check(store.queue_guest_receipt("floor-startup-guest",RECEIPT,{"discoveries":[RECEIPT]}).ok,"startup old save includes existing guest receipt")
	if not _attach_main(store): return
	var before: Dictionary=store.snapshot()
	var hashes: Dictionary=_published_hashes(store)
	for point in ["before_write","after_write","before_publish"]:
		store.failure_point=point
		var started: bool=session.start_flight(mode)
		check(not started and not session.active and not session.owns_world and session.network.mode=="solo" and session.network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer and session.interface.menu.visible and not session.distribution.ready and not session.clinic.ready and not is_instance_valid(session.world),point+": failed startup cannot adopt visible/background candidates")
		check(_same(store.snapshot(),before),point+": failed startup cannot replace old envelope/history in memory")
		_assert_original_disk(store,before,hashes,"startup "+point)
		store.failure_point=""
		await process_frame
		if not _healthy(): return
	check(session.start_flight(mode),"startup retry performs migration and adopts the real world")
	if not _disable_callbacks() or not session.active: return
	var after: Dictionary=store.snapshot()
	check(session.region_id==region and session.distribution.ready,"startup restores cabinet lifecycle in the saved region")
	check(_same(after.world.environment.I2_distribution,_expected_envelope(fixture_envelopes[method])) and _same(after.world,after.branches.main.world),"startup publishes migrated history into active and branch copy before adoption")
	check(int(after.generation)==int(before.generation)+1,"all failed startups plus success publish only one new generation")
	_preserves_personal(before,after,"startup "+region)
	check(_same(session.distribution.progress.snapshot(),fixture_envelopes[method].history),"live tracker restores the original first observation")
	if region=="I2":
		check(session.distribution.module==session.world.distribution,"real visible world owns the adopted cabinet")
		_check_pose("migrated startup")
	else:
		check(not is_instance_valid(session.distribution.module),"off-region migration creates no running background cabinet")
	var disk=Store.new(store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),after),"successful startup survives independent disk reload")
	if mode=="host":
		check(session.network.mode=="host","successful retry owns the actual host transport")
		session.network.start_solo()
		check(session.network.mode=="solo","test closes its successful host before solo branch checks")
	await physics_frame

func _startup_rejections() -> void:
	phase="real MAIN invalid saved-state rejection"
	for kind in ["unknown_digest","bad_history"]:
		var store=_fresh_store("invalid-"+kind)
		if not _seed_old(store,"manual","I2","invalid-base-"+kind): return
		var bad: Dictionary=fixture_envelopes.manual.duplicate(true)
		if kind=="unknown_digest": bad.mechanism.layout_sha256="0".repeat(64)
		else: bad.history.evidence.mechanism_serial=30
		check(store.commit({"id":"declared-corrupt-fixture-"+kind,"set":{DistributionAdapter.STATE_PATH:bad}}).ok,"generic Store holds explicit domain-invalid fixture: "+kind)
		if not _attach_main(store): return
		var before: Dictionary=store.snapshot()
		var hashes: Dictionary=_published_hashes(store)
		check(not session.start_flight("solo") and not session.active and not session.distribution.ready and not is_instance_valid(session.world),"actual startup rejects rather than resets invalid old state: "+kind)
		check(_same(store.snapshot(),before),"invalid startup does not overwrite corrupt evidence with defaults")
		_assert_original_disk(store,before,hashes,"invalid startup "+kind)
		await process_frame
		if not _healthy(): return

func _environment_save_idempotency() -> void:
	phase="real Session environment persistence boundary"
	check(session._save_environment(),"settle current live state through real Session")
	var before: Dictionary=session.store.snapshot()
	check(session._save_environment() and session._save_environment(),"unchanged live state can be saved repeatedly")
	check(_same(session.store.snapshot(),before),"no simulation step means no new generation or commit")
	# Explicit live scalar mutation tests dirty detection, not an ability or playthrough.
	var relay: Dictionary=session.entities["I2:distribution_relay"]
	relay.charge=float(relay.charge)+0.125
	check(session._save_environment(),"changed fractional live value is persisted")
	var changed: Dictionary=session.store.snapshot()
	check(int(changed.generation)==int(before.generation)+1 and changed.world.entities.I2["I2:distribution_relay"].charge==relay.charge,"real fractional change writes exactly once")
	check(session._save_environment() and _same(session.store.snapshot(),changed),"unchanged fractional readback causes no second generation")

func _real_branch_switch() -> void:
	phase="real UI branch migration failure and retry"
	check(session.active and session.region_id=="I2" and session._save_environment(),"current real I2 world is saved before creating inactive legacy target")
	if not _healthy(): return
	var store=session.store
	check(store.fork_branch("legacy-floor","Legacy cabinet floor",false).ok and store.switch_branch("legacy-floor").ok,"explicit inactive-target fixture starts via real Store branch APIs")
	if not _seed_old(store,"manual","I1","legacy-floor-seed"): return
	check(store.switch_branch("main").ok,"fixture returns Store to the still-running main world")
	session.world_cache=store.snapshot()
	session.consensus.configure([1],int(session.world_cache.world_revision))
	check(session._save_environment(),"settle actual current environment before isolating branch write failures")
	if not _healthy(): return
	var before: Dictionary=store.snapshot()
	var old_world=session.world
	var old_module=session.distribution.module
	var hashes: Dictionary=_published_hashes(store)
	for point in ["before_write","after_write","before_publish"]:
		store.failure_point=point
		session._ui_action("branch",{"id":"legacy-floor"})
		check(session.active and session.world==old_world and session.distribution.module==old_module and session.region_id=="I2",point+": rejected branch leaves old live cabinet and world adopted")
		check(_same(store.snapshot(),before),point+": real branch action does not publish target migration or switch")
		_assert_original_disk(store,before,hashes,"real branch "+point)
		store.failure_point=""
		await process_frame
		if not _healthy(): return
	session._ui_action("branch",{"id":"legacy-floor"})
	if not _disable_callbacks(): return
	var after: Dictionary=store.snapshot()
	check(session.active and session.region_id=="I1" and after.world.branch_id=="legacy-floor" and session.world!=old_world,"retry atomically switches to prepared I1 target")
	check(_same(after.world.environment.I2_distribution,_expected_envelope(fixture_envelopes.manual)) and _same(after.world,after.branches["legacy-floor"].world),"real branch hook persists target migration into both world copies")
	check(int(after.generation)==int(before.generation)+1 and _same(after.branches.main,before.branches.main),"successful UI switch writes once and preserves the previous branch",
		{"before_generation":before.generation,"after_generation":after.generation,"old_branch_equal":_same(after.branches.main,before.branches.main),
		"old_world_before":before.branches.main.world,"old_world_after":after.branches.main.world})
	_preserves_personal(before,after,"real branch switch")
	check(_same(session.distribution.progress.snapshot(),fixture_envelopes.manual.history) and not is_instance_valid(session.distribution.module),"branch restores first manual history while retaining off-region stopped state")
	var disk=Store.new(store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),after),"real branch target upgrade survives independent reload")
	await physics_frame

func _finish(code: int) -> void:
	if done: return
	done=true
	_release_main()
	if code==0 and not error_logger.errors.is_empty(): code=1
	print("DISTRIBUTION_FLOOR_SESSION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("DISTRIBUTION_FLOOR_SESSION_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"profile":profile,"input_hashes":input_hashes,
		"limits":["Old27 goals and successful host observation samples are explicit legal saved-state fixtures, not a new playthrough or new ray proof.","Production adapter, MAIN startup/UI branch, actual Store CAS/failure/reload and immediate adopted cabinet poses are exercised.","Receipt sentinel checks duplication behavior only; no new action, discovery award, ENet/ACK transport, mixed-build handshake, GPU, performance or human duration is verified."]}))
	OS.remove_logger(error_logger)
	quit(code)
