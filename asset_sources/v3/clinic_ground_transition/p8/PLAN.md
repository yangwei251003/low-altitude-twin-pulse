# P8 static preparation — broad mixed sediment, not more narrow strings

Route: `5e455d78-37b2-423b-b660-0cc3185eae49`. Root accepted this bounded plan; Blender remains prohibited until the serial window is explicitly handed over. P7 source and maps are frozen. This is not an executed P8 result.

## Evidence and layout

`p7_coverage.json` measures actual saved P7 triangles, not ellipse sums: 760 fine grains expose 0.3905m² (4.20% of soil); all stones expose 1.0267m² (11.05%). The existing 2.0563m² narrow-bank domain already has 40.43% combined coverage. Root's reference estimate of 35–50% is an artistic comparison, not a calibrated numerical pass threshold.

Keep P7's low mesh, real large-stone thickness, three main channel shapes, boundary, normals and 7,638 triangles. Change only the high-only grain distribution and soil surface authoring. Preserve the old low stones as editable geometry; the additional grains do not enter runtime meshes or collision.

Use a continuous two-dimensional sediment field: main-bank reach varies 0.50–0.70m on each side, branch reach 0.24–0.34m, joining a 0.45–0.70m apron outside the broken concrete. Clip against the real soil and preserve the low-density beds. The planning union is 4.9582m², versus 2.0563m² previously. These dimensions define a support region, not a sharp material border. Density fades at the outer margin and downstream, has broad unequal patches and merges across neighboring banks. No synchronized three-interval placement and no six isolated tubular strips.

Target 5,000 high-only angular grains: 65% diameter 3.8–5.2cm, 25% 2.8–3.8cm, 10% 2.0–2.8cm. Use actual saved soil-height queries for placement and burial, checking that each fragment crosses the supporting surface. Discourage close center overlap and avoid existing large stones; do not stack a floating high-poly carpet. Keep the existing subdued stone palette and varied facet directions.

At P7's empirical exposed-area/raw-ellipse ratio, 3,500 would suggest only 28.3% combined whole-soil coverage; 5,000 suggests 37.5%. Changed overlap and burial can invalidate this extrapolation. Actual exposed union, both whole-soil and deposit-domain denominators, will be reported after construction. Count is a budget, not proof of coverage or quality.

Remove the soil's mirrored 1.5m repeat, which repeats the generated source's broad trowel strokes. Use a single continuous, weak color contribution from the left silt source; preserve the same continuous wet/channel control and roughness response. The actual high-to-low stone bake supplies the sediment detail. No new broad procedural color noise, three painted bands, stronger normal-map factor, or image pixel editing.

## Resources and validation

- High-only geometry approximately 100,000 triangles (5,000 × 20); low runtime remains 7,638. Joined high source is around 108k triangles and remains editable/hidden in source.
- Reuse 2k native BaseColor/ORM/tangent Normal. Keep standard glTF material distinct from Blender preview AO approximation. AO remains real short-range local contact baking; no albedo shadow painting. Avoid artificial stacked particles and examine raw AO on actual UV faces for black bands.
- Keep 3.5cm cage / 9cm reach; do not tune the cage to hide placement defects. Save geometry/UV/map checkpoints before two unchanged-camera renders.
- P7 completed all stages plus two images in 113.8s (maps/reopen by roughly 23s). P8 estimate is 130–180s CPU2, with uncertainty from denser source intersection work. Parent has allowed a future **240s self-process-tree hard timeout**; no engine has been started yet.
- Future bounded command: `python asset_sources/v3/clinic_ground_transition/p8/run_asset.py build`. One full view and one close view, same P7 camera/lighting. No GLB or runtime writes.
- Check exact low source geometry equivalence, actual bounds, high-grain burial/exposure, projection coverage, native map/UV/color-space links, reopened paths and hashes. View both images and specifically judge the connected mixed-grain deposits, visible low-density channel beds, normal/contact appearance and remaining plaster texture. Numeric passes do not establish artistic acceptance.

P7 AO roughness repacking was separately verified: G/B are exact at every covered UV pixel center; changes only occur in padding. This fact does not claim future engine filtering, collision or performance has been tested.
