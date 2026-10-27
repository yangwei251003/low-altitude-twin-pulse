# Minimal repair preparation — no engine run yet

Root has reviewed the four toggles. Normal causes the added black rim; AO does not. Keep AO and actual displacement. The frozen four-view/numeric evidence is in the parent directory, manifest SHA `e8ddefed8b45dab3b94ab24943b0a8a6027d4ef3f370063c87af59d230e08ed2`.

Static source review confirms the final Image Texture vectors all share an explicit `ShaderNodeUVMap(uv_map='BakeUV')`, the Tangent NormalMap also names BakeUV, and each original bake target sets its active and active-render UV to BakeUV. This is code evidence; the next short inspection will read the actual saved node graph/state rather than treating intended assignments as proof.

One numeric-only follow-up is ready: `python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair/run_inspection.py`. Estimated15–30s / private60s CPU2. **Do not run before the next explicit root window.** It reopens the frozen preview, does not save a blend, and produces:

- exact stored ImageTexture/NormalMap UV wiring and color spaces; saved bake settings and current operator defaults, with their limits as historical evidence;
- connected actual BakeUV islands and every occupied1K pixel center, strict triangle-interior overlap, not only centroid probes;
- actual negative-tangent-Z pixels classified by top/side/bottom/solid, island ID, geometric neighbor type and whether another occupied UV island is within the original8px padding distance;
- unchanged source/low geometry hashes and actual polygon/triangle/n-gon state.

No source image is edited or regenerated. Pixel rasterization only reads the existing native maps and writes numeric evidence. No new rendering is needed to identify whether bad top pixels are already in the island interior and whether nearby side islands could contaminate the8px gutter. If this evidence remains ambiguous, report that fact rather than picking a cage strength.

After cause confirmation, the one necessary repair can isolate affected edge projection or UV padding while keeping the interior normal detail. The prepared parent `side_uv_proposal.py` changes only vertical closure-face source UV to metre-based X/height or Z/height; top/displacement UV stays fixed. No repaired build/bake/render has yet been authorized or run in this subdirectory, and no GLB or whole-module P14 is planned.
