# Matched-group preflight — actual result

This run reads the already saved prepared_repair.blend and its actual 11 high/low/cage groups. It creates no objects, saves no source, and performs no bake or render.

- Blender PID 6996; natural exit 0; launcher elapsed 5.469 seconds; CPU 2; hard limit 60 seconds; no log ERROR or residual engine process reported at release.
- All 11 copied groups preserve original triangle positions, winding and transforms; all low BakeUV corners match exactly. Actual totals: high 146,026 / low 9,578 triangles.
- Split-normal numerical differences: high maximum 0.04214665°, low maximum 0.03728940°. Saved cage offsets differ from original vertex-normal offsets by at most 3.30398e-8 m.
- All 1,965 previously identified bad normal pixels hit their matching high group: 1,550 top, 396 side, 19 solid. No misses, incorrect group identities or reversed geometric/interpolated corner normals. Maximum geometric angle to low normal 21.38045°; maximum interpolated corner angle 6.69627°.
- Former cross-component pixel (860, 849) now hits RepairSource_solid_05, original HighSolids triangle 473. Geometric angle 11.350743°; interpolated corner angle 0.00007887°. The earlier full-shell ray hit triangle 74 from another solid at 81.917897°; that failed record remains unchanged.
- Input hashes remain unchanged. Prepared blend SHA256: a96ce94687abd7288c4eec0b58a1c7a9997d7e3f907dc122e3c22643f5b7dd18.

This result validates the saved matched projection copies and the specified pixel preflight. It does not reconstruct Cycles' old internal bake rays, prove every future bake pixel, or demonstrate a visual repair. The next actual normal bake and same-camera image still require their own authorized window and review. Original failure records are retained.
