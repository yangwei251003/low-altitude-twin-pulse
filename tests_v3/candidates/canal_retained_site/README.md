# Retained I2 physics candidate — 62 checks passed; MAIN integration remains open

Final bounded run: `evidence/20261020_062138_a9aee3`, **62/62**, no engine errors.
Import PID 41812 exited 0 in 10.078 s; probe PID 40584 (engine child 29468) exited
0 in 149.329 s. Total 159.735 s, zero residual processes, all 220 input hashes
unchanged. Root's minimal Executor change reuses the original Pilot source hold
before a new move; DockLift, receipt rules and 0.20 m source gate remain intact.

The recorded serial-4 recovery begins at the same 0.20104548 m XZ error as the
failed diagnostic. Across 103 consecutive physics frames it reaches 0.04028964 m
XZ / 0.05689460 m 3D error and 0.110673 m/s before route travel. Maximum frame
displacement is 5.501 mm; pending identity, two prior receipts and both docked
cargo owners remain unchanged. No fixture displacement or threshold relaxation.

All six presentation-only transitions retain the 657 body identities and spaces;
the loaded PinJoint remains live during both carrying transitions. The original
chain finishes with one real work receipt, the beneficiary departed, six transport
receipts, both cartridges at S0/S1, no pending action and one unspent service
credit. Thermal removal/work addition are each 25 kJ exactly once: Runtime stores
millijoules (`mJ`), so each raw `25000000` is 25,000 J, not MJ or microjoules. The original
Repository safe-point save and independent generation-1 readback pass. All 145
bounded diagnostic events are retained, with zero evictions.

This establishes the retained candidate's normal physical continuation and safe
completion, not MAIN travel, multiplayer, arbitrary mid-flight save or final
performance. Root separately verified main-Viewport presentation with 32 checks
and three real I2/I1/I2 images at `artifacts/v3/region-space-20261020_062053_ae0783`;
that separate result does not add Session/HUD/facility/save integration here.

Final callback P50/P95: background scan 4.379/6.948 ms (120 samples), carrying
4.409/5.531 ms (300), post-work full-rate hover 4.561/5.342 ms (300); visible active
4.562/6.361 ms (5764). Different phases are not an A/B rendering benchmark.
`visible_postwork_hover` also includes the later player return flight and save,
so its 563-sample distribution is **not** a pure-idle comparison. Static allocation
is 950,445,047–1,026,215,721 bytes including imported assets and QA trace storage,
not process RSS or an isolated retained-region delta. No low-frequency airborne
simulation optimization has been claimed or applied.

## Preserved failures and diagnosis

First run: `evidence/20261020_060528_ace234`. Import exited 0 in 10.516 seconds;
the real probe exited 1 in 65.703 seconds (44 checks, two failed checks caused by
one original playable `source_anchor_mismatch` error). Total 76.532 seconds,
zero residual processes, all 220 dependency hashes unchanged. No second run has
been performed against this version.

Both requested active-stage background intervals ran: scan distance advanced from
0.0110 to 0.4510 m over 120 physics ticks, and the carrying aircraft moved 1.895 m
over 300 ticks. All 657 physical body identities/spaces and the bound carrying
PinJoint survived both foreground/background transitions. The original work
receipt produced one job and one unspent credit; that result was not injected.
The second World3D's real rigid body advanced independently.

After returning to foreground, the original Executor rejected a subsequent move
whose live XZ source-anchor distance exceeded its unchanged 0.20 m bound. The last
recorded snapshot is still the earlier WAIT-to-south_0 carrying move; this version
does **not** retain the fatal frame's position/action. Therefore drift, route stage,
and causation by the presentation transition are not established. The remaining
transport completion, post-work hover measurement and safe-point save were not
reached and are not accepted.

Observed host-callback P50/P95: visible active 4.186/4.970 ms (1609 samples),
background scan 4.208/5.184 ms (120), background carrying 3.974/4.757 ms (300).
These are different live workloads, not an A/B speedup claim. Static allocation
was about 0.95–1.02 GB including imported assets, test state and recorded snapshots;
it is not a retained-region memory delta or process RSS.

The diagnostic revision ran as `evidence/20261020_061514_4d76fb`: import 9.813 s,
probe 66.062 s, total 76.188 s; natural exit 1, zero residual processes, 220 inputs
unchanged, 44 checks with the same two failures from one original engine error.
All 27 action/phase events were retained, with zero evictions. At frame 3683 the
original place receipt (serial 3) succeeded with both cartridges really docked
for 350 ms. The next frame requested empty-carrier move serial 4, S0 to WORK;
the source XZ error was 0.20104548 m against 0.20 m, with an empty hold state.
It had already reached 0.21750 m during approach/release. The carrier was healthy,
had no contacts or collisions, its current full-envelope probe was clear, and its
Node/PhysicsServer positions matched. This establishes a post-place source-hold
gap, not lost World3D ownership or a new obstacle. Root owns the Executor repair.

The measured subclass retains at most 256 read-only action/phase events (plus 30-frame
docking samples), counts any evictions, and preserves the fatal callback separately.
It records the pre-callback command/pose, current action and pending identity,
confirmed/source anchor and XZ error, carrier/cargo contacts and velocity, last
receipt, hold state, custody, release preflight and current zero-intent sweep.
Queries run after the original callback, outside its timing measurement; their
cost remains part of overall engine workload. The diagnostic revision's original
player route, wind, Executor, collision/anchor thresholds and rules were unchanged. Existing first-run
source copies, logs and hashes remain untouched.

The subsequent recovery assertions passed in the final batch: serial 4's actual
hold precedes travel, with unchanged pending identity/receipt count/cargo ownership,
continuous per-physics-frame positions and the original Pilot's 0.18 m/0.18 m/s
settling conditions. Initial/final error is recorded; the test neither displaces
an actor nor requires the new wind timing to reproduce >0.20 m.

The only implementation additions are `retained_site.gd` and the measurement-only
subclass `measured_playable.gd`. The existing candidate scene is a script-only root;
the subclass calls its original `_physics_process` once, at the normal engine rate.
The harness does not change MAIN, registry, Store or facility files. Root separately
made the minimal original Executor source-hold fix described above for the final run.

`python tests_v3/candidates/canal_retained_site/run_retained.py` only inventories
inputs. Root must grant an exclusive slot before `--run`. The runner reuses the
existing suspended-start private process-tree guard, optionally imports for at most
20 seconds, and limits the entire engine sequence to 270 seconds. The probe has a
240-second wall timer plus bounded frame loops. `--skip-import` is only for an import
already performed by Root against these exact files. No network or image capture.

The test starts fresh, actually flies and invokes the original key handler/ability
validation to power the workbench, cool the original WORK cassette, and leave one
takeover order. At real `scan_out` motion and again at a real `travel` phase with a
bound carrying PinJoint, it disables only the region viewport's render updates.
It returns to the same scene, records every body's instance/RID/space, and checks the
live carrying joint across the transition. Ordinary joint release during a later
legal place is not mistaken for an identity failure. Original conservation checks,
Rules/water/heat/custody/receipts and one completed unspent credit are retained in
the report. One safe-point save uses the existing Repository in a fresh QA profile;
the test does not replay the already-covered G/F9 service flow.

The original player stays in I2 at an actually flown position under brake input.
A second real World3D contains a moving rigid-body isolation fixture. This is
**not** normal MAIN player travel, a complete I1 concurrent workload, guest state
replication, viewport compositing, or evidence that an offline timer may fabricate
physical receipts. The owner never migrates a live body to another space.

Timing records measure the original host callback, the previous engine-wide physics
monitor, and static allocation/node/active-object counters. The engine-wide monitor
includes the test and both spaces; callback time excludes engine rigid-body solving.
Neither is FPS, GPU, process RSS or final performance acceptance. Post-work vehicles
continue full-rate real hover; only the phase label changes. Per-ray counts are not
claimed because the original controllers expose no such counter.

Unique `evidence/<batch>` stores logs, result, before/after hashes and small source
text; existing model/texture bytes are hashed rather than copied. First failures
remain untouched. Future reruns require a new exclusive engine slot and batch.

Compact raw-byte copies of all three runs are frozen under
`docs/v3/evidence/canal-retained-site/`: 33 files / 4,310,868 bytes, including only
the five directly relevant source versions per batch. Its manifest and verification
record every origin/hash/readback; the remaining original `input_source` closures
stay here for traceability. See `docs/v3/planning/I2_CANAL_RETAINED_RESULT.md` for
the exact two-failure → real repair → 62/62 result and remaining integration limits.
