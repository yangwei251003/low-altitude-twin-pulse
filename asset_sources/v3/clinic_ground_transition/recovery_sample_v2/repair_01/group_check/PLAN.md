# Matched-source check — static, no engine run

The one wrong component hit belongs to the **old combined HighSolids ray reconstruction**, not the new isolated source. At old pixel(860,849), solid_05 hit solid_00/triangle74. That prior failure and its original PASS-label correction remain frozen in `prepare_20261020_003900_014313/`. It must not be silently reclassified as a successful bake prerequisite.

This check reads that run's actual saved `prepared_repair.blend` (SHA `a96ce94687abd7288c4eec0b58a1c7a9997d7e3f907dc122e3c22643f5b7dd18`). It does **not** repeat the53.813s construction or modify/re-save the scene.

- Verify all11 actual matching high/low groups against the recorded original triangle IDs: exact corner positions/winding and low BakeUV, copied split normals within the existing0.1° numerical-copy guard, identical transforms. Verify the actual saved cage topology and its original35mm vertex-normal offsets; no new cage is created.
- At each of the1,965 original bad pixels, reconstruct the point from its target group's actual BakeUV and interpolate its **saved cage coordinates**. Cast only into that group's saved high mesh. Record high identity/original triangle ID, hit, actual geometric normal and interpolated corner normal. A miss or either reversed normal is still a failure. No threshold is relaxed and no pixel is removed.
- Report old combined-source and new matching-source results for the known cross-component pixel separately. This tests the intended isolation; it does not claim to instrument Cycles' historical bake hits or prove the final normal map fixed.
- Hash all read inputs before and after. No images need loading, no source objects are generated, no UV/materials changed, no bake/render/export. Full logs and results stay in a unique child output directory.

Estimated **15–30 seconds**, CPU2, **private hard60s**. Static Python AST checks only so far. Run only after root grants a serial window:

```powershell
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_01/group_check/run_group_check.py
```

Even if this passes, bake/render do not start automatically. Root decides the next window and the prior wrong-hit evidence remains part of the record.
