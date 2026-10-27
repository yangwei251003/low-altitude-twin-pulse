# P2 — restore the approved bridge deck response

Static preparation only; no Blender/PBR/GLB run. Root rejected P1 deck appearance after viewing all three images. P1 `.blend`, images, report, scripts and log are unchanged; `p1_frozen_inputs.json` records their bytes. The source images are still at `../p1/source_review_20261019_091321_348c47/`.

P1 actual run: PID13808, 112.125s, natural exit0, 66 primitive/envelope/area checks, 21 mesh / 17,332 evaluated triangles / two source materials / 42 material surfaces. Blender's future-6.0 `use_nodes` deprecation warnings are retained. Counts do not imply visual acceptance or 42 measured draw calls. P1 top looked olive-gray and nearly flat; the 110mm transverse module bands made an empty grid, while 1.5mm treads and absent scuffs reduced the useful surface cues.

## Direct comparison with frozen P4 source

The measured differences come from the actual `shared_access_bridge_deck/p4/geometry.py`, `materials.py`, and `finish_layout.json`, not from a new invented steel preset:

| Item | Approved P4 bridge | Rejected P1 landings | P2 static choice |
|---|---|---|---|
| Steel base colors (sRGB) | 323a40 / 465055 | 484c45 / 5b5e56 | restore P4 pair |
| Base metallic / roughness | .68 / .61 | .55 / .72 | restore P4 values and linked roughness response |
| Tapered tread height | 2.8mm | 1.5mm | 2.8mm; crest remains original Y0 |
| Tread spacing | 200mm | 380mm | 260mm; 30% larger pitch, about 23% fewer per axis than P4 |
| Plate seam | 4mm | 6mm | 4mm above continuous slab |
| Module end strip | P4 has no transverse wide cyan module strip | 55mm each module, combined110mm | 8mm each side in walking-steel material, combined16mm |
| Local walking wear | finite dark rubber / abrasion masks | scuff list empty | same P4 finite mask method, actual path positions, strengths .28/.38 |
| Plate fixings | not a main P4 feature | absent | four actual small low steel fasteners per plate |

The blue paint shader/PNG, folded guards, bearing shoulders, full slabs, actual widths/lengths and original body envelopes are unchanged in intent. Blue side fascia remains; the smaller flush top trim does not move the perimeter or change collision. No white edge strip or new noise-only material is introduced. The guard geometry/face mapping remains P1.

The [official Principled node source](https://github.com/blender/blender/blob/main/source/blender/nodes/shader/nodes/node_shader_bsdf_principled.cc) confirms base color influences metallic reflection and roughness controls its microfacet response; changing all color/metallic/roughness/relief together was not a harmless density reduction. The new parameters still require a real same-angle image; documentation is not visual proof.

Only the same P1 `01-east-4m-module` camera/light/exposure/sample count will render this round. The editable `.blend` still contains the full correct-size 21-module assembly, but other modules are explicitly hidden for the single hero preview. No changed camera is used to make the material comparison flattering.

```powershell
python -u asset_sources/v3/shared_access_landings/p2/run_source.py --run-authorized-once
```

Do not run until root grants a new serialized window. This launcher still uses CPU2, a 240s own-tree bound, a unique directory and complete raw log. Current pure Python result: 66/66, 21 meshes, 33,676 pre-bevel triangles, 1,762 treads. This is an editable source budget, not a frozen runtime triangle target; future bake/low mesh decisions require approval and visual evidence. No huge vertex JSON is emitted.
