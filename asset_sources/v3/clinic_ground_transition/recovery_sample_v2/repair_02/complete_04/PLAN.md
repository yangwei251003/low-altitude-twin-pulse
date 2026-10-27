# Complete04 — explicit delivery tolerances

Root-authorized limits: position/cut-edge rounding <=1e-5m; interpolated UV <=1e-5; decoded normal <=0.1deg using Python-double atan2(cross,dot). Combined actual float32 overlap/gap residual must have maximum minimum-caliper width <=1e-5m AND summed area <=1e-6m²; every residual polygon and measured width/area stays in evidence. No bitwise normal or perfect mathematical closure claim.

All unknown changed faces, winding, zero triangles, actual UV overlaps, source maps/hashes, untouched top geometry/UV, original footprint, material and projection identities remain strict. Exact unchanged-data comparisons stay exact; dimensionless barycentric/intersection self-checks stay algorithmic assertions, not artistic delivery thresholds. Raster rejects zero/nonfinite UV area rather than rejecting nonzero subtexel UV triangles by arbitrary area. Cage interpolation equivalence uses the same1e-5m position tolerance; source cage itself unchanged.

One CPU2/240s boundary + same-group selected AO with all-high occlusion + two original-camera high/low renders. No Normal/BaseColor rebake; no export/runtime. All old failed runs immutable.
