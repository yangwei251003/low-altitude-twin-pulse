# P9 — scan-based soil surface; static preparation only

Route `5e455d78-37b2-423b-b660-0cc3185eae49` reused. Root rejected P8 after viewing both images; its source and failed attempts are frozen. No Blender/Godot run or candidate export is authorized yet for P9.

## One acquired material

Official [Sandy Gravel 02](https://polyhaven.com/a/sandy_gravel_02), by Dario Barresi, is listed at 2.5m width and [CC0](https://polyhaven.com/license). Only its actual 2K PNG Diffuse, OpenGL Normal and Roughness were downloaded through the public API's exact asset URLs. No preview image, executable, blend, script, scene or additional material was downloaded. The three original files total 54,311,782 bytes and each official MD5 matches; SHA256, author, license and exact URLs are in `vendor/polyhaven_sandy_gravel_02/provenance.json`. Original API responses are retained.

All three maps were actually viewed. The diffuse contains coherent sandy soil, sparse small pebbles and naturally changing bare patches, with a warmer orange tone than the chosen I-B reference. It is suitable as the **soil base**, not a replacement for the fractured concrete, true coarse stone geometry or whole scene. The normal and roughness correspond to this fine surface. The optional second material is unnecessary at this stage.

## Material/build plan

1. Retain P7/P8's identical 7,638-triangle low geometry, existing boundary, actual grooves, thick coarse stones and embedded fracture aggregate. Remove the entire high-only fine-grain layer and its deposit mask; no 5,000-particle substitute. Keep the editable low parts and exact geometry comparison.
2. Create explicit `SoilScanUV` at 2.5m per repeat using the existing dominant-face metric coordinates. The top uses real X/Z; sides retain their own face projection, avoiding vertical stretch. All three source maps share this same UV and fixed offset. The saved source remains the authoritative physical scale; no screen-space projection.
3. Diffuse is sRGB; normal and roughness are Non-Color. Use a standard Principled shader, metallic 0, emission 0, OpenGL tangent normal bound to `SoilScanUV`. A modest saturation reduction neutralizes orange while retaining the actual scanned variation; no flat color mix that removes the scan's structure.
4. Existing continuous wet/silt controls drive a modest albedo multiplier, lower roughness and weaker micro-normal in channel beds. There is no binary boundary between pebble pictures and blank mud, no mirrored plaster bands, and no new procedural speckle layer. Real low geometry still supplies channel depth and coarse-stone silhouettes.
5. Native low-source baking transfers this material to the asset's unique BakeUV BaseColor/ORM/Normal. Retain genuine contact AO from ground/coarse-stone geometry, with separate Blender preview and standard glTF AO materials. Source maps stay byte-for-byte untouched. No external pixel editing.
6. Reopen the actual saved blend, verify image paths and color spaces, compare low geometry to the frozen source, then render the same full/close cameras. Judge scan scale, repeated distinctive patches, warm/cool balance, wet-bed continuity and remaining repeated coarse-stone placement. A sourced PBR is not itself artistic approval.

Expected future CPU2 bake plus two images: about 100–150 seconds; bounded runner proposed at 240 seconds only after root releases the engine window. No runtime or candidate GLB is written in this preparation stage.
