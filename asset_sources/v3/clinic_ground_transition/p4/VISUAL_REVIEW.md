# P4 — rejected; material-path diagnostic only

Actual fixed-camera PNG was viewed by author and root. PID 24124 exited naturally with code 0 in 47.4716 seconds. No GLB was exported. Geometry/UV digest remained identical to P3.

P4 did change the real baked BaseColor: main-1 mouth RGB 93.70/84.54/72.41 → 80.52/72.99/63.53. However, main-1/2 midpoints moved only about 1–3/255 and branch-1 stayed approximately 113/102/88. The new mapping does not create a continuous sediment bed. The ORM and Normal PNGs are byte-identical to P3. Actual wet roughness remains about .60–.75, dry .86. Four dry reference samples stayed unchanged.

Evidence: `wet_pixel_trace.json` reads the actual saved .blend SDNA positions/corners/UVs/attributes, maps the same 14 world points to the real PNGs; `p3_p4_pixel_comparison.json` compares original bytes and pixels. Shader reconstruction is approximate because filtering differs; actual PNG samples are the measured evidence. No image was edited, and no Blender/Godot process ran for this readback.

Visual failure is broader than wet darkness: near-uniform small bright granules across the soil; no clearly separate quiet silt floor; only 24 isolated small chips; broken concrete lacks clustered exposed coarse aggregate; the standalone buried skirt reads as a cut block. The skirt is a closed underground support intended to meet the surrounding ground at Y0, but this intention is not actual integration evidence. Do not delete its side faces to hide the source view.

P5 must change surface composition and useful geometry, not merely increase the wet scalar. P1–P4 remain historical rejected candidates. No game visual or physics acceptance is implied.
