# Fixed landing source P1

Reference V1 approved by root on 2026-10-19 for editable-source development only. No runtime asset, collision replacement or final art acceptance.

`geometry.py` is pure Python and generates ten true-size floor modules plus eleven folded guard modules. Six source body groups retain the production floor/rail envelopes. Root is world `(15,5,0)`, source local Y0 is the original world Y5 walking top. The west/east widths remain 3.6/3.4m; south is two 3×3.4m modules. Positive-Y geometry is only in the original three outer rails. No pillar, rail track or target is duplicated. Corner bearing shoulders are clipped to meet without overlapping top faces.

The source reuses P4 bridge closed primitive and explicit UV/material methods, copied into this independent directory. Original files remain read-only. Two source materials: dielectric teal paint with localized exposed substrate, and rougher warm gray walking steel. The approved original painted-steel PNG remains byte-identical. Guard U is distance/6m and V is height/1m; shorter/longer modules crop the same scale instead of mapping the whole image to each new width. End faces use an intact-paint crop. Real tread pitch is 380mm, tapered relief 1.5mm, one mesh per semantic module, not one object per tread. There is no white edge material.

`build_source.py` makes a full editable `.blend` with six named identity groups and 21 mesh objects. It uses restrained editable bevel/weighted-normal modifiers and unique explicit `SurfaceUV`, `SourceXZ`, `SourceY`, `PaintPanelUV` layers plus `WeatherUse` corner data. It is only source shading; no PBR baking/export.

Three planned source views: isolated EastLanding_01 with its single guard (other production modules explicitly hidden for that view), full fixed U assembly, and the southwest joining detail. The source `.blend` is saved with all 21 modules present and visible. Studio lighting/cameras/floor are a separate removable collection. These are offline source previews, not game screenshots.

Plain-Python structural checks cover closed outward construction pieces, each module in its original body, exact areas and no doubled walking tops, plus four unrailed bridge interfaces. Intended weld/fastener intersections and coincident internal contact faces between separate pieces are not a Boolean-union topology proof. No new runtime sweep claim.

Only after root gives a serialized window:

```powershell
python -u asset_sources/v3/shared_access_landings/p1/run_source.py --run-authorized-once
```

The launcher hides Blender, restricts CPU to two threads, writes full stdout/stderr and PID, and enforces a 240s wall-clock limit on its own process tree. It creates a unique output/evidence directory and refuses overwriting prior output. A failure is reported before any repeat. No Godot/UDP/GPU process is started by these scripts; Cycles is explicitly CPU.

At static preparation, 66 source checks pass, 21 meshes/15,956 pre-bevel triangles/696 sparse treads. Actual Blender evaluated counts/materials/UVs/images remain unverified until the allocated run.
