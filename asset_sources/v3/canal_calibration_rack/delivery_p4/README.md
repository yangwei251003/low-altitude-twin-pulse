# Calibration rack P4 — frozen candidate delivery

2026-10-20: Root personally reviewed the same-byte Blender reimport image and accepted this object for **Godot candidate review**. This is not an occupied/empty gameplay, collision, performance or whole-area art acceptance. Root owns integration and the original physical box. No more offline material iterations are scheduled.

## Open or import

- `calibration_rack_editable.blend`: editable source, 51 original low parts plus four high plate copies and four editable rib groups. Keep `source_inputs/` alongside it. Actual reopen resolved all five relative image paths with SHA, dimensions and pixel reads.
- `calibration_rack_delivery.blend`: two baked runtime meshes with the review studio. Its six external maps are under `textures/`.
- `calibration_rack.glb`: selected identity root `CalibrationRack`, two meshes; no studio, collision, animation or rig. Byte-identical copy is at `assets/v3/candidates/canal_calibration_rack/calibration_rack.glb` relative to the project.
- `same_byte_reimport/reimported_candidate.blend` and `01_reference_oblique.png`: actual unchanged-GLB reimport and original camera/light comparison. This PNG is a Blender render, not a game screenshot.

Candidate: **6,139,216 bytes**, SHA256 `19ce8114fdd7f6d3a3c8c991db2cee1ee12cffc9113d1a14f7fd0d92dc0e8de9`.

## Runtime contract

| Mesh | Triangles | Opaque material |
| --- | ---: | --- |
| `DeckSurface` | 944 | `CalibrationRack_Deck_PBR` |
| `StructureAndHardware` | 3,796 | `CalibrationRack_Structure_PBR` |

Both meshes and their root have identity transforms. Ground-centred origin; local X/Z nominal ±1.2 m, Y 0…0.32 m. Actual binary AABB is `[-1.2000000476837158,0,-1.1999999284744263]` to `[1.2000000476837158,0.3199999928474426,1.1999999284744263]`. Total 4,740 triangles preserves the original low geometry. P4's 1,137 high-only ribs are represented in the tangent normal texture; they do not add individual gameplay collision shapes.

Deck uses three native 2K PNGs; structure uses three 1K PNGs. BaseColor is sRGB; ORM/Normal are Non-Color. ORM G is roughness, B metallic; occupied R is neutral 1, with no AO measurement claim or unnecessary glTF occlusion binding. Normal is tangent +Y. All six PNG byte streams are embedded unchanged in GLB. Structure normal is neutral; its bevels remain actual low geometry. Deck normal has 4.939% of occupied texels with RG deviation above 8/255; actual image inspection confirms the rib pattern.

## Evidence and limitations

`raw_glb_report.json` verifies exact source triangle multiset/winding, identity transforms, UV0/tangents, PBR bindings, six embedded images and AABB. Position error is zero; UV maximum error is 2.98e−8. Raw exported normal difference is 6.20e−5; after the installed exporter's float32 four-decimal normalization rule it is 2.98e−8. Raw and interpreted errors are both preserved.

All three private Windows Job stages used CPU2 and ended naturally with no log ERROR or owned residual process:

| Stage | PID | Wall seconds | Hard limit |
| --- | ---: | ---: | ---: |
| Bake | 43688 | 126.594 | 180 |
| Export | 27176 | 5.172 | 90 |
| Reimport/render | 39856 | 61.734 | 120 |

Read `ACTUAL_REVIEW.md` for the visible result. Steel remains relatively uniform and some paint chips are round. Standard metallic/roughness export does not encode the source's variable dielectric specular texture; the yellow reads lighter in the reimport image. These are explicitly retained for actual-camera judgment, not concealed by an offline regrade.

## Reproduction and provenance

`run_stage.py` records each stage's script snapshot, logs and process report. `bake_complete.blend` retains the baked intermediate. The current successful output files are frozen: the export script intentionally refuses to overwrite an existing candidate. For a later authorized revision, use a new delivery directory rather than rerunning into this one. Stage commands are `python -B .../run_stage.py bake|export|preview`, with Root's exclusive engine window required.

Source steel maps are ambientCG Metal012, by Lennart Demes, CC0-1.0: https://ambientcg.com/view?id=Metal012 and https://docs.ambientcg.com/license/. Only original images were used; no vendor executable or material script was loaded. The source's approved 1254² paint image was generated using native imagegen for the pump-shell atlas and reused locally; it is color information, not measured height. Copied provenance records and exact prompt are in `provenance/`. The original rack reference remains AI reference art, not a screenshot.

`manifest.json` is a selective freeze of the useful editable, baked, GLB, render, script and provenance evidence. It records external frozen P4/reference inputs separately and the candidate copy's exact hash. It deliberately excludes `.blend1`, repeated checkpoints and rejected prior-version directories, which remain untouched in their original locations. `PLAN.md` and stage reports preserve their historical pre-execution/pending-review wording; this README records the current delivery decision.
