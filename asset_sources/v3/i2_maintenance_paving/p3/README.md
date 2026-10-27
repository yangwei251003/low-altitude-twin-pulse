# Maintenance paving P3 — static material comparison

Status: **prepared, not run**. Requires root's CPU2 window; no baking, GLB, Godot or runtime writes. P1/P2 remain frozen.

`build_material_p3.py` opens the exact P2 editable blend; it does not reconstruct geometry. It compares exact mesh/UV/hierarchy/transform/material-slot signatures before/after editing and after reopening the saved source. Existing two source cameras, lights, world, exposure and sample count are retained. The second shot changes only the same resolution/orthographic scale used by P2.

- Concrete: source image is sampled through unchanged 4m world-metric ConcreteUV; in linear colour, multiply by .45, then mix 72% of that result with 28% of (.12,.13,.125). Existing authored wheel marks, joints and refill materials stay independent. No new noise or derived normal/AO.
- Cover paint: original approved steel PNG is copied byte-for-byte, sRGB. UV window U .02–.98 / V .60–.92 selects image rows 8–40% from the top. The heavy lower peeling is excluded. The ~4m longitudinal / .45m transverse mapping uses module-root coordinates, not per-piece Generated coordinates. Identical 4m source can repeat; this is not a claim of unique eight-piece weathering.
- Paint and pictured oxide are nonmetallic. Only the existing explicit cover-edge/grip exposed-metal mask drives metallic .65; the original edge/grip mask and physical parts are retained. Independent fasteners remain unchanged.

Original approved image: `references/v3/production/shared_access_bridge_deck/painted_steel_material_v1.png`; local untouched copy `source_inputs/painted_steel_material_v1.png`, 2172×724, 2,631,351 bytes; SHA256 `2ab3fdfab826eddf4736f92c34faeece79ff76278144a0430943a2924d6f50be`. Full input hashes are in `contract.json`.

Static check: `python -X utf8 asset_sources/v3/i2_maintenance_paving/p3/check_prepared.py`.
Only after the authorized window: `python -X utf8 asset_sources/v3/i2_maintenance_paving/p3/run_preview.py`.
The wrapper owns only its Blender tree, CPU2/240s, preserves stdout/stderr and uses `--python-exit-code 3`. Expected source two-image duration about 75–100s based on P2's actual 70s, not a guarantee.

Expected outputs: `maintenance_paving_p3.blend`, `evidence/production_report.json`, `evidence/maintenance_single_p3.png`, `evidence/maintenance_eight_tile_layout_p3.png`. These are offline authoring images; only actual images and root review can establish whether the bright-patch issue has improved. No aesthetic acceptance is implied by signatures or source mesh checks.
