# Rack P4: true shallow tread study

P3 is rejected by root: values improved, but the top still reads as smoothed concrete and yellow edge damage remains weak. All P1–P3 bytes remain frozen. This P4 is a source-only preview, not baked material or game acceptance.

## Evidence and bounded change

The reopened P3 report confirms `NormalGL / SteelUV -> tangent NormalMap -> Bump.Normal -> Principled.Normal`; Height is connected and 432 top corners carry the positive `SurfaceUse` mask. P3's 70 mm cells contain only one nominal 28 × 5 mm bar, about 2.9% footprint. It is not an absent-node or missing-mask diagnosis. Bump changes shading, not silhouette, and its narrow feature coverage limits visible tread in this fixed broad-light view. We have not independently isolated sampling from lighting.

The [official Blender 5.2 displacement manual](https://docs.blender.org/manual/ja/5.2/render/materials/components/displacement.html) distinguishes shading-only bump from true surface displacement. Native mesh construction already supplies the missing capability; no new tool or image is needed. English latest-page retrieval failed, so this does not claim that page was read.

- Preserve the exact 51-piece, 4,740-triangle P3 low model, UVs, corner normals, material indices and transforms as the hidden bake target/reference where replaced by high plates.
- Duplicate only the four steel plates for editable high source. Monotonically compress the upper 10 mm by at most 2.5 mm; lower body, X/Z perimeter, existing fasteners and rim remain unchanged.
- Build 1,137 closed, chamfered bars, grouped in four editable meshes. Each is 42 × 10 mm, two opposed bars per 80 mm cell; exclude actual 4 mm plate seams and eight fastener pockets. Top reaches Y = 0.320 m; bottom embeds 0.15 mm in the lowered plate. No height or footprint expansion.
- Actual static footprint is 0.468444 m² / 4.148020 m² = 11.293%. This is design evidence, not visual approval.
- 50,028 high-only rib triangles; expected visible high source 54,768 triangles. Future runtime target remains the original 4,740-triangle model, with a grouped high-to-low normal bake only after root approves this source. No bake in this stage.
- Keep P3 steel/yellow/frame colour values, fine Metal012 normal, roughness and all lighting/camera settings. Disconnect only redundant manufactured rib Bump on high plates/ribs. Eight unequal paint-edge losses originate at existing yellow edges or seams and expose the same underlying dark steel; no full-surface dirt layer.

## Verification and execution

`python -B asset_sources/v3/canal_calibration_rack/p4/run_preview.py`

The runner calls the established `scripts_tools/v3/dev.py.execute_command` hidden private Windows Job, CPU 2, hard 120 seconds, and checks no other engine before launch. Expected elapsed 80–110 seconds. Do not execute until root explicitly hands over the current window.

Before render: exact P3 low fingerprint, image SHA/colour space/actual pixel read, unchanged camera/lights, actual high triangle count, each editable component's closed edges, finite UV, whole AABB within 10 µm of X/Z ±1.2 and Y 0…0.32. Save then reopen actual `.blend`, repeat geometry/images/material-chain verification. Log ERROR or missing images fails even if Blender exits 0. One original-angle image only, then release the window. No GLB/runtime writes.

All numbers above are static until the Blender result exists. Geometry/surface contact of the original low is retained; high relief is a normal-bake source and is not new gameplay collision.
