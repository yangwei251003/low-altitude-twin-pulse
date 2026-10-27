# P7 prepared — not executed

P6 is frozen and rejected. This directory is a new source-only correction. No runtime asset or world change. Reuses route `5e455d78-37b2-423b-b660-0cc3185eae49`.

Entry: `python asset_sources/v3/clinic_ground_transition/p7/run_asset.py build` from the project root. Runner owns one CPU2 Blender process tree, 180-second hard timeout. Expected roughly 90–140 seconds including two images, subject to actual AO bake time. No engine may run concurrently. On any failure retain the attempted source/log and stop; no automatic second version.

Changes from P6:

- Preserve 6×2.4m outer join and Y0 boundary. Keep concrete fracture strata, 13-row soil topology, count/triangulation of low stones, and 760 high-only small stones. Target remains near 7,638 runtime triangles, pending actual readback.
- Medium stone authored thickness is now 5.0–8.5cm and large fragment thickness 8.0–12.5cm, with varied tilt and nonuniform facets. Their centers are at soil +10% thickness instead of soil −10%. These are construction inputs, not claims of measured exposed height. The common upper limit still clamps whole pieces downward without flattening them. Actual per-piece exposure/support must be measured after construction.
- The six routes no longer share three identical empty intervals. Bank placement covers continuous path coordinates with route-dependent density variation, with irregular gaps and low-density silt beds. The quiet soil remains; its broad real rills are deepened while the bank shoulder varies by position. No new micrograin carpet.
- Four subdued gray-brown material families have coherent centimeter-scale rock variation, not constant pale gray polygon caps. Geometric facets and inclination carry volume, not inflated normal strength.
- Retain the tested 3.5cm cage / 9cm projection reach. Native Cycles high-to-low albedo and tangent normal remain. Bake actual short-range contact occlusion through an Ambient Occlusion node (8cm distance, 16 samples, Only Local) on a joined high source containing the main ground and all stones. Only Local excludes the separate low target and studio floor; it still sees the ground/stone interfaces within that source object.
- Native shader bake packs contact AO into ORM R, preserves roughness G / metallic B, and leaves the original BaseColor PNG unshadowed. Save raw AO and pre-AO ORM as diagnostic source maps; eventual runtime still uses three maps.
- Standard export material keeps plain BaseColor and `glTF Material Output.Occlusion` on ORM R. A separate preview material uses the same R map through node multiplication. This approximates contact readability in Blender; exact AO lighting equivalence with glTF/Godot is explicitly not claimed. No GLB is produced in this stage.

Outputs planned: editable geometry, UV checkpoint, baked source, four native bake stages, full unchanged camera image and one nearer image with the same oblique direction. Actual image review must assess visible stone sidewalls and contacts, three legible channels, mixed-width banks and any black self-occlusion artifacts. Numeric checks do not pass art.

Official references consulted: [AO node API](https://docs.blender.org/api/main/bpy.types.ShaderNodeAmbientOcclusion.html), [glTF AO material contract](https://docs.blender.org/manual/en/latest/addons/scene_gltf2.html). The latter explicitly says Blender has no node arrangement with exactly the same AO response as glTF; hence the distinct preview/export materials. These documents do not establish that this candidate will look correct.
