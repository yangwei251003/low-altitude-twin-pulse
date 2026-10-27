# P5 — directed material zones and broken-edge aggregate

Status: plan approved by root; native surface reference generated, Blender execution awaits its serial window. No production runtime or layout changes.

## Preserve

- 6 m X width, ≤2.4 m outward +Z depth, join-edge-centered origin. Existing outer footprint and its Y0 perimeter remain exact. Closed buried support bottom −0.18 m, visible maximum +0.03 m.
- Three concrete remnants and two actual narrow cross joints. Plain 10 mm and legacy-P2 20 mm joining adapters. No additional coplanar skin.
- Editable originals, two merged visual groups sharing one baked material and three maps; independent named CollisionSurface, no automatic engine collision suffix. Export only after source review.

## Purposeful differences from P4

1. Replace 24 isolated chips with approximately 30–36 partly embedded angular aggregate pieces (3–7 cm) at the broken face, and 14–18 fallen fragments (7–16 cm) in four unequal break-edge clusters. The count is a ceiling/working allocation, not a placement quota. Distinct diameters, thin irregular facets and attachment into the fracture stop the result reading as beads. A handful of fragments may extend into a bank, never fill each channel evenly.
2. Keep one shared terrain surface. Three unequal primary channels and three subordinate branches drive both the actual shallow relief and the material weights. Main continuous fine-silt beds are about 0.16–0.35 m wide, branches narrower; lateral gravel banks/low sediment shoulders are separate zones. Relief remains 1–3 cm and blends to the unchanged outer Y0 perimeter. No floating ribbon geometry and no sharp longitudinal trench step.
3. New native imagegen `surface_atlas_v2.png` supplies fine silt (left) and sparse compacted gravel (right). Keep the old concrete quadrant. Map silt in along/across-channel coordinates, gravel in metric ground coordinates; the same geometric channel data supplies blending. Wet darkening is secondary. Suppress high-frequency white-speckle contrast and bump inside silt, retain broad sediment streaks. Image shading is not geometric depth and must not be converted directly into displacement.
4. The closed below-ground skirt is retained. Its standalone exposed cutaway appearance is not evidence of an actual above-ground wall. Root's integration must cut the old ground to the delivered footprint, maintain a real Y0 join, and judge the new visible silhouette in context. No camera/lighting trick is used to declare this issue solved.

## Budget and checks

- Current P4: 5,346 visual triangles. P5 planning target 6.5–7.5k, maximum 8k per adapter, not achieved/verified yet. Reuse terrain resolution; add medium-scale fragments, not model every grain.
- Coarse traversable surface ≤1.8k triangles per adapter, derived from actual ground and concrete tops; include every fragment protruding ≥3 cm above local ground. Main terrain/collision vertical discrepancy and exact perimeter are rechecked. Small omitted gravel is documented.
- Verify actual closed component topology/normals, no floating or fully hidden fragments, no visible coplanar overlays, bounds, seam dimensions, UV/color spaces, native bake and actual source reopening. Same camera first. Acceptance is readable fracture aggregate, continuous silt runnels/taper and distinct gravel banks; triangle/check counts are not visual approval.
- Planned single source/bake/preview run CPU2, ≤180 s hard timeout. No Blender run until root grants the serial window; no GLB in this initial source-review round.

## Material-source limits and documentation

`surface_atlas_v2.png` is 1774×887, original native bytes, SHA256 `4cb682cc931a667c2bacaf06bb0c7cdb17fb05aadd227520af3e5f870af72d67`. Two 887² zones, not a 2k source. Its right zone still contains a few over-large and shaded chips; use smaller metric coverage and restrained color contribution, no claim of seamlessness or complete PBR.

Recovery reused route `5e455d78-37b2-423b-b660-0cc3185eae49`. Official Blender search-index documentation distinguishes bump (normal perturbation) from actual displacement; complete page fetch returned 402, so no claim that full pages were read. The existing native Blender pipeline is adequate; no new tools installed. Sources: [Blender displacement](https://docs.blender.org/manual/en/latest/render/materials/components/displacement.html), [Blender 5.2 Bump](https://docs.blender.org/manual/id/5.2/render/shader_nodes/displacement/bump.html).
