# Calibration rack P1 — static source plan

Reference `references/v3/production/canal_calibration/rack-p1.png` was actually viewed. It is an AI single-object reference, not a game image. Follow its low teal steel perimeter, inset grey steel working surface, worn yellow border, flush covers and fasteners. Reduce dense checker/scratch noise; no drone, rail, power cable or new mechanism.

## Geometry and editable source

- Godot local bounds `[-1.2,1.2] × [0,.32] × [-1.2,1.2]`; origin at ground centre. Source conversion is Godot `(x,y,z)` → Blender `(x,-z,y)`.
- Closed base, four separate rim bars, three landing plates and a service strip, four corner guards, six side covers and editable hex fasteners. Top fasteners sit in actual shallow counterbores, not concealed below an uncut plane. All stay at/below Y .32.
- Top geometry is flat at .32, except visually shallow joints/counterbores below that level. Existing conservative full-box contact/RID is owned by root and unchanged.
- Approximate 3k–5k triangles, three source materials. Actual count/AABB and per-part closed-edge checks are authoritative; no fixed invented triangle equality.

## Material and UV

- Read-only approved pump atlas V2 lower-right teal quadrant, cropped as 8.5m × .8m authored beam-strip coverage. No other quadrant, perspective concept or rendered shadow is projected.
- Reuse local ambientCG Metal012 Color/Roughness/Metalness/NormalGL from its licensed original images. No vendor blend/scripts loaded. Colour sRGB, data Non-Color; steel normals explicitly use SteelUV. 1.2m sampling is this prop's art setting, not a claim of measured source scale.
- Metallic response belongs to actual steel; paint is dielectric except exposed patches. Yellow is a broad 79mm border plus two small alignment ticks, with limited edge wear. Sparse 160mm anti-slip pattern is <=1.1mm source bump, not raised blocking geometry.
- Explicit MetricUV, PanelUV, FinishUV, SteelUV and TopUV plus SurfaceUse corner attribute allow later native baking without Generated/Position dependencies. All UV handles acquired after layer creation.
- Input copies keep original bytes; before save resolve absolute paths and force real pixel loading, then reopen the saved blend and hash/check images again. ERROR log means failure even if Blender returns0.

## Planned delivery after source review

This entry only builds editable source and one complete isolated oblique render. Expected 60–110s CPU2, hard180s. No engine execution yet and no GLB/runtime writes. Next authorized delivery can copy evaluated pieces, preserve original source attributes, add independent BakeUV, bake BaseColor/ORM/Normal into 1–2K native images, merge runtime shell/deck into 1–2 identity meshes and explicitly export GLB in this source directory. Actual game camera/occupied/empty rack review belongs to root integration. No production asset path is currently writable.
