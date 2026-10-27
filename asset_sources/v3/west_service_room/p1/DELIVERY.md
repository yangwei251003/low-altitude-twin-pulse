# WestLowRoof candidate delivery

Root approved the single-object reference, then the repaired source close view. This is a **candidate for actual MAIN evaluation**, not whole-area art acceptance or game verification.

- Candidate: `assets/v3/candidates/west_service_room/west_service_room.glb`.
- SHA256: `e8b6b55b2ce6d8b780a51e867166c5ff9b04512c15399b65a41cdf9b05ae08c1`; 3,930,848 bytes.
- Root `WestServiceRoom`, children `PaintedShell` (2,376 tris), `ConcreteBase` (220), `RoofMetal` (1,012). All identity transforms. Three opaque single-surface PBR materials, nine embedded 1024² PNGs.
- Godot-local AABB `(-2,0,-2)..(2,2.5,2)`. Bottom-centre source origin corresponds to world `(-14,0,-8)`. +Z is the south panel front. Root's body-child offset `(0,-1.25,0)` is consistent with the existing WestLowRoof centre.
- No collision, light, camera, animation or invented enterable doorway in GLB. Original full-box collision and whole-body visibility behavior remain Root's responsibility. Eight louver slats have a real opaque backing.

## Reopenable source and texture meaning

`west_service_room_editable.blend` preserves 106 independent editable components, three explicit source materials, MetricUV/FinishUV/PanelUV, and relative paths into `source_inputs/`. Reopening and actual image pixel reads passed. `west_service_room_delivery.blend` contains only the final root/three meshes with baked textures under `textures/`; no staging scene is exported.

The approved pump-shell V2 atlas supplies authored paint and concrete colour regions; original bytes are copied, not repainted. Concrete micro-bump is procedural and deliberately restrained. Roof steel uses ambientCG Metal012 Color/Roughness/Metalness/NormalGL at explicit metric UVs, with dimmer tint and higher roughness than the original response to avoid competing with the gravity tank. Metal012 is CC0; retained source provenance and copied PNG hashes are in `source_material_provenance.json`.

Each runtime set has sRGB BaseColor and Non-Color ORM/Normal. ORM R is 1 on occupied/dilated UV pixels (unoccupied atlas background is black); no AO or lighting was baked. G is roughness and B metalness. Normal is +Y tangent space, strength 1 in the standard runtime material. Source Metal012 strength .25 is baked only once. Paint and concrete normal outputs are actually neutral at 8-bit precision; roof variation is extremely weak. **No claim of strong microscopic relief**: readable rims, slats, seams, bevels and bolts are real geometry.

## Checks and deliberate limits

Actual raw GLB triangle multiset/winding, position, UV0, exporter-quantized normal, tangent presence, material channel mapping and all nine embedded original PNG hashes passed. Same-byte Blender reimport retained 3,608 triangles. Position error is zero; maximum UV error 2.98023224e-8. The raw exporter mapping remains checked independently.

Blender's second custom-normal storage quantization caused an initial component-threshold failure. The original failure and unchanged GLB SHA are retained. Double-precision `atan2(|cross|, dot)` then measured maximum angle **0.01428135°**, within the explicit 0.1° visual storage tolerance, not bit identity. Normal lengths are .999999869..1.000000129, with no zero or reversed normals. Worst sample is PaintedShell at local (1.89199996,2.03999996,-1.30799997); source/actual vectors are recorded in `export_report.json`.

The first preview had coplanar corner-cap/post exterior faces. `failed_cap_overlap/` retains the failure; four posts were shortened to meet the cap at Y2.32. Root and agent both viewed `01-single-object-repaired.png` and confirmed the black blocks are gone. The original `02-26m-scale-source.png` is a scale study made before this local fix, explicitly not final repaired geometry or game evidence. Root waived a redundant second far render in favor of actual MAIN captures.

Remaining visual limit: wall paint is lighter and weathering cleaner than the concept. Root accepted proceeding to the same real lighting as the current pump building; do not claim final artistic approval from the source views.

## Selected process evidence

| Stage | PID | Seconds | Exit | Owned residual |
|---|---:|---:|---:|---:|
| First source, black corner overlap | 34428 | 85.735 | 0 | 0 |
| Corner repair, one source close view | 43768 | 48.875 | 0 | 0 |
| Three 1K PBR sets, one bake | 41212 | 10.828 | 0 | 0 |
| Export, raw passed/reimport component failure | 28284 | 3.328 | 3 | 0 |
| Same-byte angular reimport | 20884 | 2.687 | 0 | 0 |
| Same-byte worst-point/unit-normal evidence | 35120 | 2.922 | 0 | 0 |

All used CPU2, `scripts_tools/v3/dev.py.execute_command` hidden private Windows Job with stage hard limits. No additional offline GLB render, no production/shared write, and no Godot execution by this producer. Use `delivery_manifest.json` / `selected_files.txt` for selective archiving; prepared bake/checkpoint blends and redundant input snapshots are intentionally excluded.
