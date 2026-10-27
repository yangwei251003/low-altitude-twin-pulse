# Actual same-byte reimport review

Reviewed on 2026-10-20: `same_byte_reimport/01_reference_oblique.png`, SHA256 `e87d0df02fe6e3396944d383593c67b82315655b3f0d9f95a137b09ecbd3cb57`. Actual GLB SHA256 is `19ce8114fdd7f6d3a3c8c991db2cee1ee12cffc9113d1a14f7fd0d92dc0e8de9`. The camera/light are the frozen P4 source setup.

- The low steel platform, four top panel divisions, bolts and blue-green frame survive export. The anti-slip rib pattern is visible on all four top panels; it is subtler than the true high-source relief, which is expected to require actual game-camera review.
- The model has no observed magenta missing images, broad black normal rims, or gross texture projection errors in this view. This is a single-view observation, not exhaustive surface or engine proof.
- The yellow markings remain readable but are lighter than the source shader. The standard glTF metallic/roughness material does not preserve the source's variable dielectric specular texture. No exposure or color adjustment was made to hide that difference.
- Steel remains somewhat uniform, and a few paint chips remain round. These were previously recorded by Root; no new offline iteration is justified before the requested 26 m, near and occupied/empty game views.

Root independently viewed the returned GLB render and accepted it for Godot candidate import, specifically noting that shallow ribs, panel seams and frame were preserved. Root then authorized a byte-identical candidate copy. This decision does not approve the whole scene, prove game lighting or validate the work-chain interaction.
