# Recovery sample — first actual high/low comparison

**Status: method has visible medium-scale relief, but low bake is visually rejected. No full-asset or game approval.** Both original 1280×1100 PNGs were viewed, followed by the untouched Normal and ORM PNGs. No second strength, geometry pass, bake, or render was started after this result.

## Actual execution

- Stage A: Blender PID 35868, natural exit 0, 11.469 s; private 90 s limit. Six aggregate contacts computed together before acceptance, and `aggregate_diagnostic.blend` saved before the contact assertion. Actual exposure 3.600–7.000 mm, burial 13.181–27.238 mm; original heights preserved within 1e−9 m. The 0.5 mm minimum is an anti-total-burial check only.
- High full source 146,026 triangles, low full source 9,578 triangles. Each checked solid has no nonmanifold edges and positive volume. Intentional aggregate/concrete overlap is retained; arbitrary global self-intersection was not tested.
- Four actual cross sections span 52.81–62.99 mm; high/low maximum sampled vertical difference is 2.474 mm. This is measured geometry, not measured original-scan height and not an aesthetic pass threshold.
- Stage B: Blender PID 36288, natural exit 0, 114.969 s; private 240 s limit. Native 1024² BaseColor/Normal/ORM baked, checkpoint and preview sources reopened, six original PNGs and three baked PNGs resolved and actual pixels read. Original A checkpoint SHA stayed identical. No logged ERROR or image-load failure.
- Source A checkpoint SHA: `73f64b85d4b4ac290743c4285d3f3220b65beef21a50068c569cece862a122a0`. B preview blend SHA: `65fad833d5042b515fe4aa36ddbd11da520c1ed9a730c781337e29143d018022`.

## Actual visual findings

1. **Useful evidence:** the lower-left scanning patch has continuous real rock relief and contact transitions in the high image; the low geometry retains its main relief. This is a clearer material/shape relation than earlier flat colored gravel pieces. Displace is actual vertex geometry; the original full scan macro NormalGL remains disconnected to avoid expressing its slope twice.
2. **Low transfer failure:** the low image adds dark flecks and broken black bands along the outer top rim, side corners, and the fallen chip's contact area. These are absent from the high source view. The raw baked Normal image has strong green/pink orientation patches around several ground/side UV boundaries. A neighboring-face cage hit or tangent/sharp-boundary mismatch is plausible, but this run does not uniquely distinguish them. No claim that the cage is validated.
3. **Source UV defect:** the soil block's vertical closure faces have stretched vertical texture bands in both images. `source_uv()` forces horizontal RockScanUV for every face with `soil=True`; SoilScanUV is horizontal throughout. A vertical wall collapses one texture dimension. This is a source mapping error, not solved by the bake. It should be isolated from the actual upper displaced surface in any authorized later correction.
4. **Remaining art gap:** the broken concrete still reads as a relatively clean cut, and only a few small aggregate tips are obvious. The pale sand/concrete range and short scattered chip do not yet produce the reference's stronger fracture and sediment composition. This 0.9m method sample does not prove whole 6m composition, default game readability, or performance.

## Checks that must not be overstated

Every low triangle centroid avoided the magenta sentinel, but this did **not** catch rim artifacts or wrong normal directions. Raw baked normal channel range includes R 0..0.9843, G 0.00784..1, B 0.01176..1; complete min/max includes hidden/embedded faces and does not localize a visible fault. ORM AO is 0..1, roughness 0.50588..0.85490, metal 0. These ranges do not certify clean contact shading. Real rendered evidence overrides the zero sentinel count.

## Preserved evidence

- `build_20261019_224648_006150`: first local-import failure, exact pre-fix input snapshot.
- `build_20261019_225030_169314`: second stone almost wholly buried, exact measured values and input snapshot. No blend was saved before that old assertion.
- `build_20261019_225756_781967`: corrected actual contacts, early diagnostic blend, geometry/UV/sections/image verification, editable checkpoint.
- `bake_preview_20261019_225933_382710`: native maps, reopened preview blend, full original logs, reports, two original PNGs.

No GLB, Godot, runtime/layout, original image edits, new scan resources, or P13/recovery_study modifications. Engine window explicitly returned after natural Stage B exit; no additional engine work is planned without parent direction.
