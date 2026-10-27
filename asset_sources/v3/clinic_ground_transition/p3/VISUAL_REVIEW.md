# P3 source actual visual review

Viewed the actual 1440×860 image after native Blender CPU rendering, not a concept image or Godot frame. Source render PID35044 naturally exited0 in48.05s. No P3 GLB published.

Improvements: P2 round wet spots are gone; three localized concrete edge notches and sparse partially settled chips remain coherent. Closed source bodies and native PBR checkpoints succeeded.

Unresolved: at this full-object angle the six intended wet branches and1–2.6cm rills are still difficult to trace. The material is broadly too uniform compared with the approved broken-edge/washed-silt reference. This is an art failure, not fixed by the5346triangle total or passed closure checks. Root must inspect the source image before any new run/export.

Data finding: P2 used a broad Gaussian whose tail stayed at0.55. P3 uses three longer segmented paths and three subsidiary paths; end strength reacheszero. The full source-to-proxy wet attribute remains present. ORM inspection independently shows nonconstant roughness and zero metalness. It does not establish sufficient visual area/contrast at the actual camera.

No extra model generation or parameter search has been run. Next diagnostic, if authorized, should show the actual wetmask on the same geometry and camera, plus a few sampled source positions/UV values; do not add grain or random stains to hide the gap.
