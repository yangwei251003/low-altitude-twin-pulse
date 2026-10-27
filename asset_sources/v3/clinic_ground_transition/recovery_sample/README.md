# 0.9×0.9m real-height method sample — prepared, not executed

Root approved preparation only. No Blender/Godot process, render, source mesh, bake or export has run for this sample. Route5e455d78-37b2-423b-b660-0cc3185eae49 is reused. P13 and `recovery_study` are frozen and remain untouched. This sample is not P14 or an approved production placement.

## Fixed construction and material choice

- Godot-local bounds planned X±.45, Z0.. .9; slab topY0, structural bottomY−.18. Blender coordinates are `(x,−z,y)`. No runtime/layout write.
- One real18cm fractured concrete slab: uneven upper break, shorter angled break faces, six12–35mm embedded mineral pieces at different heights, and one fallen concrete chip. They remain separate editable originals. No new scan/model/image source and no scatter loop or parameter search.
- One asymmetric shallow channel. Soil ground has an actual64×64 top grid; the high source adds Simple subdivision level2, then genuine Displace along Blender localZ/GodotY. This deliberate vertical heightfield keeps XZ fixed instead of folding channel topology with sideways normal displacement. The low source uses the same height texture/UV/strength on its64×64 grid, retaining medium relief as vertices.
- Original Rocky Trail height/Diffuse/Rough share2m UV `(x/2+.31,z/2+.09)`. Sandy remains2.5m quiet bed. Raw source PNG bytes are unchanged. No reference lighting is used as height. The same continuous shoulder weighting drives albedo blend and geometry; the boundary fades over the explicit centimeter-scale band.
- Fixed original-height crop UV rectangle `[.085,.1975,.535,.54]`: median `.6098573281`, p01 `.4709422446`, p99 `.8900251774`. **One fixed strength `.0477232510m`**, chosen as`.020/(p99−p01)`. Unweighted full crop displacement extrema approximately−13.381..+18.573mm; actual weighted/evaluated range remains to be measured. This is authored amplification, not measured vertical scan depth. No automatic second strength.
- The full original scan NormalGL is disconnected in this diagnostic, including all source macro-normal overlays. This follows the independent read-only review: normalizing two vectors or sharing UV does not subtract low-frequency slope already represented by displacement. The low tangent normal will be baked from actual evaluated high geometry. Existing concrete atlas and its material recipe are reused; tiny procedural bump is also disconnected so the comparison tests real shape.

Estimated topology, not an acceptance assertion: high≈146k triangles; low≈9.6k. Actual report wins. The low result retains groove/aggregate/fracture outline; it is not a normal-mapped rectangle.

## Two recoverable stages

**A — construction/checkpoint.** Estimated25–45s; private hard90s. Builds editable originals and high/low evaluated proxies, checks actual separate-solid closure/positive volume, bounds, embedded-vs-exposed aggregate, chip/ground contact, BakeUV area, sampled high/low sections. Resolves every image path, verifies original SHA/size and actual pixels; saves and actually reopens `editable_checkpoint.blend`. No image render/bake in A.

```powershell
python asset_sources/v3/clinic_ground_transition/recovery_sample/run_study.py build
```

**B — native bake and two same-camera images.** Estimated100–160s; private hard240s. Requires the exact successful A checkpoint. Does not reconstruct geometry. Native1K BaseColor and tangentNormal are Selected-to-Active separately for soil and solid groups into nonoverlapping atlas ranges. ORM uses the complete joined high geometry for local contactAO, roughness and metallic0. AO is separate from unoccluded BaseColor; both high/low preview materials use it consistently. A custom35mm cage has the corresponding low topology. Per-map checkpoint is saved before the next map; every low triangle centroid is checked for the magenta miss sentinel. A logged image/bake error fails even if process exit0.

```powershell
python asset_sources/v3/clinic_ground_transition/recovery_sample/run_study.py bake_preview --checkpoint "<actual successful A directory>/editable_checkpoint.blend"
```

B saves and reopens `low_baked_preview.blend`, verifies original and baked file paths/hash/actual pixels, then renders `01_high_source.png` and `02_low_baked.png` under the same fixed camera, neutral lighting and exposure. No GLB/export/runtime output. The high camera image is a source diagnostic, not a game capture.

The runner refuses to launch when an existing Blender/Godot/LowAltitude process is present. It only kills its own new PID tree if that stage exceeds its private limit; it does not reclaim another agent's process. Both stages have unique run directories/stdout/stderr/process.json. Neither stage automatically retries or starts the next. Total estimated125–205s; splitting preserves geometry and each completed map if a later stage fails. Actual elapsed times are pending.

## Review and limits

After root grants execution, inspect both original PNGs before judging. The desired evidence is a genuinely thick break with embedded aggregate and a coherent mixed-grain shoulder fading into a clear low-density groove. If high improves but low becomes a flat sticker, the method has not succeeded. No success will be inferred from triangle count or roughness statistics.

Closure is tested per solid, and terrain has unchangedXZ/single-valued height; a universal arbitrary-mesh self-intersection audit is **not** claimed by this prepared script. Embedded aggregate intentionally intersects the concrete volume. All actual source/collision integration and gameplay sweeps remain future work. The sample cannot validate final whole6m composition, default game-camera readability or final performance.

Static syntax parsing passed for the five Python files. Blender-specific API and resulting geometry/UV/cage images remain unexecuted. The official current [`object.bake` signature](https://docs.blender.org/api/current/bpy.ops.object.html?highlight=light+add) was checked for string `cage_object`, `use_cage`, tangent normal and explicit image target behavior; this does not substitute for the actual run.
