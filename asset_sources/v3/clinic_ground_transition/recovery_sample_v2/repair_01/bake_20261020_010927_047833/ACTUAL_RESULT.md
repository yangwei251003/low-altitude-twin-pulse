# Matched-group normal bake — actual result

Blender PID 10888 naturally exited 0 in 30.500 seconds (CPU 2, private hard limit 180 seconds), with no log ERROR and no residual Blender/Godot process at release. Engine window returned immediately. No render or export was launched.

The saved 11-group prepared input matched its successful 1,965-pixel preflight hashes. Selected-to-active Normal was baked separately for each matching group with the fixed original 35 mm cages; raw margin 0, native final composition margin 1 EXTEND. No geometry/BakeUV/camera changes were made. Low geometry remains 9,578 triangles; high 146,026. Original top/side/bottom/solid failure evidence remains intact.

- All 1,965 former negative-Z normal samples are now nonnegative (top 1,550; side 396; solids 19). Across all actual occupied top pixels, negative tangent Z decreased from 1,550 to 0.
- Original AO was retained exactly at all 543,605 strict interior occupied pixels: maximum channel difference 0.0. AO and Normal both remain connected in the saved material.
- Normal remains nonneutral where high geometry differs: occupied RGB standard deviation [0.01664656, 0.01663258, 0.00385398]; occupied B range [0.76078439, 1.0]. This is not deletion of the Normal map.
- The copied high side source UV remains nonzero (Rocky 2 m / Sandy 2.5 m sampling); explicit side source maps were rebaked. Original source images remain unchanged.
- All 13 raw and 3 final PNGs were decoded after the process exited and checked against their saved dimensions/bytes/SHA. Three final maps are 1,024 square: BaseColor sRGB, Normal/ORM Non-Color.

The three raw final maps were visually inspected: no magenta missing-image regions; Normal retains top relief and AO retains its contact variation. UV-map viewing is not a rendered object review. In particular, the remaining top-border normal patterns and side material continuity still need the locked high/baked camera comparison before any visual conclusion. Saved blend SHA was checked; a separate final reopen/render has not run.

Output source: baked_repair.blend, SHA256 08367900ac296f819ca02fcbce478a777bf422d4403a9c7c5650568597554110.

This is a successful numeric bake stage, not visual approval or a completed game asset.
