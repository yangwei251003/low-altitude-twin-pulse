# Shared maintenance-paving delivery — frozen source candidate

Source: frozen P3 `maintenance_paving_p3.blend`, SHA256 `a13c879628d7352d250bb69d1e611d5baefe8d44b800608b270552f1bb468c46`. Root reviewed both P3 source images and approved an engine candidate; final game appearance remains unverified.

Executed 2026-10-19: Blender PID28996, CPU2, natural exit0 in78.141s. Four native shared-atlas channels completed; binary GLB checks **43/43**, then the same bytes were imported and both offline images rendered. Only the Blender6.0 `Material.use_nodes` deprecation warning appears in stderr; no Python exception. Process termination was not needed. The process was verified absent and the window returned to root.

Frozen GLB: `maintenance_paving_variants.glb`, **5,002,844 bytes**, SHA256 **`cbeb42fd6158e0f57c7b12c44740a1a3df482d72d3f1bbbc47d028b89374c60d`**. Actual same-byte images: `evidence/maintenance_single_glb_p3.png` and `evidence/maintenance_eight_tile_glb_p3.png`. Both were visually inspected: geometry, controlled colour peaks and the continuous inspection band survive. The shared 2K atlas visibly softens close-up concrete compared with the author shader; repeating 4m source patches and relatively flat refill finish remain limitations. Do not silently increase texture budget or claim final art approval; root evaluates the default game camera.

## Fixed export contract

One file `maintenance_paving_variants.glb`, root `MaintenancePavingVariants`, eight direct roots `MaintenancePaving_W0` … `MaintenancePaving_E3`. All roots/mesh transforms identity; **all variants coincide locally**. Root integration must select one variant subtree per placement, not display all eight at once.

Each variant uses a local Godot top-centre origin, X[-2.5,2.5], Y[-.18,0], Z[-2,2]. Blender conversion `(X,-Z,Y)`. No pivot, movable part, light, camera, animation or collider is exported. All lids are currently closed visual parts, not interactive doors. Keep the existing conservative Y0 ground collision; do not claim physical drains. The old Y0 visible surface must be cut to the patch footprint, not coplanarly overlaid.

| Variant | Child mesh names / source triangles | Editable source pieces | Proposed world centre X,Z |
|---|---|---:|---|
| W0 | W0_Surface 632; W0_InspectionBand 2388 | 39 | 17,-12 |
| W1 | W1_Surface 808; W1_InspectionBand 2316 | 41 | 17,-8 |
| W2 | W2_Surface 504; W2_InspectionBand 2316 | 39 | 17,-4 |
| W3 | W3_Surface 520; W3_InspectionBand 2484 | 39 | 17,0 |
| E0 | E0_Surface 520 | 12 | 22,-12 |
| E1 | E1_Surface 464 | 12 | 22,-8 |
| E2 | E2_Surface 520 | 12 | 22,-4 |
| E3 | E3_Surface 808 | 14 | 22,0 |

Actual binary total: **12 mesh groups, 21 nodes, 14280 triangles**; all oriented source triangles and exact per-corner float32 UV0 survived export. Every node transform is identity, all variants keep the contracted bounds, and one shared material references exactly three embedded2048² PNGs. Full numeric evidence is `delivery_report.json`.

## Texture and editable-source contract

One shared `MaintenancePaving_SharedPBR`; all eight variants share one **2048²** atlas. Native source outputs: BaseColor sRGB, Roughness/Metallic/Normal Non-Color. The standard glTF exporter packs roughness/metallic into G/B, resulting in **three shared embedded 2K PNGs**. No AO is invented or baked from source lighting. Worst-case RGBA8 storage including a full mip chain is approximately **64MiB** for all eight variants together; actual engine import memory remains to be measured. Atlas texel density is lower than eight separate 1K sets; default 720p and near-camera images determine whether a future local increase is justified.

The source's SourceUV, ConcreteUV, dedicated module-root coordinates, actual wear masks and image bytes stay unchanged. Copies receive a single globally packed DeliveryUV; only a temporary joined object is baked, using the established courtyard native EMIT/NORMAL workflow. This does not use per-piece Generated coordinates. UV checkpoint and completed channel hashes allow resuming after a bounded failure without silently rebuilding UV or rebaking finished channels. `baked_editable.blend` retains independent copied pieces and the original author pieces; the frozen P3 source is never saved over.

## Entry and evidence

After root's explicit window: `python -X utf8 asset_sources/v3/i2_maintenance_paving/delivery_p3/run_delivery.py`.

CPU2, own process tree hard limit300s, fresh timestamped stdout/stderr. Actual first run was78.141s for four passes, export/readback and two images. The successful frozen delivery must not be overwritten. A failure would retain UV/channel checkpoints; no automatic retries or engine execution.

Binary validation reuses the frozen courtyard `delivery_p2/read_glb.py`, checking names, hierarchy, identity transforms, every oriented triangle/UV corner, 2K image roles and source hashes. The same GLB bytes are imported into Blender for single W1 and eight-tile images under the original P3 source rig. These remain offline images; root alone copies runtime files and checks Godot import, shared texture reuse, lighting and real existing geometry/ability routes.
