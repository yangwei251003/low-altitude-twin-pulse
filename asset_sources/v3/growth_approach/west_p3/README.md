# West P3 — geometry diagnostic, visual self-review rejected

This directory is the only new write scope. Frozen `west_p2`, production assets,
world/session code, tests and shared documentation were not changed. The source,
basic-material GLB and preview below are temporarily frozen for root review.
**The numerical checks pass; the visible result does not pass the art brief.**

## Actual observation

Before editing, the author viewed the approved v2 single-object reference and
the real P2 placement frames `02`, `03`, `04` under
`artifacts/v3/art/capture-20261018_064640_203343/`.

P3 replaces all four rejected stone meshes. Two deep bearing volumes sit above
two offset foundation volumes; the top and body are one closed mesh per rock,
not an independent thin cover. Only the measured west join, bridge lip/nose,
eight anchors and 1.7 m central carrying strip are fixed. Free side edges may
descend, and the side volumes include a broad recess around the natural roots.

The actual offline image `west_p3_default_direction.png` was viewed after the
successful export. It still looks like a box with a rectangular recess; the
natural root is mostly occluded and appears as short exposed fragments. The
four rocks remain too architectural. These are shape/placement failures, not
problems to hide with PBR or moss. No further appearance variant was started;
root was given this diagnostic GLB and the explicit rejection. Do not promote
it as accepted runtime art or start final texture work from this status.

## Source and bounded repairs

Input: `../west_p2/growth_approach_west_p2.blend`, SHA256
`0d56dd85793d7d3b5e92e8cc24015bc1399af182d028ec73516303abeb2c3dfc`.
The old P2 parts are also retained as hidden editable objects in this new blend.

Natural fork input remains the embedded, frozen Poly Haven Island Tree 01
tree-base/fork copy (CC0), source <https://polyhaven.com/a/island_tree_01>.
It is not described as a naked-root scan. The source archive is untouched.
The existing archive's upstream source hash is retained on both new root nodes.

The first P3 attempt projected individual root vertices onto the stone's first
hit surface. Discontinuous stone seams produced 367/484 strict crossings. That
attempt was rejected before GLB export and its blend/report/log were preserved
as `first_failed_*`. A separate diagnostic found four crossings already present
in the original source within a 32.77 mm patch. In the new copies only, seven
vertices were locally smoothed; maximum displacement 14.10 mm, four crossings
to zero. The successful roots use rigid uniform 1.05 scale and rotation; no
per-vertex rock projection or normal flattening remains. Source root topology
is retained without decimation in this diagnostic to avoid creating new folds.

`second_failed_boundary.log` retains the clipping-boundary error, corrected by
micrometre-scale matching of coincident plane intersections.
`third_failed_geometry_report.json` and `third_failed_build.log` retain the
subsequent side-mask fold and shallow cap failure. The side section was made
continuous/monotone and two explicit end-section stations added. No acceptance
threshold was weakened. The material image was rendered only after all source
geometry checks passed.

## Placement contract

- Root `GrowthApproachWest`: identity local transform; Godot world placement
  **(-14.5, 0, 25)** without corrective rotation or scale.
- Godot local bounds **(0, 0, -1.5)..(3.75, 5.25, 1.5)**; Blender Z up.
- West five sampled heights come from the preserved original JSON bytes in
  `input_f1_growth_crossing.json`. The original section triangle planes remain
  the authority for the central 1.7 m carrying strip.
- Formal bridge lip local X3.5, Y5.25, width3 m; inset nose X3.75, Y5.20,
  width2.98 m. The nose is not raised to the lip height.
- `OuterJoin`, `OuterJoin_0..4`, `BridgeLip`, `InnerEnd` retain their original
  transforms; eight anchors total.
- Four rock meshes and two root meshes, **42,324 triangles / 14 primitives /
  four basic materials**. No collision box, hull or independent cover slab.
  Any placement collision must use these same visible triangles.

## Verification and limits

Blender 5.2.1 LTS / Cycles CPU2 / 12 samples, successful build/render exit0.
`geometry_report.json`: **38 checks, zero failures**. It records closed edges,
positive volumes, zero degenerate faces, per-mesh strict self-crossing zero,
fixed bounds/anchors, five west interfaces, full lip/nose and 205 carrying
samples. Both original root end-cap sets were sampled (994 points); minimum
burial against the actual stone side is **58.19 mm**.

`geometry_checks.py` uses BVH only to identify candidate triangle pairs, then
double-precision plane-straddling and positive-area coplanar intersection.
It distinguishes contact from penetration. Its pure predicates were checked
against proper penetration, coplanar overlap, shared-edge-only contact,
one-sided plane contact and separated planes. Cross-object rock/root embedding
is deliberate and outside this per-mesh self-intersection result; there is no
claim that the whole asset is a single disjoint watertight union.

`inspect_review_glb.py` reads the actual GLB bytes, node transforms, positions
and indices without an engine import: **15 checks, zero failures**, including
205 central samples and 67 west/lip/nose samples reconstructed from exported
triangles, eight anchors, source/export counts and bounds. This is stronger
than only comparing the GLB's declared accessor bounds, but it is not a real
Godot actor sweep, light-path check or actual game-camera capture.

The preview shares the game's direction (32,39,32), with an isolated object
framing. It is an offline basic-material image, not a game screenshot. No P3
world placement, player physics, human play, performance or visual acceptance
is claimed by this directory. P2's placement checks do not carry over.

## Frozen output bytes

| File | SHA256 |
| --- | --- |
| `growth_approach_west_p3.blend` | `4a537c76d878d28b75cbfc6dda9bafbb58e79b17edb0f9f72e090980a8828d92` |
| `west_p3_review.glb` (817,092 bytes) | `1804c11af262d37981def4b9522c2d8bcbf6def9093d1ad043a09826ec6a6089` |
| `west_p3_default_direction.png` | `4b991efacd53bc18340e48e5a16490fa70de115f984103ce4860d9c12fb2c683` |
| `build_west_p3.py` | `5ef7e19afef39110ac3e751e954ae5502e351459210d51dbc92fc4abb6ea0924` |
| `geometry_checks.py` | `48921367f32fa72fb07e75ea51dddc6225abfff1f040c92708b512731c2995f8` |

## Rebuild, only in a newly coordinated authoring window

From the project root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --threads 2 --python-exit-code 1 --python asset_sources/v3/growth_approach/west_p3/build_west_p3.py
python asset_sources/v3/growth_approach/west_p3/inspect_review_glb.py
```

Optional `-- --no-render` skips only the image. The script writes this directory
and reads the current production JSON, preserving its exact bytes and hash.
Rebuilding would replace these frozen diagnostic outputs, so do not run it
while root is reviewing their current bytes.
