# Inspection pit delivery — static prepared plan, waiting engine window

This directory is the art agent's exclusive delivery workspace. Root owns `p1/build_source.py`, the source preview, geometry authority and runtime wrapper. No Blender/Godot has been run for this delivery. No new reference image or source material is required.

The inspected historical preview is `../p1/preview_20261020_041821_fc8e50/`. Root subsequently inset backing end/bottom faces by 12 mm and corrected both ramp-side windings. The final source is now locked to `../p1/preview_20261020_042716_f10932/inspection_pit_editable.blend`, SHA256 `1d3df8bc07ffdd9894f9e15cc81b9cead195ed10b4a616ad607e801b62367346`: 224 editable parts, 19,640 triangles. Root personally approved its source image for candidate baking. The older preview is not an execution input. `input_contract.json` pins the final source and report hashes; scripts read its actual triangulation rather than retaining old corner order.

## Reuse with concrete benefit

1. Adapt `clinic_pump_shell/delivery_v8/common.py`'s explicit evaluated loop-triangle and corner-attribute copying. Preserve all four source UV layers (`MetricUV`, `WallUV`, `AggregateUV`, `PaintUV`), original face material identities and actual split normals. The inspected material graph uses explicit UVs, so combining a bake proxy does not move its source texture coordinates. Source boxes retain object translations: multiply positions by `matrix_world`, normals by its inverse-transpose; do not copy the older pump pipeline's source-identity assumption.
2. Adapt the rack delivery's staged runner, per-image checkpoints, actual pixel reads after reopening, standard Principled texture export, raw binary GLB readback and same-byte reimport. Three group bakes avoid 224 repeated bake launches. Use the existing `dev.execute_command` hidden private Windows Job, CPU2, no new process manager.
3. Retain original editable parts and packed source inputs in a delivery copy; retain the original source byte-for-byte. Resolve image paths in the actual opened context, copy the two original images unchanged to `source_inputs/`, then save relative paths and reopen. The original packed bytes and on-disk image SHA must match. Any image-loading ERROR fails the stage even if Blender exits zero.

## Proposed texture / mesh contract

| Group | Geometry / original materials | Budget |
| --- | --- | --- |
| `WallConcrete` | Walls, top coping, inset backing and ramp's actual side/front faces; preserve Wall/Coping/Seam face assignment | 2K BaseColor/ORM/Normal |
| `FloorAndRamp` | Walking floor panels, actual ramp strips and recessed groove faces | 2K BaseColor/ORM/Normal |
| `Hardware` | Real drain grate/recess, inspection hatch/frame/bolts, anchors, flush yellow markings | 1K BaseColor/ORM/Normal |

Three identity meshes / three opaque materials is the provisional export structure; Root may retain additional mesh separation for a real visibility requirement without increasing PBR sets. No collision, camera, light or studio surface is exported. Proposed identity root `InspectionPit`; source-local origin corresponds to world `(-17.625,0,5.75)` because `bp(x,y,z)=(x+17.625,-z+5.75,y)`. Preserve actual source bounds including its buried slab thickness and approximately 1 mm flush paint relief; do not silently clamp to the nominal physical planes.

Only original materials are baked. BaseColor and ORM use emission with no lighting. ORM R=1 (no AO claim), G=roughness, B=metallic. Tangent +Y Normal retains source bevel/shading and its existing procedural Bump (0.8 mm distance, strength 0.25), not a fabricated height conversion of wall stains. Source-color images are sRGB; ORM/Normal are Non-Color. Match source triangles and split normals throughout; no high/low remesh or multi-object selected projection is needed for this source.

## Density and preparation checks

Keep source coordinates untouched. Allocate a separate `DeliveryUV` with larger area for interior walls, coping, floor and slope; buried backs/bottoms receive lower chart density. Each original convex part is charted by the actual triangle's dominant normal; deterministic packing retains physical panel aspect ratio, with an 8 px gap around charts and 2 px bake extension. It does not uniformly SmartUV every visible and buried face into one sheet. Report actual triangle pixel-centre occupancy, representative px/m and min/max density before baking; exact density awaits final mesh readback. The already-modeled 3 mm ramp grooves and 4–6 mm construction seams remain geometry, independent of texel coverage.

Check actual triangle count, winding/positions, original per-face material identity, every source UV corner and split-normal error after transform. Validate new UV triangles finite/nonzero and in atlas, plus representative island separation. Single-sided ramp strips/sides are intentional source surfaces, so a generic all-mesh watertight assertion would be invalid. Do not invent new geometry cleanup merely to satisfy a copied checker. Visible geometry or UV faults stop the stage with a saved diagnostic source.

## Bounded stages, pending Root's window

- Prepare: estimated 15–30 s, hard 60 s. Reopen final source, audit packed/original images and material graph, make three proxies, allocate UV, save editable copy and `prepared_bake.blend`, record source mapping and density.
- Bake: estimated 100–180 s, hard 240 s. Nine native PNGs, checkpoint after every map; no re-render of the source. Verify actual reopened pixels, finite values, dimensions, color spaces and original source SHA.
- Explicit export/readback: estimated 10–20 s, hard 90 s. Preserve 19,640 triangles if unchanged in Root's final source; use actual final source count as authority. Verify original triangle multiset/winding, UV0, tangents, standard PBR channels, all embedded image bytes, identity transforms and local bounds. Export first into this delivery directory; copying into the authorized candidate directory is a separate same-byte step.
- Same-byte reimport: estimated 40–60 s, hard 120 s. Original source camera/light; verify actual imported meshes/material/image buffers before one PNG. Root and maker visually compare walls, ramp, seams, drain and steel pieces. This is not Godot acceptance.

Each stage checks error logs and natural exit / residual children before the next. No automatic recovery loop, no source rebake on a pure reporting defect, and no production scene or wrapper writes. Final compact manifest will include editable source/relative dependencies, nine maps, GLB, actual return render, scripts, logs and source provenance; old source previews remain untouched.

Static entrypoints: `python -B asset_sources/v3/inspection_pit/delivery_p1/run_stage.py prepare`, then separately `bake`, `export`, `preview`. Each run verifies the prepared script manifest and frozen final input before opening its private Job. Static syntax checks are not an actual Blender interface or bake test; no stage has run yet.
