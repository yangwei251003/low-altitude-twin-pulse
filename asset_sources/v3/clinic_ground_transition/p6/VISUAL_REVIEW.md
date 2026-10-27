# P6 — REJECTED_ART / source-only

Parent and author actually viewed `evidence/transition_source_p6.png` against approved reference V2. The two-dimensional distribution and darker fracture layer improve P5, but the medium stones look like pale paper chips, the largest fragments read as flat lids, and the three rills are weak. No GLB or game acceptance.

Blender PID 40100 naturally exited 0 in 59.090 seconds, CPU 2. Low mesh: 7,638 triangles / 159 editable parts. High-only mesh: 760 small stones / 15,200 triangles, retained hidden in editable source and excluded from runtime proxy. The 164 source geometry checks passed; this does not certify aesthetics, self-intersection, game physics or a final collision mesh.

## Evidence-based diagnosis (no subsequent Blender run)

- Actual saved material SDNA links in `actual_material_graph.json`: BakeUV feeds all maps; Non-Color normal goes to NormalMap, strength 1, BakeUV tangent basis, then Principled Normal. Emission is zero. This is not a lost shader connection.
- `flat_stone_diagnosis.json` traces saved mesh barycentric BakeUV into unmodified PNGs. Thirteen small high-poly stones sampled at five positions each yield approximately 2.2–35.2° tangent-normal deviations. Whole-atlas neutral normal pixels fell from 97.862% in P5 to 92.291% in P6. These percentages include unused UV background, so they are not gravel coverage metrics.
- The 100 medium stones are 6.5–13.5 cm across but protrude only 0.96–2.15 cm above the placement surface, median 1.57 cm. The 12 larger 13.5–22.8 cm fragments expose roughly 1.5–3.0 cm over actual saved soil triangles. Named source positions are decoded in `actual_stone_geometry.json`. Their flattened profile is a modeling error, not a reason to tune cage distances blindly.
- Successful source bake used selected-to-active with 3.5 cm cage extrusion / 9 cm max ray distance. The local normal samples prove projection worked there; this does not prove every texel. Normal transfer records orientation, not real height or physical cast shadows.
- AO was never baked: ORM source R was constant 1, and sampled channel/stone pixels are 255. The final preview material also does not use R. Hence the high-poly stones have no retained local contact occlusion. The four almost constant gray stone colors additionally make the projected shapes read as decals.
- Rill coordinates and roughness survive: main mid-channel RGB samples are about (97,88,77), (97,88,78), (100,91,79), versus adjacent dry values near (110–112,101–102,90–91); roughness is 0.647–0.663 versus 0.878. The signal exists, but in this fixed image it is insufficiently legible. This is not permission to just darken the entire surface.

The native normal conventions agree with the [Blender normal-map manual](https://docs.blender.org/manual/en/latest/render/shader_nodes/displacement/normal_map.html) and [NormalMap API](https://docs.blender.org/api/main/bpy.types.ShaderNodeNormalMap.html): matching UVs, Non-Color and tangent/OpenGL convention. [Cycles baking](https://docs.blender.org/manual/id/5.0/render/cycles/baking.html) distinguishes selected-to-active normal transfer and AO baking. Search-index documentation was consulted; no new tool installation.

## Limits / next bounded correction

P6 remains frozen. P7 is separately authorized to restore genuine thickness and modest tilt to medium/large fragments, add restrained brown-gray stone variation, and bake actual short-range contact AO into ORM R while keeping albedo free of painted lighting. Geometry is still responsible for silhouette, large relief and real collision. The outer Y0 interface remains unchanged; the final coarse collision surface has not yet been delivered or tested. The raw projected ellipse area sum in `sediment_distribution.json` is only an upper bound before overlap/burial, not a measured visible surface fraction.

No geometry, maps or render were altered after the single P6 run. Diagnostic files are additive reads. No P7 render has run as part of this review.

The supplementary per-object SDNA reader first reused global DATA addresses and incorrectly read the studio floor array for stones; the diagnostic stopped with an empty sample list. Its raw output/log are preserved as `diagnostic_failed_global_addresses.json` and `diagnosis.stderr.log`. The corrected reader resolves each mesh's adjacent DATA blocks, exactly as the previously successful proxy reader does. `diagnosis-final.stdout.log` and the final JSON use the named source mesh arrays. The material-link and BakeProxy/PNG conclusions did not depend on that failed reader.
