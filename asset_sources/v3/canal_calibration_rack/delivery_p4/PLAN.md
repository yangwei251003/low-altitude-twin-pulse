# P4 candidate delivery — static preparation

Root accepted the actual P4 tread shape for candidate baking/export, not final game art. Retain the P4 editable high source and exact P3 low mesh. All work remains in this directory; root owns runtime placement and collision.

## Delivery contract

- Ground-centred identity root `CalibrationRack`, two identity meshes: `DeckSurface` = 944 triangles, `StructureAndHardware` = 3,796; total 4,740. No collision, lights, cameras, rig, animation or scene background in GLB.
- Bounds X/Z ±1.2 m, Y 0…0.32 m, Godot world placement later at `(6.6,0,6)`. Existing conservative box collider/RID remains root-owned.
- Two opaque metallic/roughness materials. Deck: 2K BaseColor / ORM / tangent +Y Normal. Structure: 1K equivalents. Shared source maps retain original bytes/licences. ORM R is neutral 1, no new AO claim.
- Standard glTF Principled output only. Procedural source colour/roughness/metalness is baked via emission without lighting. Normal uses actual P4 plate/rib geometry plus its fine surface normal. Each plate projects only the matching high plate and rib mesh, cage 6 mm / max ray 15 mm. Other structure self-bakes its actual original bevel normals and fine source shader.
- Deck primary top UV uses four panel rectangles with 20.48 px gutters, approximately 955 × 845–863 px/m; original continuous source UVs preserve the paint alignment. Pocket, side and bottom use a separate lower strip with a larger relative island margin. Deck bake extension is 2 px, structure extension 6 px. Structure uses its own 1K atlas. All UV source layers/corner attributes survive proxy creation; only DeliveryUV becomes final SurfaceUV. No Generated/Position-based texture is moved for baking.
- Source's variable dielectric specular level is not encoded as an unsupported extra texture. Final material follows standard metallic/roughness response; same-byte Blender and later Godot views must judge any resulting value difference. No promise that source lighting alone predicts the game response.

## Scheduled stages

1. `python -B asset_sources/v3/canal_calibration_rack/delivery_p4/run_stage.py bake` — estimated 90–150 s, hard 180 s, CPU2. Prepare exact proxies and UV, save `prepared_bake.blend`, bake six images with per-image checkpoint, save `bake_complete.blend`. ERROR or zero UV stops.
2. `.../run_stage.py export` — estimated 10–20 s, hard 90 s. Explicit GLB, actual binary triangle/winding/UV/normals/bounds/matrices/material/channel/image-byte readback. Source normals are also checked against the installed exporter round-four-decimal rule; raw error remains reported.
3. `.../run_stage.py preview` — estimated 70–90 s, hard 120 s. Reimport the unchanged GLB, verify actual mesh triangles and linked PBR, render the original P4 camera/light. Root and maker must inspect the PNG before claiming visual success.

Runner uses existing dev.execute_command hidden private Windows Job, stops on failure and does not automatically schedule another stage. Root must grant the engine slot. Current files have only static Python syntax checks; none of these stages has run.

## Editable/source dependencies

Approved source: `../p4/preview_20261020_035045_756760/calibration_rack_p4_editable.blend`, SHA256 `a7d48c4b46fca78b9cc5bbea7448d4d630b03aef64ea195b47e6c86421eb73fc`. Contains the original 51 low pieces plus four high plate copies/four rib meshes. Input images are copied byte-for-byte into `source_inputs/` before changing save paths and actual pixels are read. Reopened delivery paths are tested; glTF embeds all six native baked images.

Material sources: approved native-imagegen paint atlas `references/v3/production/clinic_pump_shell/material_atlas_v2.png`; ambientCG Metal012 CC0 Color/Roughness/Metalness/NormalGL. Full source provenance remains in `../p3/input_contract.json` and `asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json`. No new generated image or external download.

Known visual residuals retained for actual-camera review: steel is more uniform/clean than reference, some paint-edge chips look rounded. Do not reopen offline colour iterations without actual evidence.
