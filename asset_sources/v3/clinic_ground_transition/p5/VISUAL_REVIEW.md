# P5 actual fixed-camera source review

Author opened `evidence/transition_source_p5.png` after the completed run and compared it with the original approved V2 single-object reference and P4 actual preview. This is a Blender CPU source render, not a Godot screenshot or a complete visual acceptance.

- Three main runoff beds now read as continuous directional paths, with subordinate branches and fading ends. This is a visible improvement over P4; it comes from distinct fine-silt/gravel zones and matching shallow geometry, not only a lower wet color value.
- Dense small bright granules no longer dominate the entire soil plane. The new source atlas was generated natively and copied without pixel edits; it is only an albedo source. Geometry creates the real channels, while roughness and tangent normals are native material outputs.
- Real embedded aggregate now appears at four unequal fracture areas, with larger fallen pieces. However, the fracture still reads as a relatively thin row, less thick and interlocked than the reference. Fallen fragments remain rather sparse and light gray. Do not claim the rough break is fully restored.
- Channel floors look somewhat smooth/brush-like. Their direction is readable, but the reference has richer low-frequency sediment and adjacent aggregate hierarchy. No further self-directed parameter iteration was launched.
- The outer closed skirt is below surrounding Y0 and still looks like a cut block in an isolated studio render. Only an actual ground cut/flush installation can show whether it is invisible as intended. This is not permission to delete the skirt or fake the integration with a flat overlay.

First attempt PID 38252 stopped before baking: one 3.8 cm embedded fragment had less than the required 3 mm insertion at a sloping edge. `failed_floating_aggregate09/` preserves its script, actual .blend, report and raw logs. Read-only actual 12-vertex diagnosis found about 2.03 mm original insertion. Only that fragment moved 3.966 mm along the local inward edge normal; size/height/other pieces/checks did not change. The corrected model has four inserted and four exposed vertices for this fragment.

Corrected run PID 40600 exited naturally with code 0 in 49.0543 seconds. CPU2/180-second own-tree limit. Geometry: 6,786 triangles, 55 editable pieces, 61/61 source checks. Bounds Godot min `[-3,-0.1800000072,0]`, max `[3,0.0055700634,2.3987879753]`. The output .blend was actually reopened and five image paths resolved with `bpy.path.abspath`; original image SHA and sRGB/Non-Color roles were read back. P3 helper and P4 manifest remained unchanged.

No GLB, CollisionSurface or actual gameplay acceptance was produced by this round. Root must review the source image before export; new collision must be derived from P5, not copied from rejected P2. The 61 source checks do not prove visual quality or engine physics.
