# Inspection pit — source-faithful candidate delivery

2026-10-20. Root and maker viewed the final source and same-byte GLB reimport at the original camera. Root accepted the object for Godot candidate review and authorized a byte-identical copy to `assets/v3/candidates/inspection_pit/inspection_pit.glb`. No Godot render, gameplay or whole-area art acceptance is claimed here. Root owns the wrapper, anchor placement and physical ground/pit.

## Delivered contract

GLB: `inspection_pit.glb`, **14,792,084 bytes**, SHA256 `0e977a7e93df47015ba58ebde01e0a39efbb53c40aba8ed66474e96877f1b30f`.

Identity root `InspectionPit`; three identity meshes and three opaque standard PBR materials:

| Mesh | Triangles | Material |
| --- | ---: | --- |
| `WallConcrete` | 3,280 | `InspectionPit_WallConcrete_PBR` |
| `FloorAndRamp` | 2,480 | `InspectionPit_FloorAndRamp_PBR` |
| `Hardware` | 13,880 | `InspectionPit_Hardware_PBR` |

All **19,640 original triangles** remain. Local AABB is `[-4.375,-2.484999895095825,-4.75]` to `[4.375,0.0009999999310821295,4.75]`. Root places the identity root at world `(-17.625,0,5.75)`. The slight lower slab depth and 1 mm paint relief are actual source geometry, not an alteration to the original gameplay collider. The GLB contains no collision, light, camera, studio, animation or rig.

Wall and floor/ramp each use 2K BaseColor/ORM/Normal; hardware uses the same three channels at 1K. Nine native PNGs total **12,788,837 bytes**, all embedded as exact original PNG byte streams. BaseColor is sRGB; ORM and tangent +Y Normal are Non-Color. ORM R=1 is neutral, G is roughness, B metallic. There is no AO bake or painted lighting claim.

## Editable source and source identity

`inspection_pit_editable.blend` preserves all 224 editable pieces and original eight materials. Two original image dependencies are supplied under `source_inputs/`, with relative paths and packed copies verified after reopening. SHA256 is `c2a2157a8ef1f3a9c377f03ffc078623639b9c827be4b5833db0716858d1d243`.

`inspection_pit_delivery.blend` is the separate three-mesh baked scene with the review camera/studio; nine used textures are in `textures/`. Only the selected asset root/meshes were exported. SHA256 is `49552d64a4463af669e814efa29008f7ace7d5697f76efcde0cba5e2ad977ced`.

Root's frozen authority remains `../p1/preview_20261020_042716_f10932/inspection_pit_editable.blend`, SHA256 `1d3df8bc07ffdd9894f9e15cc81b9cead195ed10b4a616ad607e801b62367346`. It includes the corrected outward ramp-side winding and the 12 mm inset backing end/bottom faces. Neither it nor Root's build/wrapper was modified. The previous preview is not used as the delivery input.

## Verification and observed limits

Source positions, triangle winding and material identity survived the evaluated proxy conversion; all four source UV layers were preserved before creating DeliveryUV. Actual pixel-centre occupied atlas fractions are wall 78.843%, floor/ramp 72.199%, hardware 13.893%. Main wall density is about 150 px/m, main floor/ramp about 203 px/m; numerous small hardware islands account for its lower packing occupancy. Distinct charts have an 8 px gap and native extension is 2 px. No source geometry was removed to improve statistics.

Raw binary verification reports zero position error, UV maximum 2.98e−8, source-normal raw maximum 6.37e−5 and exporter-quantization-adjusted maximum 1.19e−7. Actual GLB reimport independently matches the triangle multisets and winding, loads nine packed images and binds all required PBR inputs. See `raw_glb_report.json` and `preview_report.json`.

Normal maps are almost neutral: 99.858–99.979% of occupied pixels equal RGB(128,128,255), with RG spanning 126–129. The original material has a shallow procedural Bump; source bevels, ramp recesses, seams and metal parts remain geometry. The normal texture is not presented as measured material relief, nor was wall color converted into a fabricated height map. The actual reimport image retains the source appearance at the tested view. See `ACTUAL_REVIEW.md`; the final game view still decides whether finer surface response is needed.

## Actual stages

| Stage | PID | Wall seconds | Hard seconds | Result |
| --- | ---: | ---: | ---: | --- |
| Prepare | 36832 | 8.016 | 60 | Natural exit 0 |
| Bake | 20444 | 69.094 | 240 | Natural exit 0 |
| Export | 32856 | 7.485 | 90 | Natural exit 0 |
| Same-byte reimport/render | 35540 | 34.890 | 120 | Natural exit 0 |

Every stage used CPU2 and the existing hidden private Windows Job runner, with zero ERROR lines and zero owned residual processes. Each successful map had a checkpoint. Logs and selected process reports are included; the engine window has been returned. `PLAN.md` and the stage reports retain their historical status text; this README states the completed candidate-delivery status.

`manifest.json` is the compact submission inventory: editable source and its two original images, nine maps, delivery blend, GLB, scripts, actual reimport image, selected reports/process logs, source provenance, and Root's final source/build/image/report. Large prepared/checkpoint/bake blends, `.blend1`, repeated `input_snapshot/` trees and full per-triangle JSON arrays remain recoverable locally but are excluded from this selection. The manifest is verified by rereading every listed byte count and SHA.

Both original source images are approved native-imagegen material references reused from the ground and revetment assets. Their original bytes, prompt/provenance copies and dimensions are preserved. They are neither photographs of this game nor complete measured PBR sets. All actual runtime roughness/metalness/normal outputs came from the supplied source shader. No new image generation, downloads or material changes were introduced during delivery.

To reproduce, use `run_stage.py prepare|bake|export|preview` in a new authorized delivery workspace with the frozen input contract; successful outputs here are frozen and the scripts refuse accidental overwrites. Do not start a stage without Root's exclusive engine window.
