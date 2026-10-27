# Original Story / Store bridge

Root alone owns normal Session, Story, network and Store integration. The
adapter never writes a Store, emits rewards or heals the player.

`prepare_story_service(peer_id)` uses the actual host-owned peer body, owner
registry, enabled/unfrozen state, same physics space, distance <=4 m to the
physical Workbench PowerContact and actual Session LOS. Ordinary adapter ticks
observe the existing completed-safe checkpoint continuously for 350000 us.
Repeated same-frame queries cannot add observation credit. A genuine completed
work receipt and terminal/empty-carrier/docked-cargo gates remain mandatory.

For a new claim, the result contains `envelope`, `prepared_rules`, `source_rules`,
`expected_generation`, lineage/branch, current physics frame and actor revision.
It changes no public Rules counter. Root places `envelope` at
`world.environment.I2_canal` in the SAME `Story._submit` transaction as
`world.actions.opening`, objective/flag/discovery changes and original guest
reward outbox. It must replace the ordinary pre-consumption Canal envelope in
that transaction. No await or physics tick may occur between prepare, original
Store commit and `adopt_story_service(token)`.

After successful Store commit, adopt rechecks the actual Store readback using
its original `matches_persisted_value`, unchanged authority frame/player/Rules,
then calls original Rules.adopt_service and Executor.wait_for_next_beneficiary.
Calling adopt before the original Store commit is rejected. Commit failure
leaves the original credit and Story unchanged. A post-commit live-state failure
stops owned physics and reports `committed_claim_reload_required`; reload the
committed envelope rather than rolling it back or writing an older checkpoint.

Already consumed, persisted service serial1 returns `duplicate=true` and
`healed_hp=0`; adoption is an idempotent no-op. Root owns any intended player
repair and its persistence. This interface does not claim to validate healing.

`story_service_status()` is display/query-only. `exchange_fact()` derives
`low_route`/`high_route`/`mixed_route` only from original ten completed transport
receipts plus current uniquely docked, actually supported 350000-us custody.
Current normal controls support only low-route transport. Legacy strict
SCAN/Progress saves retain count rather than raw runtime report arrays; their
sealed low-only Executor, disabled manual/buffer roles, original work serial11
and current real custody are required for the low-route fallback. Unsupported
high/manual play is not advertised by changing a policy flag.

Bind these to existing authored facts `I2:canal_exchange_verified` and
`I2:canal_service_verified` (`repaired`). Adapter.ready means usable site, not
claim readiness. The service navigation point is the actual PowerContact
(`I2:canal_workbench_power`, (5.1,1.05,5.4)); a distant dispatch marker must not
stand in for its 4 m/LOS access gate. No guest runs this ledger or its dynamics.

Root serial physical continuation entry:
`python tests_v3/candidates/canal_session/run_progress_test.py --service-pickup`.
It resumes the pinned real pre-receipt pickup after the original descent/
alignment, covers remaining loaded-flight/approach/freefall/cleanup states via
the original MAIN Store and fresh Worlds, then service prepare/failure/success/
adopt and claimed restore/no-op. Actual `service_20261020_230122_2e6a2e` passed
231/0/0 in55.265s,240 inputs unchanged/no process leak. Original Story rewards,
player healing and LAN remain separate Root checks. The new original-Story
test/runner accepts that exact successful result and its SHA as declared input;
it never manufactures a Safe/claimed endpoint or replays scan/route3.
# Pause boundary and local preparation additions

`request_pause()` accepts an intent, returning `{ok, pending, ready, code}`. Root
leaves its Consensus proposal and `simulation_paused=false` while pending. After
one ordinary `canal.advance()` per physics frame, `pause_request_status().ready`
means all owned bodies are frozen at an exact native/Node sync boundary AND a
valid pre-stop persistent checkpoint is cached. SCAN uses its existing settling
handshake first. Failed capture never freezes the site. Cancellation releases
only this request's barrier; `set_paused(false)` resumes native momentum once.
Process/UI callers must not call synchronous `set_paused(true)` to freeze a
moving body. Root skips owned bodies in its generic freeze/resume loop.

`pause_boundary_snapshot()` supplies the actual application `physics_frame`,
`bodies` keyed by instance ID, `carrier_clock`, and pre-stop Rules/Custody
`modules`. Body fields match the lifecycle test's physical diagnostics and use
native pose/linear/angular velocity; use this as the baseline rather than the
earlier UI request. Paused capture and original Store save do not require resume.
The independent original-Flight/cargo/PinJoint probe passed normal exact pause/
resume plus reload-only native hold as10/0/0 in `.875s`:
`boundary_20261020_224904_e5799d`. Fatal hold also suppresses the already queued
original Flight callback through its existing enabled early return; it neither
replaces callbacks nor changes normal resumable pause. The full MAIN lifecycle
remains a separate gate.

`exchange_fact()` additionally returns `local_cooling` for a distinct proof:

- Current preparation: original hot cassette1 still on WORK, native closed
  chain with no transport receipts, actual unique docked support for350000us,
  current temperature<=45C, and original thermal ledger effective ability
  removal sufficient to account for its reduction from the initial50kJ.
- Historical preparation: original first-work serial1/cassette1, validated three
  measurements and1.4m scan, original25kJ work heat and at least25kJ effective
  ability removal, plus the same real cassette's CURRENT unique holder/support
  for350000us. This means it was prepared locally; it may now be hot or at a
  southern berth. It works when the original preparation preceded Brief.

No Story state, rewards, claim ledger or second save repository is created.
Ten-receipt route classification retains its original strict checks.
`run_progress_test.py --local-cooling` tests the pinned actual96/0 pre-Brief
thermal scan, paused SCAN save failure/success, subsequent real work heating,
and original Store/fresh-World support revalidation. Run224906_9bca43 passed
those functional gates (65 checks/1 old-fixture assertion failure/0 engine
errors); its last assertion incorrectly expected no prior old27 discoveries.
The test now compares the recorded seeded Story/discovery baseline. It has not
been relabeled as an all-green rerun; see PROGRESS_RESTORE.md for exact scope.

