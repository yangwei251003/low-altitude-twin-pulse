# P7 — REJECTED_ART, no GLB

The single CPU2 run ended naturally: PID 26160, exit 0, 113.7813 seconds. No later Blender/Godot process was started by this agent. The original preparation README and all production bytes are retained; this review supersedes its pending status.

Both `evidence/transition_source_p7.png` and `evidence/transition_contact_close_p7.png` were actually viewed, and root independently compared them with the approved V2 reference. The medium stones now have visible sides, varied facets and contact shadows. This fixes the shallow paper-chip reading, but does not pass the asset: the sediment still reads as roughly six narrow pale bead strings over broad plaster-like soil. Mixed grains do not form the reference's connected, unequal-width deposit, and the three low-density channel beds are insufficiently separated from that surface.

Measured source remains 7,638 low triangles / 159 editable parts, with 760 high-only grains / 15,200 triangles excluded from runtime. Bounds and 164 source geometry checks passed; these are not game physics or visual approval. Named large-fragment vertices protrude 52.3–73.2mm above the actual local soil (global upper bound remains +27mm). Medium placement-formula protrusions are 26.9–52.6mm; that statistic is explicitly analytical rather than a full per-vertex soil measurement.

Normal mapping is connected as tangent/OpenGL, strength 1, with BakeUV and Non-Color input. AO was genuinely baked from joined ground/stone geometry (Only Local, 8cm distance, 16 samples), not painted into albedo. The preview multiplies the same ORM R through a separate preview-only material; the retained standard material uses glTF Occlusion. Exact Blender/Godot AO lighting equivalence is not claimed. At 65 selected fine-grain UV samples AO ranges 0.593–1; this is sampling, not an all-surface darkness guarantee.

`orm_repack_check.json` resolves the global roughness comparison outlier: all 1,443,247 rasterized UV-face pixel centers preserve G/B exactly. The maximum G difference of 153 is outside UV-face coverage in repadded margins. Filtering at island boundaries remains a later actual-engine concern, not evidence that every unused PNG byte stayed identical. The original maps and diagnostics are preserved.

Subsequent read-only projected coverage is in `../p8/p7_coverage.json`: actual saved low/high triangles rasterized at 5mm, exposed by more than 1mm above saved soil. Fine grains cover 0.3905m² / 4.20% of 9.2923m² soil; combined grains cover 1.0267m² / 11.05%. The old narrow bank domain is only 2.0563m² and already has 40.43% combined coverage. Thus merely packing the same narrow strips more tightly is not the next method. These are top-down geometric measurements, not camera appearance or a calibrated reference-image mask.

P7 is frozen as a rejected but useful thickness/AO baseline. No candidate GLB, coarse collision delivery, gameplay integration or performance approval was produced.
