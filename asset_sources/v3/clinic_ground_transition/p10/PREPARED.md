# P10 prepared entrypoint

No Blender or engine has run for P10. Root approved the static reconstruction plan; execution still requires the next serial window.

From the project root:

```text
python asset_sources/v3/clinic_ground_transition/p10/run_asset.py build
```

CPU2, own process tree limited to 240 seconds. Expected native build/bake plus two fixed-camera views: approximately 120–180 seconds. There is no GLB or runtime write. A failure stops the single run and retains the geometry/log checkpoint.

The prepared code uses one closed XZ height field with explicit three-channel bed and bank constraint lines. It preserves the 6×2.4m connection, outer Y0 seam and structural bottom Y−0.18. Flat areas are sparse; bank breaks receive purposeful density. Coarse-stone clusters are unequal by route and sit on the **constructed triangle BVH**, rather than on a guessed analytic height. The original fracture aggregate recipe is retained, with the new shoulder kept low enough to expose the broken face.

The lightweight analytical design sample is **not a mesh validation**: it proposes −93.27mm to +0.68mm soil heights, nominal relative channel depths 39.11–66.30mm, and maximum wet control 0.88. The authorized run will measure actual triangle sections, perimeter and volume before rendering. The fixed 7,638-triangle comparison has been removed; actual counts are reported against the approximate 8k budget.

Soil and concrete top receive explicit separate atlas regions; hidden/bottom surfaces receive less area. Soil source maps retain real 2.5m / 2m scale. The six original source images are never edited. The final maps are native BaseColor / ORM / Normal, with real coarse-contact AO kept separate from albedo and with a standard glTF material retained for a later authorized export.

Expected outputs: editable source, UV checkpoint, baked/reopened source, actual geometry and section reports, 2K maps, `evidence/transition_source_p10.png`, `evidence/transition_contact_close_p10.png`. These are offline source previews. Root still decides art acceptance and later actual Godot collision/game-camera validation.

Static syntax was checked. The existing local P7 side-study call demonstrates the same `delaunay_2d_cdt(coords, edges, faces, 1, epsilon, True)` API signature. The official current API page was requested, but the web tool returned HTTP 402; no successful reading of that page is claimed. Unlike that old YZ repair, P10 operates on a simple non-folding XZ domain and rebuilds the whole soil surface; it does not inherit the rejected 3D seam boundary.
