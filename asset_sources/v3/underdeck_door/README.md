# Underdeck door — editable source and explicit GLB

Current material revision is **v4**, a frozen integration candidate. The parent agent performs the actual Godot camera, collision and gate-state review. The images here are CPU offline renders, never game screenshots.

The Blender source preserves 126 mesh parts. The runtime exports contain six named meshes, 16,536 triangles and thirteen material surfaces, with five PBR materials. The continuous panel is 3.8 × 3.2 × .30 m; the wall-zone hangers extend above it to Y2.038042. The rail is a separate static asset. See `docs/v3/assets/I1_UNDERDECK_DOOR.md` in the project root for all interfaces.

Pipeline, executed with the installed Blender 5.2.1:

1. `build_underdeck_door.py`: authors geometry and 20 external UV PBR PNGs, saves editable source before merging export copies, exports panel/rail GLBs, renders the source. CPU 2 threads; no GUI.
2. `inspect_glb.py`: decodes the actual raw GLB bytes, checks geometry/hierarchy/UV/material bindings and front/back solid coverage. 128 checks; compares the full six-group triangle multiset with the archived v1 geometry at 1 micrometre quantization.
3. `verify_and_render.py`: reopens source, reads evaluated geometry, deletes the source model, imports both final GLBs, checks bidirectional vertices/bounds/triangle counts, and renders front/rear/open views. 26 checks. It never changes the GLBs.
4. `freeze_manifest.py`: verifies final report hashes, records owned files and read-only reference inputs, and reads every file back. `selfcheck.json` records results.

Use `--background --factory-startup --threads 2 --python-exit-code 17 --python <script>` for Blender. Do not run the builder while the parent is importing, testing networking or measuring performance. Rebuilding intentionally changes runtime bytes and requires a new freeze; do not treat a frozen filename alone as version identity.

The texture pipeline directly authors PBR maps in UV space; no high/low geometric bake is claimed. `SurfaceUV` is the sole explicit render UV. All PNG roles are flipped vertically once when serializing the v-up authoring arrays into top-down PNG rows. Color remains sRGB, data maps Non-Color, and the normal map is tangent-space +Y with `(-dh/du,-dh/dv,+1)` before serialization.

Failures are retained in `evidence/rejected_material_v1`, `v2`, `v3` and unique process logs. The first node-construction exception is a failed attempt even though the original command did not use a Python-error exit code. Later processes use an explicit nonzero Python-error code. The final build/reimport both exited 0.

Remaining limitations: cleaner/less granular weathering than the reference, some edge wear remains flat texture, wheels translate but do not independently rotate, and game lighting/status readability/whole-scene art/performance are not accepted by this offline pipeline. The fixed neutral `StatusLens` replaces the reference's small moving amber lamp intentionally; only that surface may receive gate-state emission from the wrapper.
