# Crown p6 isolated candidate

This folder is a single candidate based on frozen p5, not final art acceptance. The running p5 GLB and p5 editable source remain unchanged. Parent integration must explicitly select `assets/v3/candidates/crown_p6/parasitic_crown.glb`; this folder does not change the game wrapper or encounter.

Candidate freeze: `3b87381e7769132367f76ef96e1ee549a3937ad526bd2df1d306a44164c40cde`, 16,341,508 bytes. The successful binary and same-byte roundtrip report is `crown_glb_validation_p6.json`; the file hashes are in `candidate_lock.json`. Actual imported closed/open bounds match the raw-binary calculations within 0.000000060 m. Actual GLB fixed-angle CoreSeed projection is closed 0/10,828, open 9,054/10,828 (83.6165%). All 18 critical anchors retain identity rest rotation/unit scale and their named parent chains.

The analytically bounded crown arc has Godot min (-3.537612,-3.000001,-2.711498), max (3.333720,2.910001,2.508465), horizontal radius 3.984858 m (rounded outward). This covers the declared three plate motions with the limbs at rest; it does not certify hypothetical future shoulder/wrist animations. Front probes report 9 blocked when closed and 0 blocked when fully open. The unchanged seed/shell intersection remains 112 sampled edge/face crossings and zero surface gap; Core anchor's nearest closed armor point is 0.0198079 m away.

## Reproduction

Run Blender 5.2.1 LTS in background mode with `-t 2`, serially with the other asset renderers:

1. `--python prepare_p6.py` loads the exact frozen p5 source, reconstructs the candidate cavity and leaf membranes, and writes `parasitic_crown_p6_geometry.blend`, two shape studies, and `geometry_review.json`.
2. `--python build_p6_surfaces.py -- --bake --export --render` uses that geometry plus the preserved original single-material references. It creates external PBR images in `textures/`, editable `parasitic_crown_p6.blend`, and the isolated candidate GLB above. It does not modify the running p5 files. Plain `--render` writes an unbaked surface study only.
3. `--python verify_p6_glb.py -- --render` reads the actual exported binary, validates the actual topology/UV/material indices, continuous crown motion envelope and 18 anchors, measures actual core-surface occlusion, imports the same bytes, verifies imported pose bounds against the binary calculations, then renders both poses.

The original single-material stone PNG is preserved byte-for-byte with `stone_source.json` and `stone-prompt.txt`. Bark and leaf use read-only original references under `../../material_references/`; exact input hashes are recorded in `surface_review.json`. No game lighting is baked into BaseColor. Local cavity AO is a modest surface aid. Roughness and OpenGL tangent normals use Non-Color; BaseColor and amber emission use sRGB.

## Interface and intentional changes

Root, Core, shoulder/wrist/contact and leaf pivot transforms are retained. Four feet still rest at Godot Y=-3 m. All 76 editable meshes remain separate, including CoreSeed and all moving plate/limb children. The candidate has 31,818 triangles.

Candidate plate endpoints are Godot local Y -60° for L, Y +72° for R, and local X -58° for C. These differ from p5 and require explicit wrapper support. A continuous analytic envelope is required; checking only the closed and open endpoints is insufficient.

The front three rings of `Torso_ContinuousRootSleeve` are reshaped into an asymmetric raised opening. `BrowRoot_1` and `BrowRoot_-1` have localized lifts, outward shifts and backward bends with the base preserved. CoreSeed anatomy and Core anchor are unchanged. This opens the view into the existing seed without shrinking the whole creature or removing its major shell.

Both leaf membranes and their three rib meshes are rebuilt with a broad notched outline and thickness. A weighted twist and gentle billow improve the fixed oblique projection; the actual left leaf projected area increases from 0.695 to 2.415 m² while the right decreases from 2.259 to 1.650 m². The leaves remain asymmetric; source geometry reports these measurements separately from total surface area.

## Evidence boundary

`geometry_review.json` is source geometry evidence. `surface_review.json` records actual bake/export inputs and hashes. `crown_glb_validation_p6.json`, when produced successfully, is the binary GLB and imported-geometry record. The closed/open PNG files are offline renders in the game's camera direction with studio lighting, not game screenshots, human playtests, frame-rate evidence or final artistic approval.

The visibility measure is the fraction of actual CoreSeed triangle projection visible through all intervening creature triangles, using a 120×120 raster of the core's projected bounding box. It is not nine empty-anchor rays and does not measure projected screen size, attack aim comfort or occlusion by the actual host platform. Those require the parent agent's real game camera and collision checks.

The p5 anatomical core/shell intersection is not silently fixed by this candidate. Core damage collision must still be disabled when closed, enabled when open, and the real armor triangles must remain active. The actual candidate surface-gap/intersection result is recorded by the binary verifier. No collider may be shrunk to make a size check pass.
