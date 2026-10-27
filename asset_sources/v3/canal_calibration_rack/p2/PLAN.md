# Rack P2 — material-only source preview, static preparation

Input is the frozen, actually reopened P1 `.blend`, SHA b980c089f57a00a8d8071cd2002620b6a548582cd563ade9b5e7914891b5f309. Keep all51 editable pieces,4740 triangles, positions, per-corner normals, five source UV layers, SurfaceUse, transforms, camera and lights exactly unchanged. No new geometry, image generation, bake, GLB or runtime changes.

The P1 image was actually viewed against the approved reference and rejected for cloudy reflective deck, pale yellow and long frame streaks. P2 makes these changes:

- Steel base colour:18% original Metal012 colour,82% neutral steel; roughness `.55 + .28*original roughness`. This reduces the broad cloud/reflection contrast while keeping physical steel and the original source data.
- Anti-slip ribs:70mm diamond-cell pitch, alternating approximately28×5mm ribs. Use1.5mm source Bump distance/strength.70, chained after the original tangent NormalGL (strength.20). This is material relief, not a claim of new physical geometry. Inspect the actual top SurfaceUse values and both graph links after saved-source reopen; the real rendered result decides readability.
- Yellow: linear warm-yellow base(.50,.25,.008),roughness.80,metal0. Keep the79mm band with quiet centre; sparse chips are restricted to its outer/inner18mm edge zones, not full-surface noise.
- Teal: quiet base(.035,.10,.115),atlas centre weight.10, rising only near actual component corners/access-cover ends to at most.85. Original texture bytes are retained; no long full-frame stripe is added. Hardware roughness `.48 + .30*original`.

Entry: `python asset_sources/v3/canal_calibration_rack/p2/run_preview.py`. Uses the existing `scripts_tools/v3/dev.py.execute_command` hidden Windows private Job, CPU2,hard120s. Expected70–100s, one unchanged1280×1100 view; do not run until root grants the next serialized window. No source edit or new render occurs as part of preparation.
