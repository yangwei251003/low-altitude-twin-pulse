# Two residual boundary regions — read-only preparation

The repaired normal bake and two reviewed renders remain frozen. This task does not rebuild geometry, change UV/cage/normal/AO, save a blend, bake, render, or export. The parent must explicitly allocate the next engine window before the runner executes.

Inputs: the actual `bake_20261020_010927_047833/baked_repair.blend`, projection groups, final three PNGs and the two fixed-camera PNGs from `render_20261020_011918_547529`. Input bytes/SHA are checked before and after the diagnostic.

The current static image measurement locates differences; it does not identify their physical cause:

| Region, pixel origin top-left | Low dark pixels | High dark pixels | Low newly darker | Samples including controls |
|---|---:|---:|---:|---:|
| Left junction x176..211/y594..711 | 566 | 165 | 479 | 636 |
| Fragment base x738..794/y390..473 | 35 | 1 | 32 | 122 |

Dark selection is display-luma < 0.15 in either frozen PNG; newly darker also requires high-minus-low > 0.06. These are selection criteria, not material or geometry acceptance thresholds. Every selected dark pixel is retained, together with an eight-pixel grid of controls: 758 samples total.

The inspection opens the saved blend read-only, constructs derived BVHs from its actual high/low and 11 matching groups, and records:

1. Same-camera first-hit triangle/group, world position, geometric and interpolated corner normal, three vertices and edge adjacency. Camera rays are independently round-trip checked against Blender camera projection. High-minus-low ray depth and low-to-matching-high nearest distance are retained; unsigned nearest distance is not called a gap or penetration depth.
2. Exact low BakeUV at each hit, four bilinear pixel taps, actual Normal/BaseColor/ORM values, and the actual triangle/group occupying each tap. This distinguishes a dark AO tap, an empty/gutter tap, residual normal direction, and a visible geometry mismatch. CPU level-zero texture filtering and tangent reconstruction are explicitly approximations to shader filtering, not instrumented Cycles internals.
3. For three separated representatives in each region, six-centimetre local X/Y/Z line sections through all high/low component groups. Intersection locations and enter/exit normal signs are written without inventing a global solid-boolean verdict. These raw sections and local triangle coordinates let the reviewer distinguish a real inter-component separation/overlap from shading at a shared boundary. Coordinates are Blender world coordinates from the saved scene.

The successful original full-shell/matched-group normal diagnosis is not repeated. No huge all-scene self-intersection sweep, broad strength search or image editing is performed. Missing inputs, camera mismatch or an actual data/API error stops this one run and retains logs.

Prepared entrypoint (not run):

`python asset_sources/v3/clinic_ground_transition/recovery_sample_v2/repair_01/boundary_inspection/run_inspection.py`

Expected 15–35 seconds; CPU 2; hard limit 60 seconds on this private process tree. Output is a new timestamped subdirectory with before/after hashes, pixel/geometry evidence, local sections and process logs. No automatic next stage. Python AST validation has passed; Blender execution remains pending.
