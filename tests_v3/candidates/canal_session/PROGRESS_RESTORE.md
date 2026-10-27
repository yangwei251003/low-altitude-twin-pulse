# Original Canal progress persistence — current continuation

2026-10-20 continuation: the implementation now includes Bootstrap, waiting,
moving transport, pre-receipt commit, actual committed work/original beneficiary
departure, claim and exact native pause boundaries. The first-batch notes below
are retained as history; their old pending list is superseded by this status.

- Moving transport plus same-adopt/first167ms re-save:
  `progress_20261020_213229_56619d`,79/0/0,13.766s,223 inputs unchanged.
- Real Bootstrap initial contacts through waiting:
  `startup_20261020_214501_998667`,161/0/0,34.781s,226 inputs unchanged.
- Pre-receipt commit, work receipt, lift and three departure legs roundtripped:
  `departure_20261020_220204_b80a06`,179 checks/1 failure/0 engine errors.
  The real carrier then could not descend from its high same-anchor work hold;
  original full swept pickup_prepare now precedes local alignment.
- Exact dynamic pause/resume and reload-only native hold:
  `boundary_20261020_224904_e5799d`,10/0/0,.875s. Normal pause never changes
  enabled or callbacks; fatal committed-state reload-only hold uses the original
  Flight.enabled early return to suppress an already queued callback.
- `local_cooling_20261020_224906_9bca43`,65 checks/1 failure/0 engine errors,
  20.625s. Actual current/historical local proof, SCAN pause/cache, original
  Store failed/success paused save, resume, work heating and fresh zero-credit
  restore passed. The last assertion incorrectly expected the explicit old27
  QA fixture to have no prior discoveries; the test now records and compares
  its Story/discovery baseline. No all-green rerun has been claimed.
- `service_20261020_225113_320296`,76 checks/1 failure/0 engine errors,
  17.609s. Real descent/alignment created the real PinJoint; generic frozen
  clearance then rejected its genuine source-table touch. The correction
  permits ONLY that original source RID after matching pick phase/Rules holder,
  original joint/grip/serial/history, actual current five rays/footprint/gap
  <=.025/upright. It changes no collision mask, pose or current contact credit.
  The pinned unchanged actual Store boundary `actual_commit_pick.json` has SHA
  `bb7fd752f0d135710753c4e7337fa18ed18ec074a278575c1ff8a25e37d2f252`.
  `run_progress_test.py --service-pickup` resumes there without redoing the
  already-covered descent/alignment.
- That continuation passed as `service_20261020_230122_2e6a2e`:
  231/0/0,55.265s,240 inputs unchanged/no leftover process. Actual pick commit,
  departure, loaded travel, approach, freefall, idle and original prepare/Store
  failure/success/adopt/claimed fresh restore all passed. Exact result SHA:
  `95c7e7e1482bbbd6adc977c10152675c118a4f10bf93211be01ffbba41e848a1`.
  Original MAIN Story interaction/atomic reward is tested separately using its
  real `snapshots.phases.transport_idle.source` and claimed reference, never a
  synthesized terminal or a replay of the long scan/route3 path.

All these runs used isolated QA profiles and left no process. Root owns normal
factory/Consensus/Story/Store/network integration. Production enablement,
original Story atomic claim, client replica, dual-machine LAN, current
performance and human full-flow acceptance remain distinct evidence gates.
Headless check counts do not establish comfort, fun or final completion.

## Historical first-batch implementation notes

2026-10-20. New kind: `canal_progress_checkpoint_v1`. This is a site envelope
under the original Session/Store path `world.environment.I2_canal`; it is not a
Repository, second reward ledger, automatic production enablement, or LAN state.

First batch is deliberately bounded: normal ordered Executor transport while
the Workbench is still waiting. It captures the actual moving carrier/cargo
poses and momenta, physical filters and material, real optional PinJoint local
anchors/parameters/grip, custody ownership/replay counters, original pending
Rules action/thermal clock, Executor route phase/index/controller/serial/receipt
count, cooling equipment state and workbench power/unserved beneficiary.

`capture_active_checkpoint()` dispatches old unordered WAIT and stationary SCAN
as before. Other ordered phases try the new progress capture. During transport
the existing `prepare_scan_capture()` returns ready/not-required. Pure capture
does not initiate settling, freeze bodies, move them, issue actions or save.

Loading builds a new frozen subtree in the caller's fresh actual World3D.
The new body's initial pose is assigned only during construction. Actual
PhysicsServer poses and the reconstructed original joint must read back in a
later real physics frame, with current physical overlap checks, before the
same-frame `adopt_saved()`. All original Rules state and route progress remain
unchanged throughout preparation. Adoption restores saved momentum once; the
next normal Assembly tick owns movement, contact updates and the Rules clock.
There is no 350 ms interval where bodies move while the logical clock is held.

Saved contact/arrival stability remains source history. Current-space Custody,
Pilot and Dock stability credit starts at zero. Executor permits bounded
revalidation of already-owned docked cargo while continuing the original safe
transport controller; original pickup/place still need their real current
contact gates. Revalidation times out rather than inventing support.

Run only after the Root has serialized Godot/Blender work:

```powershell
python tests_v3/candidates/canal_session/run_progress_test.py
```

The probe uses the explicitly recorded historical WAIT fixture, then starts a
new real Rules/LOS-authorized transport. It captures actual carrier speed above
0.8 m/s, exercises failure/success through the existing MAIN Store, reopens its
JSON generation, reconstructs the same phase/route/momentum/joint/ledger, and
observes further real movement. Invalid phase, motion, pending identity, joint,
credit and missing body samples are rejected. Each run preserves its literal
source closure, hashes, engine log and result in a unique evidence folder.
Results must come from that actual run, not this candidate description.

First actual run `progress_20261020_212102_b75b2b` reached the original Store
failure/success/JSON roundtrip and new frozen scene (61 checks, one failure,
zero engine errors). It rejected a rotated load's bit-exact matrix comparison
to PhysicsServer. Official Godot 4.7.2
[Jolt conversion](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/jolt_physics/misc/jolt_type_conversions.h)
stores normalized float quaternions and reconstructs a Basis on readback.
The new check retains exact position, records both full native transforms and
maximum component error, and bounds only matrix representation error to 1e-6.
Node-vs-saved pose, the real joint, momentum and all kinematic scan checks remain
unchanged. Whether this correction passes is determined by the next real run.

Still pending after first batch: initial Bootstrap until WAIT, immediate
re-save during fresh contact revalidation, tool commit and completed beneficiary
departure/terminal hold, claimed service state, full-chain short tests and
production lifecycle/LAN integration. Until those are implemented and tested,
this first batch does not remove the normal-game enablement blocker.
