# One bounded repair — STATIC PREPARED, NOT EXECUTED

Route `5e455d78-37b2-423b-b660-0cc3185eae49`. This is only the existing 0.9×0.9m method sample. It is not P14, a game asset, an exported GLB, or an art pass. Root must grant a serial engine window before any command below runs.

Read-only inputs are the frozen sample and V2 diagnosis. Inspection PID27096 established correct actual BakeUV/Non-Color wiring and 1,550 reversed top-normal pixels inside a pure-top UV island; only 40 are near another island. The previous switches established that AO removal does not fix the rim. The internal historical Cycles hit remains unobserved. Original 67 inputs and 74 diagnostic files, plus the 19-file pixel inspection, are hash checked at every stage.

## Fixed scope

- Retain every actual high/low position and existing loop triangle, low BakeUV and original corner split normal. Low remains 9,578tri; high remains 146,026tri. Original editable source and all original maps stay untouched.
- Retain the original 35mm cage offsets, captured from original low vertex normals before any cage point is written. No cage-distance search and no displacement-strength adjustment.
- Temporary same-surface projection groups: ground top, vertical closure, bottom; the eight already existing independent solids are isolated by connected component to avoid cross-object rays. These are baking tools, not new visible pieces or a collision change. Their target tangents/signs must match the final low copy.
- Correct only copied high-ground vertical source UV to X/height or Z/height at the existing Rocky2m/Sandy2.5m scale. Top source UV and displacement are unchanged. Preserve source colors and physical AO.
- Raw per-group Normal images use explicit BakeUV/Tangent and zero padding; native Blender EMIT composes them back into unchanged BakeUV with explicit 1px EXTEND padding. Raw group separation prevents one bake's padding writing another group. No Python/shell image editing or erasure of bad normal pixels. Final Normal strength stays1.
- Final BaseColor retains original top/solid map data and only replaces the side source mapping. ORM retains the old full-source AO in R and metallic in B; only side roughness is reprojected. Native recomposition checks AO against the old occupied pixels to within one 8-bit quantization step, not a perceptual tolerance.

## Stages and stop conditions

1. `prepare`: estimated **25–55s**, private limit **90s**, CPU2. At all1,965 originally identified negative-Z pixels, read the original high hit's geometric normal and barycentrically interpolated corner normal. A miss, wrong ground face class, or a high normal facing away from the low is a **stop before baking**, with a saved diagnostic blend. Then build temporary same-triangle tools, verify source UV area, exact geometry/BakeUV, and tangent/sign consistency. Output `prepared_repair.blend`, `bad_pixel_source_normals.json`, `projection_groups.json`, `semantics.json`, `result.json`.
2. `bake`: estimated **35–80s**, private limit **180s**, CPU2. Reopen the successful prepared blend; project and save each map checkpoint separately. Native1K final BaseColor/Normal/ORM. Record every old bad pixel's before/after value and the whole occupied top negative-Z count, actual texture ranges and AO delta. Reversed top normals, unbaked/missing pixels, changed geometry or AO beyond quantization stop the stage and save `bake_failure.blend`. It does not render automatically.
3. `render`: estimated **80–110s**, private limit **180s**, CPU2. Reopen `baked_repair.blend`, check absolute image paths/hashes/real pixels, Normal and AO links, exact low/high geometry, original camera/lights. Produce only `01_high_source.png` and `02_low_baked.png` at the old1280×1100 camera, 24samples. This remains pending actual image review even on exit0.

The estimates are based on previous source inspection12.86s and two source renders within114.97s; they are not new measured times. Each stage has a unique directory, full stdout/stderr, PID/elapsed/exit record and input snapshot. No stage starts the next one automatically. Any ERROR line invalidates exit0. Timeouts terminate only that launcher's newly created PID tree. No Godot/GPU is launched.

From project root `.`:

```powershell
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_01/run_repair.py prepare
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_01/run_repair.py bake --previous <successful-prepare-directory>
python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_01/run_repair.py render --previous <successful-bake-directory>
```

The runner accepts only prior stage directories inside this new folder and successful result/hash records. Only AST/static checks have run so far. Blender API behavior, projection correction and visual quality remain untested.
