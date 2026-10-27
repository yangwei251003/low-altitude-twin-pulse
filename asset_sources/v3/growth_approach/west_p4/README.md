# West P4 — first form image rejected; frozen diagnostic source

2026-10-18. Only this new directory was written. P1/P2/P3, reference images,
production assets and shared scripts are unchanged. No P4 GLB, PBR textures,
game import or runtime placement was produced. Do not promote this source.

## What actually changed

The approved redesign report and its reference measurements were read first.
Four independent, uneven point clouds form three main thick rock masses and a
smaller lock stone. They are not boxes or a full rectangular top rim extruded
downwards. Their solids are clipped by the measured interface surface, then
joined with solid subtraction so visible top faces do not simply overlap.
The source preserves each uncut and clipped rock in a hidden construction
collection. Local free rim points descend independently of the carrying strip.

Two continuous roots use editable Bezier paths, varying radii, and an asymmetric
0.52 × 0.32 m base cross-section. A shorter branch joins the south root; only
that wood junction is voxel-remeshed. The original curves and profiles remain
editable and hidden. No natural scan was flattened or forced onto rock vertices.

## Actual result and stop decision

`west_p4_default_direction.png` was viewed after Blender exited successfully.
It is one offline basic-gray/wood form image, direction `(32,39,32)`, not a game
screenshot. The main root is now continuous in this view. The rock masses still
read as hard geometric wedges, and the upper surface has obvious abnormal
cuts/void-like shading. It does **not** reproduce the approved reference's
substantial, interlocking natural rock masses. The other root is on the far
side and this single view does not demonstrate both visible root paths.

The image and quick geometry report both reject this attempt. No second image,
new design variant, P5 or texture work was started. Root and the next artist were
notified immediately after exit; CPU2 was released.

## Quick checks: 30 total, 28 pass, 2 fail

Preserved checks passed: five measured west joins, full-width bridge lip/nose,
205 samples of the central 1.7 m carrying strip, eight original anchors, closed
edges, and the frozen P3 source hash. These limited checks do not establish full
physics validity or artistic quality.

1. **Actual envelope fails.** All vertices span Godot local
   `(0,0,-1.529864669)..(3.75,5.25,1.555620790)`.
   The Z budget is ±1.5 m; excess is 29.865 mm north and 55.621 mm south.
   The curve control-point clearance used an estimated normal radius; it did
   not bound the evaluated twisted full cross-section. This is an implementation
   error, not permission to enlarge the asset or shrink collision.
2. **West rock solid orientation fails.** `Rock_C_WestFoot` has signed volume
   `-5.871838160 m³`, with zero zero-area faces and zero open/nonmanifold edges.
   The earlier brief message calling it a degenerate-face issue was corrected:
   the actual failure is negative volume in the Boolean/orientation result.
   Its cause has not been isolated by a further Blender run. The artifact must
   not be treated as a valid closed outward-facing solid merely because edges
   are closed or vertical rays find a surface.

Expensive self-intersection, actual body sweeps, light first-hit, source/GLB
round-trip and game-camera tests were not run. Root requested the single first
form image before further audits, so the image was retained as a diagnostic
despite the explicit two quick failures. No pass claim is made.

## Frozen files

| File | SHA256 |
| --- | --- |
| `growth_approach_west_p4.blend` | `7090e4a3c0dd10fee7cc044e2b1216a99d50fe373be2167b38cd1bc024f2397e` |
| `west_p4_default_direction.png` | `44f5a46c2a96f62ccffc540c35cc2aa3e8f97d5594b5c83e269e6e621fa6eec9` |

`geometry_report.json` records the source/reference/layout hashes, evaluated
vertex bounds, path points and all quick checks. The visible form has six mesh
objects and 28,826 triangles; neither count is an art acceptance target.

`initial_duplicate_hull_diagnostic.log` preserves an immediate pre-render
Blender error: convex-hull API lists contained the same interior element more
than once. The input list was deduplicated and the script rerun within the
allocated first window; only one complete image was rendered.

The reproducible build command is in `build_west_p4.py`, but executing it would
overwrite these frozen diagnostics. Do not run again without a new assignment
and a coordinated window. There is no authorized automatic next variant.
