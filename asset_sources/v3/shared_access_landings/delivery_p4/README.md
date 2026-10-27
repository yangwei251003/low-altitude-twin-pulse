# Fixed landing P4 delivery candidate

Status: corrected GLB exported, raw binary verified and same-byte Blender reimport rendered and inspected in two unchanged cameras. Candidate bytes are frozen for root integration review. This is not Godot integration, gameplay collision validation, or final art acceptance.

Candidate: `shared_access_landings.glb`, 6,792,256 bytes, SHA256 `4aa040cff1325e9881387b23b7b6698f097ef2df6ae2b6bbcbd093a9ee23ac2a`. Editable delivery blend SHA256 `15d66de3ea9a961ea5f0f0fd2969ae1703210647ba44baffc9270b8450c59775`.

## Source and geometry

The editable approved source is `../p4/source_review_20261019_152843_ce6ff1/shared_access_landings_p4.blend`, SHA256 `726db4e2bc08ce404696c3c959269473a961a6b2e228e210609cb62f0585199d`. Its 21 construction meshes remain unchanged. Delivery merges only by the six actual fixed-body IDs, preserving the evaluated triangle geometry: 6 meshes, 12 surfaces, 13,908 triangles. No high-poly tread objects are exported.

The GLB root `SharedAccessLandings` is identity and corresponds to Godot world origin `(15,5,0)`. Mesh nodes are direct children with identity rotation/unit scale and authored translations; they are **not** all at origin.

| Node / existing body ID | Local Godot translation | Triangles |
|---|---|---:|
| WestLanding | (-4.8,-0.2,6.4) | 2660 |
| EastLanding | (4.7,-0.2,6.55) | 2660 |
| SouthBypass | (0,-0.2,13.1) | 1200 |
| WestOuterRail | (-6.55,0.5,6.4) | 2736 |
| EastOuterRail | (6.35,0.5,6.55) | 2736 |
| SouthOuterRail | (-0.1,0.5,14.75) | 1916 |

The integration should retain each authored root-to-mesh transform. For reparenting onto an existing fixed body, use `Transform(origin - authored_body_center) * authored_root_to_mesh`, not a second addition of the node translation. The existing collision bodies, their dimensions, targets, moving bridge and controls are outside this asset's scope. `node_contract.json` and `raw_glb_report.json` record expected/actual node matrices and local bounds after successful export.

## Texture budget and deliberate reuse

Two ordinary PBR materials use only `TEXCOORD_0` / `SurfaceUV`, with BaseColor, ORM and tangent Normal on the **same** UV. No alternate-UV normal extension or custom runtime shader is required.

- `SharedLandings_Deck_PBR`: three 2048² PNGs. Forty-four top plates reuse five exact dimensions × two real source wear variants. Unique top area is 29.5648m²; 288px/m gives 27.36px per 95mm tread pitch and 1.66px on the 5.76mm crest width. This does not claim unique wear over all 136.98m². The lower atlas strip contains quiet side steel, fixings and undersides.
- `SharedLandings_Coating_PBR`: three 1024² PNGs. The source material depends only on explicit `PaintPanelUV`. Source image uses EXTEND outside [0,1]; the bake covers U[-0.12,1.02], V[-0.02,1.03], then normalizes that domain to the delivery UV. Nominal source metric is 6m×1m: about149.71px/m along U and975.24px/m along V. Thin return/cap projections retain their authored crop and are not asserted to have the same physical density as broad guard faces.
- Six RGBA8 textures plus a full mip chain have an approximately80MiB uncompressed upper estimate. Actual PNG/GLB sizes are recorded after export; this is not a GPU memory measurement.

P4 retains the P3 native 512² tread normal and adds a same-pattern high-poly top/slope mask to the **source** material. Delivery bakes the resulting color, roughness/metallic and tangent normals into the ordinary same-UV maps. No normal strength inflation, lamp change or new geometry is part of export.

## Actual failures retained

1. `run-20261019_162229_e306f2`: preparation rejected out-of-unit UVs before baking. Read-only diagnosis found 106 coating triangles in two source parts, source domain U[-0.1000000015,1], V[0.00150001,1.008000016]. The source EXTEND behavior was preserved by extending the bake domain, not by dropping the range check or clamping faces.
2. `run-20261019_163111_09f1da`: channel startup rejected missing `DeckBakeProxy`. A local attribute-loop variable had overwritten the intended object name. Original script/checkpoint retained; only that variable name changed before preparation resumed.
3. `failed_missing_paint_20261019_1636`: first exported GLB SHA `042f335accf60410ba6e71af3149284aafa9e8f0c0fa55e831bf82860acd93ce` is **rejected**. Its geometry and embedded-image checks passed, but the two actual reimport images show magenta coating. Saving the intermediate blend with `relative_remap=False` had changed the meaning of a relative source paint path. Cycles logged an image-load ERROR while returning exit0. The bad GLB, maps, scripts, reports and images are preserved here.

The correction resolves all source file paths while the original blend is current, verifies bytes and actual pixels, and checks them again on channel startup. The process runner now records Cycles ERROR lines and returns failure even if Blender exits0. Only invalid coating channels are rebaked. The three deck maps retain their first byte-identical outputs: their active source graph does not depend on the missing paint image, but their original logs contained the unrelated global coating-load error and are not represented as clean runs.

## Running and evidence boundaries

`run_delivery.py` defaults to preparation instructions and starts nothing. With a root-allocated engine window, `--run-authorized-stage` runs exactly one hidden CPU2 process tree with a240-second timeout: `prepare`, the six named material/channel combinations, `export`, or `preview`. Successful channel entries in `bake_report.json` are hash-checked and skipped. Failures are retained before any correction.

The final preview reimports the exact GLB bytes into Blender and uses the same approved source 02/03 cameras and lights. It validates six meshes, material/image presence and root bounds, then renders the whole delivered geometry. This cannot establish actual Godot import, original collision retention, default gameplay readability, occlusion fade, or performance. Those remain root integration checks.

Final corrected run records: preparation PID44272 (5.86s), coating PIDs27196/4100/19084 (1.657/1.687/2.187s), export PID1544 (4.204s), reimport/render PID24632 (73.610s). All naturally exited0 within their240s tree limit with no captured engine ERROR. Export emits two standard sampler warnings for the ORM image reused by separate roughness/metallic channels; the raw GLB verifies the resulting same-UV image assignments. Old first-bake errors above remain disclosed.

The reused deck receiver fingerprint is `243b4b9b1e64633c0be1535bd48eedae791787f625757f804bf12a2dc8e2955c`: all32,052 vertices,10,684 receiver triangles, every source/delivery UV and WeatherUse value, material indices,122 reachable source nodes and image bytes match the previous checkpoint exactly. This establishes why its three maps are reused despite the unrelated image-load error in their old logs.

Visual readback: blue-green coating and irregular lower-edge wear are restored; the full U remains open and the southwest join does not show a new hole or floating guard. Tread and bolt marks remain visible in the closer view. Repeated plate wear and repeated lower-guard damage are still detectable; distant tread is fine and may lose readability under the game camera/mips. No appearance adjustment was made after root's P4 approval. The two images are `same_byte_reimport/02-fixed-assembly.png` and `03-south-west-junction.png`, explicitly offline Blender renders.
