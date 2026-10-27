# P3 measured material correction — same source geometry and view

P2 was actually rejected by root and maker for light silver deck, cream yellow and near-solid teal. No bake/export. Actual image statistics in read_only_material_statistics.json show Metal012 RGB sRGB mean(.838,.866,.898), metalness1 everywhere, roughness median.08235. Therefore P2 actual steel base was linear(.268,.286,.297), roughness median.573, not dark rough steel. Emission0, original colour/data spaces and saved image pixels are correct. Fixed AgX/lighting reflect this comparatively bright metallic base; no exposure/world/light change is made.

P3 preserves all51 source parts,4740tri,positions,allUV,corner normals,polygon material indices,camera and light. Only known P2 material slots are replaced by identity; unused empty slots are retained. P2 original SHA is checked before and after execution.

Steel uses original colour multiplied by(.075,.075,.070), retaining its source variation (expected mean roughly.050,.054,.055), pure metal unchanged; roughness .62+.80*original, median about.686. This is a stylized old-steel reflectance choice, not a measured physical claim.70mm alternating ribs remain, now2mm Bump distance/strength.85, after NormalGL/SteelUV; actual connections and top mask checked.

Yellow uses lower-value saturated linear(.32,.13,.0015), roughness.80 and Specular IOR Level.12 only under yellow paint. This explicitly limits white highlight/AgX desaturation rather than changing lighting. Its final appearance still requires the actual PNG.

Teal uses a darker base and restrained existing atlas variation. Discontinuous corner/edge masks reveal bounded steel/rust patches; only two unequal vertical oxidation traces start under actual front upper bolts. No additional image or geometry, no full-field cloud/noise. Source bump is not collision geometry.

Entry: python asset_sources/v3/canal_calibration_rack/p3/run_preview.py. Existing dev.execute_command hidden Windows private Job CPU2/hard120s, expected70–100s. One original camera render, no bake/GLB. Actual image decides material progress; numeric checks do not grant art acceptance.
