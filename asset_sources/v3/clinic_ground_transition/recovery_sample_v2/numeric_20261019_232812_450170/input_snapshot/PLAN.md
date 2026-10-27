# Recovery sample V2 — discriminate the black-rim cause before repair

**Static preparation only. No Blender/Godot, render, bake or geometry edit has run in V2.** Route `5e455d78-37b2-423b-b660-0cc3185eae49` continues. The frozen 0.9×0.9m sample is the only subject; this is not P14 or a game placement. Old recovery_sample/P13/recovery_study and their original maps remain read-only.

## What is known, and what is not

The frozen high source has readable real medium-scale relief. Its baked low image adds black rim patches that the high image does not have. Both images have stretched lines on the soil block's vertical closure walls. The raw Normal map has abnormal orientation patches near several UV edges. These observations do not yet uniquely distinguish wrong cage hits, tangent changes during merge, or excessive AO. The previous zero-magenta-centroid check was insufficient and will not be treated as a clean-bake certificate.

## Two diagnostic stages

1. **Numeric, estimated 10–25s / private hard 60s.** Reopen the exact old baked preview. Verify all frozen input hashes, real image pixels and paths. Compare LowGround to the identical region in LowFull by triangle position+UV keys; record split-normal/tangent/sign differences. Sample all ground triangle centroids plus seven barycentric positions on true outer-boundary triangles. Record real bilinear Normal/ORM values, decoded tangent normal, and the reconstructed original 35mm cage ray against actual high triangles. Record hit surface class, nearest class/distance and ray deviation. This is an independent reconstruction of the authored cage, **not an instrumented Cycles internal-hit trace**; exact corners may be ambiguous. Also count side faces whose horizontal source UV has zero area. No save, render, bake or parameter change.
2. **Four fixed-camera views, estimated 150–210s / private hard 300s.** Reopen the same low baked preview. Keep its original 1280×1100 camera, lights, exposure, 24 CPU samples, mesh/UV, roughness, metalness and all image bytes. Change only Normal connection and BaseColor AO multiplication:

| File | Normal | AO multiplication |
| --- | --- | --- |
| 01_N1_A1_baseline.png | on | on |
| 02_N0_A1.png | off | on |
| 03_N1_A0.png | on | off |
| 04_N0_A0.png | off | off |

Each completed image is checkpointed with SHA. Geometry/UV fingerprints and scene settings are verified before each render. Turning Normal or AO off is a diagnostic, **not an approved final material fix**.

```powershell
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/run_diagnostic.py numeric
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/run_diagnostic.py switches
```

These are separate explicit commands, not an automatic multi-run loop. Launch only after root grants the serial engine window. The runner inventories existing engines and refuses to launch alongside them, records the new PID, preserves its exact input snapshot and full logs, and only terminates its own tree at the stage limit. Any ERROR, missing image or real unexpected failure stops the stage. No repair/bake entrypoint is auto-triggered.

## Decision logic for one necessary later repair

- If black patches track Normal on/off, investigate the sampled normal orientation and merge tangent parity first. A mismatch between LowGround and LowFull calls for baking with the final tangent topology. If tangents agree but the reconstructed ray reaches an adjacent side/back surface, fix the affected projection region/cage direction; do not randomly increase distance.
- If patches track AO on/off, isolate the same actual mapped region's AO/hit provenance; retain real contact occlusion rather than globally deleting AO. If both contribute, record both rather than declaring a single root cause.
- If all four views retain the fault, inspect actual material base/UV/geometry. Do not modify height strength or scan UV to conceal a bake issue.
- **Independent side mapping defect:** `side_uv_proposal.py` is prepared but unused. Only vertical closure faces will use metre-based X/height or Z/height, preserving 2m Rocky and 2.5m Sandy scale. Top source UV and all top geometry stay unchanged. Back-stretch corner continuity still requires a real review. This does not move the side out of view.

Only after root reviews the four views and actual numeric data will the single minimal repair/bake be implemented and run. The old 9,578-triangle geometry and contact/closure requirements are retained; no loosened geometry gate, original image editing, new resource, software installation, imagegen or GLB.
