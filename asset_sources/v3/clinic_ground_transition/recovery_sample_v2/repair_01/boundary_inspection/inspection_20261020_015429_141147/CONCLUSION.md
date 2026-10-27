# Residual boundary diagnosis — no repair performed

Actual execution: Blender PID35712, CPU2, hard60s; natural exit0 in10.469s; no log ERROR, no remaining engine process at release. All758 fixed-camera samples ran; source/map/render input hashes remained unchanged. No objects were created; no source was saved, baked or rendered.

## Left-front black wedge: real coincident exterior faces

All636 ROI samples hit both high and low. There are no sampled holes; all edges of hit triangles have two adjacent faces. High/low ray depths differ by at most0.10252mm, and nearest same-group high distance is at most0.03956mm. However153 samples choose different coincident component groups (ground_side versus solid_00).

The low soil side and concrete side both occupy the exact float32 plane X=-0.44999998807907104, facing -X. Direct 2D clipping of the actual reached triangle vertices in YZ establishes10 overlapping triangle pairs with combined local overlap0.0011702737642292106m² (11.7027cm²). This is a lower bound from the reached triangles, not a whole-model overlap survey. Concrete low triangles9073/9075/9076 overlap soil low triangles8700..8703; pair polygons and coordinates are in local_coplanar_overlap.json. The high side has nanometre-scale coordinate variations around the same exterior plane, so its coincident-surface behavior is not numerically identical to low.

Of479 newly dark low pixels,222 have sampled AO>=0.95. Their Normal is not reversed: the minimum estimated shading-normal/geometric-normal dot across the479 is0.9999507. Example screen(186,672) has AO1, neutral tangent Normal, a legitimate nonblack base colour, and high/low hits at the identical position; low is nevertheless nearly black. Therefore reducing AO or altering Normal cannot be the primary fix for this subset. The confirmed coincident exterior faces are a concrete structural defect and a strong explanation for unstable self-occlusion/overlap rendering. This is not evidence for a large low-boundary gap.

Smallest proposed direction, not executed: remove the duplicate exposed overlap locally and form one unambiguous outer cut surface, while retaining the distinct concrete/soil materials and checking closure. Do not globally voxelize, change displacement strength, or offset an entire object to conceal the overlap.

## Fallen fragment base: preserved AO is the immediate darkening term

All122 ROI samples hit both meshes; all32 newly dark samples hit ground_top in both. At those32, AO is0..0.0748033 (16 exactly0), Normal B is0.9962104..1, and all four texture taps are actual ground_top interiors, not blank gutter. Minimum estimated shading-normal/geometric-normal dot is0.993190. Maximum same-group high distance is0.696712mm; maximum camera-depth difference across the entire ROI is1.089811mm. This does not support a new large hole or another reversed Normal problem.

The vertical local sections also show real small clearance under an overhanging part of solid_07. At screen(766,447), high ground-to-fragment-bottom clearance is5.86742mm and low is6.19892mm. At(778,449), high is2.79323mm and low is3.01022mm. These are local underside clearances, not proof that the entire fragment floats or lacks contact.

The original source uses DIAG_AO only_local=True,16samples,distance35mm and originally bakes ORM by selected-to-active projection from complete HighFull with a35mm cage (recovery_sample/common.py and bake_preview.py). That full-shell projection can potentially select an overhanging underside instead of the intended ground. Current evidence establishes the extremely dark retained AO and the nearby underside, but this run did not reconstruct those exact old ORM bake rays, so wrong-source AO sampling remains a bounded hypothesis rather than a declared cause.

Smallest next diagnostic, not executed: use only the32 affected ground samples to compare the original full-shell ORM cage-ray hit identity with the matching ground source. Keep the successful Normal map and real scene occlusion; do not clear AO or paint it white merely to erase the black lines.

## Limits

Texture values are level-zero bilinear CPU reconstructions; Cycles derivative filtering can differ. The normal frame reconstruction is not an instrumented shader trace. BVH nearest distances are unsigned and are not themselves penetration depths. Local line sections and overlap polygons carry actual geometry evidence, but no global self-intersection or watertight-union certification is asserted. This remains an offline0.9m method sample, not a repaired/full asset or game integration.
