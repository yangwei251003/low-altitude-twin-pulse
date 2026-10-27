# P13 source silhouette study — not accepted

One CPU-only Blender 5.2.1 run completed with exit 0 on 2026-10-18, producing `p13-basic-readonly-bridge-assembly.png` at 1000×750 and 8 samples. This is an **offline basic-material assembly**, not a game screenshot or GLB readback. The frozen production bridge is imported read-only at local Godot translation `(24.5,0,0)`; the P12 camera transform and framing are unchanged.

## Method and scope

The existing P12 rock is deformed in its current topology: X/Z remain fixed, while Y above 0.55 m is scaled by a strictly positive, position-dependent factor. Three unequal oblique ridges form lower notches. X≥3.5, including the final 1 m bridge support strip and X=4.5 interface, is exactly unchanged. No voxel rebuild, Boolean, added triangles, textures, bake, GLB or runtime replacement occurred.

The inherited diagnostic source still contains 869,522 triangles in five editable meshes. Its density is temporarily retained for judging shape, not accepted as a runtime budget. Existing microscopic coplanar issues remain unresolved. Edge closure and signed volume are recorded separately from triangle self-intersection; this run does not establish full geometric validity.

## Actual result and self-review

The image was opened and reviewed. The previously continuous broad upper slab is reduced, but the surviving bridge-side strip still reads as a straight sloping edge. More seriously, the high root develops a rolled/folded lump. The measured maximum root displacement is **1.599995 m**: the source-height mask selected too broad a proximal region for what was intended as local burial. This is not an acceptable repair of two short cut ends.

The distal fork vertices selected by source Y>1.67 do remain unchanged, but that narrow statement does **not** imply the main root silhouette was adequately preserved. The image is therefore not approved for material production. No additional automatic revision or render was started after this finding.

The useful retained evidence is: final-metre vertex displacement 0; 15 top and 25 interface-side rays retained; positive continuous vertical derivative minimum 0.317265; no boundary/nonmanifold edges in the two edited meshes; frozen source and production bridge SHA unchanged. These do not override the visual failure.

If a next local correction is authorized, use the actual cut-cap connected neighborhood and a much tighter displacement limit rather than a broad source-height mask. Preserve the natural proximal trunk; the surrounding stone should accommodate it instead of lowering the root to match a depressed stone surface. The interface itself should remain unchanged.

## Files

- `build_p13_form.py`: editable, reproducible source; this version retains the failed broad root influence mask for traceability.
- `shore_root_t03a_p13_basic.blend`: separate source without the assembled bridge; SHA256 `ff3197c90c49f9a467e9c48470e880e718e195631d6ce71b9a68b026440b505c`.
- `p13_basic_assembly.blend`: the read-only bridge assembly scene.
- `p13-basic-readonly-bridge-assembly.png`: reviewed image; SHA256 `3966f958656a1cb5f14aaa67556230d3c26c4a77e1bb615b6b4e458c54d098d7`.
- `p13_form_report.json` and `build-p13-form.log`: actual numerical observations and exit evidence. A successful process exit means the script ran, not that the art passed.
