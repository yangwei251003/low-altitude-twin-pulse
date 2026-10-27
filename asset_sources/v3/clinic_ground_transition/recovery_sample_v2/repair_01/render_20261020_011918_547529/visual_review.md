# Same-camera high/low review

Actually viewed this run's 01_high_source.png and 02_low_baked.png, plus original recovery_sample/bake_preview_20261019_225933_382710/02_low_baked.png. Camera/lighting remain fixed at 1280x1100. This is a 0.9m offline method sample, not a game screenshot or full-transition approval.

The former ragged black perimeter along the soil top and associated scattered dark flecks are no longer visible in the repaired low render. Both exposed soil sides now show ordinary soil/gravel projection rather than long vertical stripes. Scanned mid-scale relief and the shallow channel remain; low is somewhat softer than high. Normal and AO both remain connected.

A narrow black wedge remains at the left-front concrete/soil junction in low (approximately x184..198/y607..693, top-left origin); high has thinner dark marks at the same junction. A few dark marks also remain at the fallen fragment's left base. Their exact cause is not established by this image review. No further run is authorized by this report.

The concrete is still relatively pale, its six small exposed aggregate pieces are subdued, and the rectangular diagnostic cutout is not a final transition composition. Artifact repair is not approval against the full original reference.

Blender PID22596 naturally exited0 in106.453s, CPU2/private180s limit, 0 log ERROR, 0 engine residual at release. Window returned immediately. Actual baked blend reopened; image paths/pixels, geometry/BakeUV, Normal/AO connections and camera verified. All40 frozen bake files remain byte-identical after render. The later external summary initially expected3 image datablocks but found6: each final PNG has a generated and a reloaded datablock sharing path/SHA/space. This summary-only assertion was retained and corrected to verify3 unique files while retaining all6 records; no engine rerun or source/image edit.

Source SHA256: 08367900ac296f819ca02fcbce478a777bf422d4403a9c7c5650568597554110.
High PNG SHA256: 9f066118916570e34d30e7c73202b2dd69896ace87b2409e48e62275cf0bdab9.
Low PNG SHA256: 218e8854a258148a116d392f3b49b9b21ebb08b9cf4550b37e435496f05ff428.

Conclusion: the original normal-related perimeter and soil-side projection defects show a clear repair in this controlled pair. Root review of the remaining junction marks is pending. No additional bake/render, geometry edit, GLB export or game integration was performed.
