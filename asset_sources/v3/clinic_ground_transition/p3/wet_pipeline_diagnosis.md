# P3 wet pipeline read-only diagnosis

No Blender/Godot was launched. Actual compressed blend was decoded with the existing project SDNA reader and installed Git libzstd.dll, without modifying the blend. Actual BakeProxy positions, corner indices, BakeUV, MetricUV and SurfaceControl were read. Fixed Godot X/Z points were barycentrically projected into their highest actual upper triangle, then original baked PNG pixels bilinearly sampled.

| Point | formula / actual wet | actual RGB | rough pixel / expected |
|---|---:|---|---:|
| main1-mouth | 0.960 / 0.819 | [94, 85, 72] | 0.598 / 0.598 |
| main1-mid | 0.780 / 0.726 | [98, 90, 78] | 0.627 / 0.628 |
| main1-tail | 0.461 / 0.449 | [108, 98, 86] | 0.718 / 0.716 |
| main1-dry-adjacent | 0.000 / 0.001 | [108, 99, 86] | 0.859 / 0.860 |
| branch1-mid | 0.420 / 0.414 | [113, 101, 88] | 0.729 / 0.728 |
| main2-mouth | 0.769 / 0.730 | [100, 91, 81] | 0.627 / 0.626 |
| main2-mid | 0.665 / 0.647 | [104, 95, 82] | 0.653 / 0.653 |
| main2-tail | 0.369 / 0.353 | [103, 94, 82] | 0.746 / 0.747 |
| main2-dry-adjacent | 0.000 / 0.001 | [109, 100, 86] | 0.859 / 0.860 |
| main3-mouth | 0.864 / 0.794 | [91, 81, 69] | 0.607 / 0.606 |
| main3-mid | 0.748 / 0.725 | [96, 84, 71] | 0.627 / 0.628 |
| main3-tail | 0.491 / 0.473 | [96, 88, 77] | 0.710 / 0.708 |
| main3-dry-adjacent | 0.001 / 0.002 | [113, 102, 89] | 0.859 / 0.860 |
| far-dry | 0.000 / 0.000 | [119, 105, 90] | 0.859 / 0.860 |

## Cause and limits

The wet scalar survives actual corner data and native ORM bake. Roughness matches 0.86−0.32×actual_wet within about 8-bit quantization/filtering, metal remains0. Mouth attenuation (0.960→0.819 at main1) comes from finite vertex interpolation, but is not enough to explain the disappeared tail direction.

Actual source node recipe mixes independently sampled dry BL and wet BR image quadrants, with phase(.17,.23) vs(.41,.13). Soil dry =0.62×linear(0.185,0.158,0.120)+0.38×BL; damp =0.60×linear(0.095,0.083,0.065)+0.40×BR; final factor=min(1,1.08×wet). Different natural grain values partly cancel darkening. Actual main1 tail RGB108/98/86 is essentially equal to adjacent dry108/99/86; branch1 is113/101/88. This is visible albedo ambiguity despite valid wet data.

The final PBR uses BaseColor sRGB; ORM Non-Color R=1, G=roughness, B=0; normal is separate Non-Color tangent+Y. Native EMIT base/ORM bake does not include studio light. Roughness0.63–0.72 stays fairly broad and cannot independently supply a clear wet line under the diffuse review lighting. Current source camera/review environment is still offline, no Godot assertion.

Read-only author reconstruction uses actual MetricUV and source PNG samples; per-channel linear differences to baked pixel reach approximately0.014. It is an approximation because Blender texture filtering and bake rasterization differ from a point bilinear sample; not claimed bitwise shader equivalence. The actual baked pixel observations above do not rely on this reconstruction.

## Minimum proposed change, not executed

Keep P3 geometry and exact low relief. Use the same dry sample as the base of wet regions; apply a bounded multiplicative damp response (factor1 down to approximately0.48 at full wet), preserving the same grain underneath. Remove the independent wet image replacement that can brighten branches; any sediment tint should have very low weight. Keep scalar roughness separate. Do not expand random stains/scatter or darken the whole soil. Compare the same fixed wet/dry points and same source camera after authorization; do not call the proposal a verified fix.
