# Actual V2 diagnosis — Normal path causes the added black rim

All four original PNGs were viewed. **01 N1/A1 and 03 N1/A0 retain the added black rim; 02 N0/A1 and 04 N0/A0 remove it.** AO is not the main cause. Disabling the complete normal map is a diagnostic, not an accepted final repair. Existing geometry relief remains visible without the normal map. The soil side-wall stretch persists in all four images.

The 01 baseline has **exactly identical RGB pixels** to the frozen original low render (PNG metadata/hash differs). The same camera, light settings, geometry, UV, and original image hashes were checked throughout. No blend was saved, geometry changed, or texture rebaked.

## Execution and preserved script failures

- Numeric first attempt: PID30788, natural exit3, 6.937s. Blender `calc_tangents` rejects the original LowFull's n-gon concrete caps. Exact inputs/logs retained in `numeric_20261019_232350_824117`.
- Minimal diagnostic correction: create **unlinked temporary meshes** from the actual loop triangles, copy every UV and original corner normal, then compute tangents. No scene object is replaced. PID25072 natural exit0 /14.329s in `numeric_20261019_232615_261200`.
- Cage provenance correction: temporary triangulation changes vertex-normal cage offsets by up to0.431131mm, so rays now use the frozen original LowGround vertex normals. PID28832 natural exit0 /14.156s, final numeric evidence in `numeric_20261019_232812_450170`. No actual bake cage or model was modified.
- Four views: PID44132 natural exit0 /157.625s, logs0ERROR, `switches_20261019_233016_946791`. Engine window explicitly returned after exit; no residual Blender/Godot process was found.

## What the numbers distinguish

1. LowGround vs LowFull: all8,960 ground triangles match position/UV;26,880 corner samples,0 bitangent-sign flips. Max normal/tangent difference≈0.033° (temporary normal copy≈0.038°). This does not support a large merge-induced tangent flip.
2.6,854 recorded boundary/abnormal samples include933 mapped normals angled>60° from the low split normal;729 are outer-edge top samples.114 have AO<0.2. These are diagnostic classifications, not new acceptance thresholds.
3. The independently reconstructed original35mm cage rays did **not** cross top/side/bottom surface class in those samples. This is not a trace of Cycles internals and cannot prove the actual bake had no misprojection. At a representative top sample `(x=.01378125,z=.89959234)`, raw normal RGB≈(.062745,.501961,.258585) implies118.903° deviation, while the reconstructed hit face differs only0.295° and lies2.768µm from the low sample. The map carries a bad orientation there; the present evidence does not yet uniquely separate bake projection from UV-edge padding contamination.
4. All512 vertical soil closure triangles have zero source RockScanUV and SoilScanUV area; BakeUV itself has area. Horizontal source projection collapsed the height dimension. This establishes the side-stretch cause independently of the Normal/AO comparison.

## Scope of the next bounded preparation

Root reviewed the four images and authorized static preparation inside a new `repair/` subdirectory only. Keep AO, true relief, camera, footprint and original image bytes. Read back explicit BakeUV node names/active render state, rasterize actual triangle UV pixel occupancy (not just centroids), classify neighboring UV islands/padding and source/low sharp-edge triangulation. Only after that evidence supports a cause should the single necessary normal/UV repair be run. Side correction uses true metre-based face projection; it must not hide or crop the side. No P14, GLB, runtime write, new source image or installed tool.
