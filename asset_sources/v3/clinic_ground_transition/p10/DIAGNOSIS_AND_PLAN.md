# P9 actual section diagnosis / proposed P10 reconstruction

**Static preparation only. No P10 Blender, Godot, bake, GLB or runtime change.** P9 remains frozen and rejected. Route `5e455d78-37b2-423b-b660-0cc3185eae49` is reused. Root explicitly removed the intermediate restriction requiring new terrain to equal P7's low mesh; the 6×2.4m connection and usable collision remain the real requirements.

## What was measured

The actual saved P9 `baked_source.blend` SHA256 is `f17113eb29f0c32157a626e36fef6cf86273c9086617dd31ed19f996348aa626`. The read-only SDNA extractor obtains its joined, triangulated BakeProxy. The soil is its largest connected component: 1,237 vertices, 1,920 upward surface triangles, projected area 9.292214m². The full closed soil has 2,470 triangles. No procedural reconstruction was substituted for the saved mesh.

Twelve section planes cross the three real main route paths at 18%, 38%, 62% and 82% of arc length. `p9_cross_sections.json` retains actual triangle intersections, coordinates, heights and triangle indices. `p9_cross_sections.csv` contains regular plot samples. The PNG is a diagnostic chart with independent axes, not a rendered or edited asset image.

Depth below means the difference between the lowest actual triangle point inside the existing bank offsets and the straight chord joining those actual bank heights. It removes the background cross-slope. Negative/positive bank refers to the recorded cross normal, not screen left/right.

| Main channel | Along path | Bottom Y, mm | Negative bank Y, mm | Positive bank Y, mm | Relative depth, mm |
|---|---:|---:|---:|---:|---:|
| 1 | 18% | −60.88 | −40.94 | −43.93 | 18.63 |
| 1 | 38% | −56.98 | −39.44 | −37.95 | 18.38 |
| 1 | 62% | −45.35 | −20.70 | −28.07 | 21.54 |
| 1 | 82% | −37.69 | −13.40 | −11.73 | 25.19 |
| 2 | 18% | −68.18 | −47.59 | −47.97 | 20.40 |
| 2 | 38% | −56.63 | −46.70 | −39.42 | 13.26 |
| 2 | 62% | −58.01 | −43.29 | −47.63 | 12.13 |
| 2 | 82% | −49.54 | −26.96 | −25.27 | 23.38 |
| 3 | 18% | −54.48 | −34.49 | −38.05 | 17.92 |
| 3 | 38% | −45.20 | −26.40 | −31.61 | 15.93 |
| 3 | 62% | −36.30 | −15.98 | −20.78 | 17.59 |
| 3 | 82% | −26.52 | −7.80 | −7.83 | 18.71 |

The entire soil surface reaches Y−72.08mm, but much of that is the broad inset slope. It is **not** a 72mm channel. Measured local relief is only 12.13–25.19mm. Mesh edge lengths in XZ have median 123mm and maximum 294mm (including diagonals); the regular X step is 75mm. Narrow bed/bank features can have only one or two useful cross samples. The plan therefore changes terrain structure instead of increasing normal strength or darkening the same shallow surface.

## Actual material scale and sampling

Actual soil UV/world-area ratios confirm a 2.5m source repeat: min/median/max 2.4999945 / 2.5000000 / 2.5000050m. The original 2048² scan has a 1.221mm pixel pitch. The final shared 2048² BakeUV atlas allocates only about **198.1 texels/m** to soil, or **5.048mm per baked texel**. The source UV was correct; the final sampling budget is much lower than the source map.

Read-only FFT of the original NormalGL R/G shows 83.58% of Sandy Gravel 02's radial detail power below 1cm wavelength. Rocky Trail has 42.24% below 1cm and 12.68% at 5–15cm, versus Sandy Gravel's 1.24% at 5–15cm. These are frequency measurements, **not stone diameters, coverage rates or a visual acceptance test**. They explain why fine scan detail alone cannot fill the missing medium-scale structure after asset baking. Exact inputs/method/limits are in `texture_world_scale.json`.

## One bounded second material comparison

Only [Rocky Trail](https://polyhaven.com/a/rocky_trail), Amal Kumar / Poly Haven, [CC0](https://polyhaven.com/license), was additionally acquired. Official width: 2m. Three original 2048² Diffuse / OpenGL Normal / Roughness PNGs total 62,177,664 bytes; each official MD5 matches. SHA, exact URL, author and license are in `vendor/polyhaven_rocky_trail/provenance.json`. All three maps were actually viewed. No preview, executable, model or extra material was downloaded; no original image was edited.

This source contains visibly mixed angular particles, larger irregular rock faces and finer infill. It is a more suitable candidate for sediment shoulders than Sandy Gravel 02. It is also dense: full-surface use would erase the low-density beds again. Keep the P9 sand as the quieter bed/substrate; use Rocky Trail only in broad, unequal accumulation zones with a gradual transition. No shader or render has yet proved this blend.

## Proposed one-purpose P10 change

1. **Rebuild the actual soil surface around three distinct cross sections.** Retain the concrete connection, overall 6×2.4m footprint, outer Y0 seam and the −0.18m structural bottom. Use explicit bed and shoulder guide lines rather than evaluating a narrow Gaussian on the existing sparse rectangular grid. Start with relative bed-to-shoulder relief around 4–7cm, bed width varying roughly 0.16–0.32m and broad, unequal shoulders. These are initial design dimensions, not new visual pass thresholds. Keep the highest visible surface within the existing +0.03m envelope; the proposed beds remain above the existing −0.18m underside.
2. **Give each route a different deposit structure.** Channel 1 has a broader, broken shoulder on one side and a lower opposite side. Channel 2 accumulates on the outside of its bend rather than parallel bead strings. Channel 3 is wider and finer, with fewer coarse pieces. Retain continuous readable bed space and spread the existing coarse stone budget into purposeful clusters; do not duplicate the same sequence at three outlets. The actual visible top need not remain exactly 7,638 triangles.
3. **Spend mesh density at real bends and bank breaks.** Use a single XZ height field with constrained bed/bank lines and coarse triangles on quieter flats. Proposed allocation: about 1.4k concrete/seal, 2.6–3.0k soil and 3.2–3.6k true coarse stones, aiming near 8k total without flattening rocks to meet a count. The old allocation was 1,408 + 2,470 + 3,760. No high-only 5,000-particle blanket returns. Actual achieved counts will be reported.
4. **Use both scans at their physical scales.** P9 sand stays at 2.5m on low-density beds; Rocky Trail at 2m supplies mixed shoulders. One smooth, width-varying accumulation field must control base color, roughness and normal consistently; avoid a hard picture cutoff. Preserve low color contrast in the bed and use actual terrain slope/contact AO for its shape. Keep one material / BaseColor + ORM + Normal delivery goal. Prioritize visible soil in the atlas; bottom/hidden islands should not consume the same density. Do not simply raise map resolution to preserve microscopic sand.
5. **Respect edge/physics meaning.** The terrain returns smoothly to Y0 at the outer seam. With that fixed perimeter it is an erosion/deposition depression, not a validated continuous hydraulic outlet; no active water-flow claim is added. The new coarse collision must follow actual terrain and include protruding large stones, with a machine-readable footprint, instead of reusing P9/P2 collision evidence.

## Checks for the next authorized single run

- Actual exported/source mesh cross sections again, showing both banks and bed; no claim from source parameters alone.
- Shared edge coverage, closed surfaces, triangle intersections, outer seam height and coarse-stone burial/exposure. No floating particles or independent overlapping coplanar ground layers.
- Actual visual and collision triangle budgets, height extrema and footprint; collision is still subject to root's real Godot validation.
- Actual UV scale, per-region baked density, image spaces and reopened blend paths. Contact AO stays separate from albedo.
- Same full and close cameras. First judge three readable non-identical channels, mixed shoulder versus low-density bed, and soil contact. Technical checks alone do not approve the art.

This document is the requested diagnosis and proposal. No P10 build script or render was executed, and no next engine window is assumed.
