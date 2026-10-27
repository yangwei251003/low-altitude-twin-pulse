# 1.3m middle crop — offline delivery complete

Actual execution completed and the parent personally viewed the same-byte GLB reimport. Approved to proceed to Godot integration; not final game/art acceptance. Candidate `i2_canal_revetment_1p3.glb`: SHA256 `bad2a55f2a24117ad31bb5ed071e0cd8501fea5894f1a3986a3c11fa444649b0`, 5,018,928 bytes, 1,172 triangles, 1 mesh / 1 material. Root and mesh are identity. Four editable pieces survive, and the original 4m delivery bytes are unchanged.

First build failed before baking because rounded float32 coordinates were used as cut-vertex identity (`KeyError:153`). Its script/log/manifest are frozen in `run-build-20261019_205027_da8976/`. The repair keys intersections by original edge IDs and cut plane, computing each shared point once; each corner keeps its own interpolated UV/attributes/normals. Actual Blender diagnostic found 12 edges whose old rounded keys split, with maximum 0.238µm arithmetic difference. No topology or UV gate was relaxed. The two caps retain 89 and 83 actual boundary segments. Positive closed-body volume is 1.272383m³; 25 front/waterline rays differ from the original by at most 0.0596µm. This is scoped topology/ray evidence, not a generic exhaustive self-intersection claim.

Successful private process stages: build PID26568 / 3.406s; bake PID2060 / 12.391s; export PID35308 / 2.657s; preview PID34316 / 60.641s. All naturally exited 0, had no logged errors and left no owned processes. Source UV density is unchanged; actual baked front area-weighted density is 556.4px/m. Normal PNG is exactly neutral (128,128,255), consistent with retained geometry and no invented image-height conversion.

The actual reimport image `same_byte_reimport/01-reference-oblique.png` was viewed by the producing agent and root. It preserves dry/wet layers, waterline, embedded fixing and exposed top/end material. Missing original side seams and repair are expected: they lie outside the genuine middle crop. Adjacent 4m-to-short seam appearance and actual game lighting remain integration checks. See `delivery_summary.json`, `visual_review.md` and `manifest.json` for frozen evidence.

## Historical preparation checkpoint

This is a true middle crop of the frozen 4m editable delivery. It is not an X scale of the original. No Blender process has been run for this directory at this preparation checkpoint. The parent has actually viewed the 4m same-byte Blender reimport and approved proceeding to game integration; this does not yet constitute a Godot visual result for either length.

## Frozen input and output contract

- Input: `../delivery_p4/i2_canal_revetment_editable.blend`, SHA256 `2e14f59de71971596226af0ecf2c2d59ea4b8e6bffea60c07d2a0308ac563b71`.
- Output: `i2_canal_revetment_1p3.glb`; identity root `I2CanalRevetment`, identity child mesh `RevetmentSurface`, one material `I2Revetment_PBR`.
- Godot local bounds: X `[-0.65, 0.65]`, Y `[-2.8, 0]`, Z `[-0.35, 0]`; origin top-front middle, +Z faces water. No collision, lights, camera, animation or runtime file writes.
- Four editable pieces survive the crop: closed concrete body and the three parts of the central fixing. The other fixing, right repair and both original construction seams lie outside this true middle segment and are intentionally absent. No replacement fake seam is added.

## Geometry and UV method

Clip original evaluated triangles by the two X planes, interpolating their original corner UVs, attributes and normals. Intersection topology uses original source edge IDs plus the cut plane, not rounded position matching. Close each actual cut loop using its original boundary segments; require opposite boundary winding and a valid star-shaped cap before accepting the cap fan. All resulting edges must have exactly two opposite incidences. The build checks signed volume, exact bounds and 25 original-versus-crop front rays including Y=-1.2. Native unwrap must yield finite, nonzero UV triangles; a failure saves the actual failed mesh and triangle details and stops.

The original front image keeps horizontal U `[0.3375, 0.6625]` and unchanged vertical density. Each new end samples a 0.35m adjacent front strip with unchanged height/waterline. The top remains the original material/UV. This preserves front-to-end continuity, not an assertion of seamless texture continuation across every rear top/end edge.

The two original source images are copied without pixel changes, their actual pixels and SHA checked before saving, and the saved editable source is reopened for path/pixel validation. Three native **2048²** maps are planned. The initial 1K cost estimate has been superseded: 2K avoids reducing density across the retained 3.64m² front plus back and new end UV allocation; actual front pixels/metre will be reported, not inferred as measured now. Baking does not increase the original input image detail.

BaseColor is an albedo-only emission bake. ORM is Non-Color R=1, G=roughness, B=metallic: no AO claim. Normal is the actual source tangent response; no pore-color-to-height conversion. Neutral normals are acceptable when the real retained geometry contains the surface shape.

## Sequential execution after the parent's explicit engine window

Run from `.`:

```text
python -B asset_sources/v3/i2_canal_revetment/delivery_short_1p3/run_delivery.py --stage build --run
python -B asset_sources/v3/i2_canal_revetment/delivery_short_1p3/run_delivery.py --stage bake --run
python -B asset_sources/v3/i2_canal_revetment/delivery_short_1p3/run_delivery.py --stage export --run
python -B asset_sources/v3/i2_canal_revetment/delivery_short_1p3/run_delivery.py --stage preview --run
```

CPU 2 throughout. Estimates: build 5–15s, bake 10–25s, export 3–8s, actual-GLB reimport/render 50–80s; total roughly 70–130s. Independent private-process-tree hard limits: 60 / 180 / 90 / 180 seconds. Inspect each result before the next command; a logged ERROR, missing image, invalid geometry/UV or nonzero exit stops this delivery. No second build automatically follows a failure.

The binary check compares actual GLB triangle multiplicity/winding, positions, corner UVs, exporter-normal mapping, node matrices, bounds and three embedded PNG bytes to the exact cropped source. The final image is rendered from this same GLB, under the original P4 camera and lighting. The image must be viewed before claiming offline visual acceptance. Godot, terrain collisions and complete 13.3m integration remain the parent's independent validation.
