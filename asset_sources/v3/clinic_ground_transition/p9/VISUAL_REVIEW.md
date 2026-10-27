# P9 — actual source render review

Status: **self-review rejects artistic completion; no GLB or game integration**.

The reviewer actually viewed both original PNGs, the approved `ground_transition_reference_v2.png`, and all three native baked maps. The two P9 images are Blender offline renders, not game screenshots. The full and close camera/light setup is the same as P7/P8. No image was edited.

## Visible result

- Removing the 4,909 high-only grain layer removes P8's hard-edged, uniformly embedded gravel mosaic. The scanned soil is continuous across the surface and its texture is present in the close image; it is not an empty or magenta material.
- The result still does **not** reproduce the chosen reference. The whole soil area reads as one pale sandy surface. Three low channels exist in geometry, but their directional wash, muddy bed and changing sediment density are not clear in the full view and remain weak in the close view.
- The preserved coarse stones have visible thickness and contact shading. Their sparse repeated clusters/strings remain conspicuous because the scanned base supplies fine sand, not the missing intermediate deposit layer. Scan provenance and correct UV do not resolve that composition problem.
- The original concrete and dark broken edge remain, but edge aggregate is still too row-like compared with the reference's irregular accumulation. The exposed perimeter wall still reads as a cut-out model; it has not been assessed seated in actual game terrain.

The new scan is usable as a continuous soil substrate, but this material substitution alone is insufficient for delivery. No automatic second build, new material download or geometry revision was started after this review.

## Actual execution and bounds of evidence

- Blender PID 38232, CPU2, natural exit 0; runner elapsed 107.51055 seconds, own-tree limit 240 seconds. The engine window was explicitly returned immediately after natural exit.
- 7,638 low triangles, 159 editable pieces; all source vertex float32 values, original polygon index order and object matrices match the frozen P7 source. No high-only fine-grain geometry remains. These are source checks, not Godot physics or visual approval.
- The real joined `BakeProxy` contains 7,410 soil loops checked against 2.5m `SoilScanUV`; maximum mapping error is 5.2452087562215866e-8. All three source textures explicitly use this UV.
- Source Diffuse is sRGB; source OpenGL Normal and Roughness are Non-Color. Native baked BaseColor/ORM/Normal are all 2048×2048, with corresponding sRGB/Non-Color/Non-Color settings. The actual final blend was reopened and file images reloaded through `bpy.path.abspath`; paths resolved and image data was present.
- Contact AO uses the actual joined low terrain and coarse stones, not the removed fine-grain layer. The offline preview multiplies the same ORM R; the retained standard glTF source material uses occlusion. Exact cross-renderer lighting equivalence is not claimed.
- Authoritative raw logs/reports are retained unchanged. `production_report.json` records execution success pending review; this review records the separate negative art judgment.

## Files

- Full: `evidence/transition_source_p9.png`
- Close: `evidence/transition_contact_close_p9.png`
- Editable: `editable_source.blend`
- Baked/reopened: `baked_source.blend`
- Actual UV binding: `soil_scan_binding.json`
- Exact low comparison: `low_geometry_equivalence.json`
- Native maps and resolved images: `production_report.json`
- Official raw source maps, authorship, license and hashes: `vendor/polyhaven_sandy_gravel_02/provenance.json`

Original source: [Sandy Gravel 02](https://polyhaven.com/a/sandy_gravel_02), Dario Barresi / Poly Haven, [CC0](https://polyhaven.com/license). The scan is used as material input, not as a substitute scene or reference screenshot.
